"""Подписанный Android APK для прямой установки, без Google Play.

init-signing создаёт отдельный ключ вне репозитория один раз; build использует
его повторно. Пароль не выводится и не передаётся аргументом процесса.
"""

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

from build_windows_installer import public_origin, read_version


ROOT = Path(__file__).resolve().parents[1]
FLUTTER = ROOT / "src/flutter"
PACKAGE = "com.skladkomforta.sklad_komforta_app"


def signing_directory(value: Path) -> Path:
    """Не позволяет хранить ключи в рабочем репозитории или его артефактах."""
    directory = value.expanduser().resolve()
    repository = Path(subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], cwd=ROOT, text=True).strip()).resolve()
    if directory == repository or repository in directory.parents:
        raise ValueError("Ключ подписи должен храниться вне репозитория.")
    return directory


def java_home(value: Path | None) -> Path:
    """Находит JDK: аргумент, JAVA_HOME или встроенный JDK Android Studio."""
    candidates = [value] if value else []
    if os.environ.get("JAVA_HOME"):
        candidates.append(Path(os.environ["JAVA_HOME"]))
    candidates.append(Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Android/Android Studio/jbr")
    for path in candidates:
        if path and (path / "bin/keytool.exe").is_file():
            return path.resolve()
    raise ValueError("Укажите --java-home с JDK Android Studio.")


def init_signing(directory: Path, java: Path) -> None:
    """Создаёт закрытый PKCS12 и пароль; существующую папку не перезаписывает."""
    directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    # ACL применяется до создания секретов; обычным другим пользователям доступ не выдаётся.
    output = subprocess.check_output(["whoami", "/user", "/fo", "csv", "/nh"], text=True)
    sid = next(csv.reader(io.StringIO(output.strip())))[1]
    if not re.fullmatch(r"S-1-[0-9-]+", sid):
        raise ValueError("Не удалось определить Windows SID.")
    subprocess.run(["icacls", str(directory), "/inheritance:r", "/grant:r", f"*{sid}:(OI)(CI)F"],
                   check=True, stdout=subprocess.DEVNULL)
    password_file = directory / "password.txt"
    with password_file.open("x", encoding="ascii") as stream:
        stream.write(secrets.token_urlsafe(48) + "\n")
    subprocess.run([str(java / "bin/keytool.exe"), "-genkeypair", "-noprompt", "-storetype", "PKCS12",
                    "-keystore", str(directory / "release.p12"), "-storepass:file", str(password_file),
                    "-keypass:file", str(password_file), "-alias", "skladkomforta", "-keyalg", "RSA",
                    "-keysize", "3072", "-validity", "10000", "-dname", "CN=Sklad Komforta Android"], check=True)
    print(f"Ключ создан: {directory}. Сохраните всю папку отдельно от ПК. Не создавайте новый ключ для обновлений.")


def build_arguments(origin: str) -> list[str]:
    """Универсальный release APK с production API и публичными ссылками."""
    origin = public_origin(origin)
    return ["build", "apk", "--release",
            f"--dart-define=API_BASE_URL={origin}/api/v1",
            f"--dart-define=PUBLIC_APP_BASE_URL={origin}",
            "--dart-define=APP_ENVIRONMENT=production"]


def sdk_directory(value: Path | None) -> Path:
    """Читает путь SDK из аргумента, окружения или локального файла Flutter."""
    if value:
        return value.resolve()
    for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if os.environ.get(name):
            return Path(os.environ[name]).resolve()
    properties = (FLUTTER / "android/local.properties").read_text(encoding="utf-8")
    match = re.search(r"^sdk\.dir=(.+)$", properties, re.MULTILINE)
    if not match:
        raise ValueError("Укажите --android-sdk.")
    return Path(match[1].strip().replace("\\\\", "\\").replace("\\:", ":")).resolve()


def certificate_fingerprint(text: str) -> str:
    """Извлекает SHA-256 единственного сертификата apksigner."""
    found = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})", text)
    if len(found) != 1:
        raise ValueError("Не найден единственный сертификат подписи APK.")
    return found[0].lower()


