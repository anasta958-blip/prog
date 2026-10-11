#!/usr/bin/env python3
"""Управление отдельным сервером Ubuntu: конфигурация, запуск и резервные копии.

Использует стандартную библиотеку Python, Docker Compose v2 и GnuPG.
Не запускает shell и не исполняет содержимое .env. Секреты не печатаются.
"""

import argparse
import base64
from contextlib import contextmanager
from datetime import datetime, timezone
import getpass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SECRET_NAMES = (
    "POSTGRES_PASSWORD", "APP_DATABASE_PASSWORD", "REDIS_PASSWORD",
    "MINIO_ROOT_PASSWORD", "S3_SECRET_KEY", "JWT_SIGNING_KEY", "BOOTSTRAP_TOKEN",
)
KEYS = {"APP_DOMAIN", "FILES_DOMAIN", "TOTP_ENCRYPTION_KEY", *SECRET_NAMES}
SERVICES = ("postgres", "redis", "minio", "api", "worker", "web", "cloudflared")
PAYLOADS = {"database.dump", "volumes.tar.gz", "server.env", "tunnel-token"}


def domain(value):
    """Проверяет ASCII DNS-имя, исключая URL, порты и шаблоны."""
    if len(value) > 253 or not re.fullmatch(
        r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
        r"[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?", value
    ):
        raise ValueError("Нужно DNS-имя в нижнем регистре, без https:// и пути.")
    return value


def read_env(path):
    """Читает строгий формат KEY=value без подстановок и неизвестных ключей."""
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key not in KEYS or key in values:
            raise ValueError("Неизвестная или повторная переменная в серверном .env.")
        values[key] = value
    if set(values) != KEYS:
        raise ValueError("Серверный .env неполный. Используйте команду init.")
    for key in ("APP_DOMAIN", "FILES_DOMAIN"):
        domain(values[key])
    if values["APP_DOMAIN"] == values["FILES_DOMAIN"]:
        raise ValueError("Домены приложения и файлов должны различаться.")
    for key in SECRET_NAMES:
        if not re.fullmatch(r"[a-f0-9]{64}", values[key]):
            raise ValueError(f"{key}: ожидается сгенерированный секрет из 64 hex-символов.")
    try:
        decoded = base64.b64decode(values["TOTP_ENCRYPTION_KEY"], validate=True)
    except ValueError as error:
        raise ValueError("Некорректный ключ TOTP.") from error
    if len(decoded) != 32:
        raise ValueError("Ключ TOTP должен содержать 32 байта.")
    return values


def private_write(path, content):
    """Создаёт новый файл 0600; существующий файл, включая symlink, не заменяет."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(content)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def validate_volume_archive(path):
    """Разрешает только обычные файлы и каталоги внутри двух data volumes."""
    with tarfile.open(path, "r:gz") as archive:
        for member in archive:
            parts = PurePosixPath(member.name).parts
            if (not parts or parts[0] not in {"minio", "redis"}
                    or ".." in parts or "\\" in member.name
                    or not (member.isfile() or member.isdir())):
                raise ValueError("Недопустимый путь или тип файла в архиве volumes.")


class Server:
    """Изолирует команды одним Compose-проектом и одним файлом настроек."""

    def __init__(self, root=ROOT, project="sklad-komforta-server", env=None):
        if not re.fullmatch(r"sklad-(?:server|restore)[a-z0-9-]*", project) and project != "sklad-komforta-server":
            raise ValueError("Имя проекта должно начинаться с sklad-server или sklad-restore.")
        self.root = Path(root).resolve()
        self.project = project
        self.env = Path(env).resolve() if env else self.root / ".env.server"
        self.secret_dir = self.env.parent / (self.env.name + ".secrets")
        self.token = self.secret_dir / "tunnel-token"

    def compose(self, *args, **kwargs):
        # Переменные интерактивной оболочки не должны подменять production-секреты.
        environment = {k: v for k, v in os.environ.items()
                       if k not in KEYS and not k.startswith("COMPOSE_")}
        environment["TUNNEL_TOKEN_FILE"] = str(self.token)
        return subprocess.run(
            ["docker", "compose", "--project-name", self.project,
             "--env-file", str(self.env), "-f", str(self.root / "compose.server.yaml"),
             *args], cwd=self.root, env=environment, check=True, **kwargs,
        )

    def init(self, app, files):
        domain(app)
        domain(files)
        if app == files:
            raise ValueError("Домены должны различаться.")
        values = {"APP_DOMAIN": app, "FILES_DOMAIN": files}
        values.update({key: secrets.token_hex(32) for key in SECRET_NAMES})
        values["TOTP_ENCRYPTION_KEY"] = base64.b64encode(secrets.token_bytes(32)).decode()
        private_write(self.env, "".join(f"{k}={v}\n" for k, v in values.items()).encode())
        self.secret_dir.mkdir(mode=0o700, exist_ok=True)
        if not self.token.exists():
            private_write(self.token, b"")
        print("Создан серверный .env. Существующие базы и локальный compose не изменены.")

    def check(self):
        values = read_env(self.env)
        if os.name == "posix" and self.env.stat().st_mode & 0o077:
            raise ValueError("Закройте права на серверный .env: chmod 600.")
        self.compose("config", "--quiet")
        return values

    def set_tunnel(self):
        token = getpass.getpass("Токен Cloudflare Tunnel (ввод скрыт): ").strip()
        if not re.fullmatch(r"[A-Za-z0-9_+/=-]{40,}", token):
            raise ValueError("Некорректный формат токена.")
        self.secret_dir.mkdir(mode=0o700, exist_ok=True)
        temporary = self.secret_dir / ("token-" + secrets.token_hex(8))
        private_write(temporary, token.encode())
        os.replace(temporary, self.token)
        print("Токен сохранён. Tunnel ещё не запущен.")

    def bootstrap(self):
        values = read_env(self.env)
        login = input("Логин первого директора: ").strip()
        name = input("Имя директора: ").strip()
        limit = int(input("Лимит сотрудников [5]: ").strip() or "5")
        print("Пароль: от 12 символов, заглавная и строчная буквы, цифра и спецсимвол.")
        password = getpass.getpass("Временный пароль (ввод скрыт): ")
        if password != getpass.getpass("Повторите пароль: "):
            raise ValueError("Пароли не совпадают.")
        if not login or not name or limit < 1 or len(password) < 12:
            raise ValueError("Заполните имя и логин, лимит > 0, пароль не короче 12 символов.")
        payload = json.dumps(dict(login=login, displayName=name,
                                  temporaryPassword=password, employeeLimit=limit))
        # Секреты передаются в stdin curl, не в argv / истории shell / логах Compose.
        config = '\n'.join([
            'url = "http://api:8080/api/v1/auth/bootstrap/director"',
            'header = "Content-Type: application/json"',
            'header = "X-Bootstrap-Token: ' + values["BOOTSTRAP_TOKEN"] + '"',
            "data = " + json.dumps(payload),
        ]) + '\n'
        result = self.compose("--profile", "tools", "run", "--rm", "-T", "--no-deps",
                              "admin", "--config", "-", input=config.encode(),
                              stdout=subprocess.PIPE)
        response = json.loads(result.stdout)
        if not response.get("data", {}).get("userId"):
            raise ValueError("API не подтвердил создание директора.")
        print("Директор создан. При входе смените пароль, подключите TOTP и создайте организацию.")

    def running(self):
        result = self.compose("--profile", "public", "ps", "--services", "--status", "running",
                              stdout=subprocess.PIPE, text=True)
        return set(result.stdout.splitlines()) & set(SERVICES)

    def container_ids(self, services):
        ids = self.compose("--profile", "public", "ps", "--all", "--quiet", *services,
                           stdout=subprocess.PIPE, text=True).stdout.splitlines()
        if len(ids) != len(services):
            raise ValueError("Не найдены контейнеры для возобновления работы.")
        return ids

    def start_existing(self, services):
        # Compose start может также запускать зависимости, выключенные до backup.
        subprocess.run(["docker", "start", *self.container_ids(services)],
                       check=True, stdout=subprocess.DEVNULL)

    def wait_ready(self, services, timeout=180):
        ids = self.container_ids(services)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = subprocess.run(["docker", "inspect", "--format", "{{json .State}}", *ids],
                                    check=True, capture_output=True, text=True)
            states = [json.loads(line) for line in result.stdout.splitlines()]
            if all(s["Status"] == "running" and s.get("Health", {}).get("Status", "healthy") == "healthy"
                   for s in states):
                return
            time.sleep(2)
        raise ValueError("Сервисы не восстановили готовность: " + ", ".join(services))

    @contextmanager
    def paused_writes(self):
        running = self.running()
        if "postgres" not in running:
            raise ValueError("PostgreSQL должен работать для создания дампа.")
        stopped = [s for s in reversed(SERVICES) if s in running and s != "postgres"]
        try:
            if stopped:
                self.compose("--profile", "public", "stop", *stopped)
            yield
        finally:
            # Запускаются только сохранённые контейнеры, без обхода depends_on.
            failures = []
            for group in (("minio", "redis"), ("api", "worker"), ("web",), ("cloudflared",)):
                selected = [s for s in group if s in stopped]
                if selected:
                    try:
                        self.start_existing(selected)
                        self.wait_ready(selected)
                    except (OSError, ValueError, subprocess.CalledProcessError):
                        failures.extend(selected)
            if failures:
                raise ValueError("Не удалось возобновить сервисы: " + ", ".join(failures))

    def backup(self, destination, key):
        check_key(key)
        destination = Path(destination).resolve()
        if destination.exists():
            raise ValueError("Архив уже существует; перезапись запрещена.")
        destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="sklad-backup-", dir=destination.parent) as directory:
            folder = Path(directory)
            with self.paused_writes():
                with (folder / "database.dump").open("wb") as stream:
                    self.compose("exec", "-T", "postgres", "pg_dump", "-U", "sklad",
                                 "-d", "sklad_komforta", "-Fc", stdout=stream)
                with (folder / "volumes.tar.gz").open("wb") as stream:
                    self.compose("--profile", "tools", "run", "--rm", "-T", "--no-deps",
                                 "volume-tools", "-c", "tar -C / -czf - minio redis", stdout=stream)
                shutil.copyfile(self.env, folder / "server.env")
                shutil.copyfile(self.token, folder / "tunnel-token")
            revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=self.root,
                                      capture_output=True, text=True, check=True).stdout.strip()
            manifest = dict(version=1, created=datetime.now(timezone.utc).isoformat(),
                            revision=revision, sha256={name: digest(folder / name) for name in PAYLOADS})
            (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            with tarfile.open(folder / "backup.tar", "w") as archive:
                for name in sorted(PAYLOADS | {"manifest.json"}):
                    archive.add(folder / name, arcname=name)
            encrypted = folder / "backup.gpg"
            gpg(key, "--output", str(encrypted), "--symmetric", "--cipher-algo", "AES256",
                str(folder / "backup.tar"))
            # Эксклюзивное создание не позволит затереть другую копию даже при гонке.
            with encrypted.open("rb") as source:
                fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                try:
                    with os.fdopen(fd, "wb") as target:
                        shutil.copyfileobj(source, target)
                except BaseException:
                    destination.unlink(missing_ok=True)
                    raise
        print("Зашифрованная копия создана. Перенесите её за пределы ПК; ключ храните отдельно.")

    def assert_fresh(self):
        if self.env.exists() or self.secret_dir.exists():
            raise ValueError("Восстановление требует отсутствующих .env и каталога секретов.")
        for resource in ("container", "volume", "network"):
            result = subprocess.run(
                ["docker", resource, "ls", "--quiet", "--filter",
                 "label=com.docker.compose.project=" + self.project],
                check=True, capture_output=True, text=True)
            if result.stdout.strip():
                raise ValueError("Проект уже содержит Docker-ресурсы. Выберите новый проект/ВМ.")

    def restore(self, source, key):
        check_key(key)
        self.assert_fresh()
        with tempfile.TemporaryDirectory(prefix="sklad-restore-") as directory:
            folder = Path(directory)
            gpg(key, "--output", str(folder / "backup.tar"), "--decrypt", str(Path(source).resolve()))
            with tarfile.open(folder / "backup.tar", "r:") as archive:
                members = archive.getmembers()
                if (len(members) != 5 or {m.name for m in members} != PAYLOADS | {"manifest.json"}
                        or not all(m.isfile() for m in members)):
                    raise ValueError("Некорректный состав резервной копии.")
                for member in members:
                    with archive.extractfile(member) as stream:
                        with (folder / member.name).open("xb") as target:
                            shutil.copyfileobj(stream, target)
            manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
            if manifest.get("version") != 1 or set(manifest.get("sha256", {})) != PAYLOADS:
                raise ValueError("Неизвестный формат резервной копии.")
            for name in PAYLOADS:
                if digest(folder / name) != manifest["sha256"][name]:
                    raise ValueError("Нарушена контрольная сумма: " + name)
            read_env(folder / "server.env")
            validate_volume_archive(folder / "volumes.tar.gz")
            revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=self.root,
                                      check=True, capture_output=True, text=True).stdout.strip()
            if revision != manifest["revision"]:
                raise ValueError("Сначала переключите код на коммит копии: " + manifest["revision"])
            self.assert_fresh()
            private_write(self.env, (folder / "server.env").read_bytes())
            self.secret_dir.mkdir(mode=0o700)
            private_write(self.token, (folder / "tunnel-token").read_bytes())
            self.compose("create", "postgres", "minio", "redis")
            with (folder / "volumes.tar.gz").open("rb") as stream:
                self.compose("--profile", "tools", "run", "--rm", "-T", "--no-deps",
                             "volume-tools", "-c", "tar -C / -xzf -", stdin=stream)
            self.compose("up", "-d", "--wait", "postgres")
            with (folder / "database.dump").open("rb") as stream:
                self.compose("exec", "-T", "postgres", "pg_restore", "-U", "sklad",
                             "-d", "sklad_komforta", "--clean", "--if-exists", "--no-owner",
                             "--no-privileges", "--exit-on-error", stdin=stream)
        print("Данные восстановлены. API и Tunnel не запущены. Далее: config, up и проверка.")


def check_key(path):
    path = Path(path)
    if not shutil.which("gpg"):
        raise ValueError("Установите GnuPG: sudo apt install gnupg.")
    if path.is_symlink() or not path.is_file() or path.stat().st_size < 64:
        raise ValueError("Нужен отдельный ключ, созданный командой backup-key.")
    if os.name == "posix" and path.stat().st_mode & 0o077:
        raise ValueError("Ключ резервирования должен иметь права 0600.")


def gpg(key, *args):
    subprocess.run(["gpg", "--batch", "--no-symkey-cache", "--pinentry-mode", "loopback", "--passphrase-file",
                    str(Path(key).resolve()), *args], check=True)


@contextmanager
def operation_lock(path):
    """Не допускает параллельных запусков администратора в одной рабочей копии."""
    import fcntl
    fd = os.open(path, os.O_WRONLY | os.O_CREAT, 0o600)
    with os.fdopen(fd, "w") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("Другая серверная операция ещё выполняется.") from error
        yield


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default="sklad-komforta-server")
    parser.add_argument("--env", type=Path)
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="Создать секреты, не запуская сервисы")
    init.add_argument("--app-domain", required=True)
    init.add_argument("--files-domain", required=True)
    for name in ("config", "up", "status", "set-tunnel", "publish", "unpublish", "bootstrap"):
        commands.add_parser(name)
    key = commands.add_parser("backup-key")
    key.add_argument("path", type=Path)
    for name in ("backup", "restore"):
        command = commands.add_parser(name)
        command.add_argument("archive", type=Path)
        command.add_argument("--key", type=Path, required=True)
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("Команды администратора выполняются в Ubuntu-ВМ, не на Windows.")
    server = Server(project=args.project, env=args.env)
    with operation_lock(ROOT / ".server-operation.lock"):
        if args.command == "init":
            server.init(args.app_domain, args.files_domain)
        elif args.command == "backup-key":
            private_write(args.path, (secrets.token_hex(48) + "\n").encode())
            print("Ключ создан. Сохраните отдельную копию вне этой ВМ и вне каталога проекта.")
        elif args.command == "restore":
            server.restore(args.archive, args.key)
        else:
            server.check()
            if args.command == "up":
                server.compose("up", "-d", "--build", "--wait", "--wait-timeout", "300")
            elif args.command == "status":
                server.compose("--profile", "public", "ps", "--all")
            elif args.command == "set-tunnel":
                server.set_tunnel()
            elif args.command == "publish":
                if not server.token.read_text().strip():
                    raise ValueError("Сначала выполните set-tunnel.")
                if input("Ввести домен приложения для публикации: ").strip() != read_env(server.env)["APP_DOMAIN"]:
                    raise ValueError("Публикация не подтверждена.")
                server.compose("--profile", "public", "up", "-d", "cloudflared")
            elif args.command == "unpublish":
                server.compose("--profile", "public", "stop", "cloudflared")
            elif args.command == "bootstrap":
                server.bootstrap()
            elif args.command == "backup":
                server.backup(args.archive, args.key)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print("Ошибка: " + str(error), file=sys.stderr)
        sys.exit(1)