def build(args: argparse.Namespace, directory: Path, java: Path) -> Path:
    """Собирает APK, проверяет подпись и манифест, создаёт хеш и паспорт выпуска."""
    origin = public_origin(args.app_url)
    version, _ = read_version((FLUTTER / "pubspec.yaml").read_text(encoding="utf-8"))
    for name in ("release.p12", "password.txt"):
        if not (directory / name).is_file():
            raise ValueError(f"Отсутствует {name}. Для первого выпуска выполните init-signing.")
    sdk = sdk_directory(args.android_sdk)
    versions = sorted((p for p in (sdk / "build-tools").iterdir() if re.fullmatch(r"\d+(\.\d+)+", p.name)),
                      key=lambda p: tuple(map(int, p.name.split("."))), reverse=True)
    tools = next((p for p in versions if (p / "apksigner.bat").is_file() and (p / "aapt.exe").is_file()), None)
    if tools is None:
        raise ValueError("В Android SDK отсутствуют build-tools с apksigner и aapt.")
    env = os.environ.copy()
    env.update(SKLAD_ANDROID_SIGNING_DIR=str(directory), JAVA_HOME=str(java), ANDROID_HOME=str(sdk))
    # Kotlin incremental cache не умеет относительные пути между дисками C: и E:.
    # Выпуск компилируется целиком; обычную debug-разработку это не затрагивает.
    env["ORG_GRADLE_PROJECT_kotlin.incremental"] = "false"
    env["PATH"] = str(java / "bin") + os.pathsep + env.get("PATH", "")
    subprocess.run([args.flutter, *build_arguments(origin)], cwd=FLUTTER, env=env, check=True)
    apk = FLUTTER / "build/app/outputs/flutter-apk/app-release.apk"
    verification = subprocess.check_output([str(tools / "apksigner.bat"), "verify", "--verbose",
                                            "--print-certs", str(apk)], env=env, text=True, encoding="utf-8")
    fingerprint = certificate_fingerprint(verification)
    # Сверяем фактическую подпись с ключом, а не только наличие любой подписи.
    certificate = subprocess.check_output([str(java / "bin/keytool.exe"), "-exportcert",
        "-keystore", str(directory / "release.p12"), "-storepass:file", str(directory / "password.txt"),
        "-alias", "skladkomforta"])
    if hashlib.sha256(certificate).hexdigest() != fingerprint:
        raise ValueError("APK подписан не ожидаемым ключом.")
    badging = subprocess.check_output([str(tools / "aapt.exe"), "dump", "badging", str(apk)], env=env,
                                      text=True, encoding="utf-8")
    if f"package: name='{PACKAGE}'" not in badging or "android.permission.INTERNET" not in badging:
        raise ValueError("Неверный package ID или отсутствует INTERNET в APK.")
    if "application-debuggable" in badging:
        raise ValueError("APK не должен разрешать отладку.")
    output = ROOT / "build/android-apk"
    output.mkdir(parents=True, exist_ok=True)
    release = Path(tempfile.mkdtemp(prefix=f"{version}-", dir=output))
    target = release / f"SkladKomforta-{version}-android.apk"
    shutil.copy2(apk, target)
    with target.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    target.with_suffix(".apk.sha256").write_text(f"{digest}  {target.name}\n", encoding="ascii")
    (release / "apk-verification.txt").write_text(verification + "\n" + badging, encoding="utf-8")
    manifest = {"version": version, "appUrl": origin, "package": PACKAGE, "sha256": digest,
                "certificateSha256": fingerprint, "createdUtc": datetime.now(timezone.utc).isoformat(),
                "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())}
    (release / "release.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return target


def main() -> int:
    """CLI init-signing/build для Windows; не изменяет сервер и не публикует APK."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("init-signing", "build"))
    parser.add_argument("--signing-dir", type=Path, default=Path.home() / ".sklad-komforta/android-signing")
    parser.add_argument("--java-home", type=Path)
    parser.add_argument("--android-sdk", type=Path)
    parser.add_argument("--flutter", default=shutil.which("flutter") or "flutter.bat")
    parser.add_argument("--app-url")
    args = parser.parse_args()
    if os.name != "nt":
        raise ValueError("Этот сценарий сборки предназначен для Windows.")
    directory = signing_directory(args.signing_dir)
    java = java_home(args.java_home)
    if args.action == "init-signing":
        init_signing(directory, java)
    else:
        if not args.app_url:
            raise ValueError("Для build укажите --app-url.")
        print(f"Готово: {build(args, directory, java)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Ошибка: {error}", file=sys.stderr)
        sys.exit(1)
