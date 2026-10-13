"""Сборка Windows x64: Flutter release, локальный CRT и NSIS без UAC.

Публичный HTTPS-адрес обязателен. Секреты и .env не читаются. Каждый запуск
создаёт отдельную папку в игнорируемом build; существующие выпуски не удаляются.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FLUTTER = ROOT / "src/flutter"


def public_origin(value: str) -> str:
    """Проверяет HTTPS origin без путей, учётных данных и shell-метасимволов."""
    if not re.fullmatch(r"https://(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}/?", value):
        raise ValueError("Укажите HTTPS-адрес домена без пути, порта и параметров.")
    return value.rstrip("/").lower()


def read_version(text: str) -> tuple[str, str]:
    """Возвращает версию pubspec и четырёхкомпонентную версию Windows."""
    match = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", text, re.MULTILINE)
    if not match or any(int(part) > 65535 for part in match.groups()):
        raise ValueError("Нужна версия major.minor.patch+build, компоненты 0..65535.")
    parts = [str(int(part)) for part in match.groups()]
    return ".".join(parts[:3]) + "+" + parts[3], ".".join(parts)


def build_arguments(origin: str) -> list[str]:
    """Фиксирует release-сборку и production URL API и публичных ссылок."""
    origin = public_origin(origin)
    return ["build", "windows", "--release",
            f"--dart-define=API_BASE_URL={origin}/api/v1",
            f"--dart-define=PUBLIC_APP_BASE_URL={origin}",
            "--dart-define=APP_ENVIRONMENT=production"]


def run(args: list[str], cwd: Path = ROOT) -> None:
    """Запускает инструмент с проверкой кода завершения."""
    subprocess.run(args, cwd=cwd, check=True)


def find_crt() -> Path:
    """Находит новейший redistributable x64 CRT установленной Visual Studio."""
    vswhere = Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
    installation = subprocess.check_output(
        [str(vswhere), "-latest", "-products", "*", "-requires",
         "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"],
        text=True).strip()
    if not installation:
        raise ValueError("Visual Studio с инструментами C++ не найдена.")
    base = Path(installation) / "VC/Redist/MSVC"
    versions = sorted((p for p in base.iterdir() if re.fullmatch(r"\d+(\.\d+)+", p.name)),
                      key=lambda p: tuple(map(int, p.name.split("."))), reverse=True)
    for version in versions:
        candidates = list(version.glob("x64/Microsoft.VC*.CRT"))
        if candidates:
            return candidates[0]
    raise ValueError("Не найден redistributable x64 CRT. Укажите --crt-dir.")


def validate_bundle(bundle: Path) -> None:
    """Отклоняет неполный bundle и случайно попавшие конфигурации с секретами."""
    for name in ("sklad_komforta_app.exe", "flutter_windows.dll", "data/icudtl.dat",
                 "data/app.so", "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"):
        if not (bundle / name).is_file():
            raise ValueError(f"В сборке отсутствует {name}")
    if not (bundle / "data/flutter_assets").is_dir():
        raise ValueError("В сборке отсутствуют Flutter assets.")
    for path in bundle.rglob("*"):
        if path.name.startswith(".env") or path.suffix.lower() in {".key", ".pfx", ".pem"}:
            raise ValueError(f"Запрещённый файл в сборке: {path.name}")


def nsis_escape(value: str) -> str:
    """Экранирует строки NSIS, исключая подстановку переменных из путей."""
    if any(c in value for c in '\r\n'):
        raise ValueError("Недопустимый перевод строки в пути.")
    return value.replace('$', '$$').replace('"', '$\\"')


def write_file_lists(bundle: Path, release: Path) -> None:
    """Фиксирует список файлов; удаление не затрагивает посторонние файлы."""
    installs, deletes = [], []
    paths = sorted(p for p in bundle.rglob("*") if p.is_file())
    for path in paths:
        relative = path.relative_to(bundle)
        parent = "" if relative.parent == Path(".") else "\\" + nsis_escape(str(relative.parent).replace("/", "\\"))
        installs.extend([f'SetOutPath "$INSTDIR{parent}"', f'File "{nsis_escape(str(path))}"'])
        deletes.append(f'Delete "$INSTDIR\\{nsis_escape(str(relative).replace(chr(47), chr(92)))}"')
    directories = sorted((p.relative_to(bundle) for p in bundle.rglob("*") if p.is_dir()),
                         key=lambda p: len(p.parts), reverse=True)
    deletes.extend(f'RMDir "$INSTDIR\\{nsis_escape(str(p).replace(chr(47), chr(92)))}"' for p in directories)
    (release / "install-files.nsh").write_text("\n".join(installs), encoding="utf-8-sig")
    (release / "uninstall-files.nsh").write_text("\n".join(deletes), encoding="utf-8-sig")


def main() -> int:
    """CLI: собирает клиент, проверяет bundle, создаёт installer и SHA-256."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-url", required=True)
    parser.add_argument("--flutter", default=shutil.which("flutter") or "flutter.bat")
    parser.add_argument("--makensis", type=Path)
    parser.add_argument("--crt-dir", type=Path)
    parser.add_argument("--prepare-only", action="store_true", help="Собрать bundle без NSIS")
    args = parser.parse_args()
    if os.name != "nt" or platform.machine().lower() not in {"amd64", "x86_64"}:
        raise ValueError("Сборка установщика выполняется на Windows x64.")
    origin = public_origin(args.app_url)
    version, file_version = read_version((FLUTTER / "pubspec.yaml").read_text(encoding="utf-8"))
    compiler = args.makensis
    if not args.prepare_only:
        if compiler is None:
            candidates = [Path(shutil.which("makensis") or "__missing__"),
                          ROOT / "build/tools/nsis-3.12/makensis.exe"]
            for root in (os.environ.get("ProgramFiles(x86)", ""), os.environ.get("ProgramFiles", ""),
                         str(Path(os.environ.get("LOCALAPPDATA", "")) / "Programs")):
                candidates.append(Path(root) / "NSIS/makensis.exe")
            compiler = next((p for p in candidates if p.is_file()), None)
        if compiler is None or not compiler.is_file():
            raise ValueError("Установите NSIS 3 или укажите --makensis. Для bundle: --prepare-only.")
    crt = args.crt_dir or find_crt()
    if not (crt / "vcruntime140.dll").is_file():
        raise ValueError("--crt-dir должен указывать на redistributable x64 CRT.")
    run([args.flutter, *build_arguments(origin)], FLUTTER)
    output = ROOT / "build/windows-installer"
    output.mkdir(parents=True, exist_ok=True)
    release = Path(tempfile.mkdtemp(prefix=f"{file_version}-", dir=output))
    bundle = release / "bundle"
    shutil.copytree(FLUTTER / "build/windows/x64/runner/Release", bundle,
                    ignore=shutil.ignore_patterns("*.pdb", "*.exp", "*.lib"))
    for dll in crt.glob("*.dll"):
        shutil.copy2(dll, bundle / dll.name)
    validate_bundle(bundle)
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
    manifest = {"version": version, "appUrl": origin, "commit": commit, "dirty": dirty,
                "createdUtc": datetime.now(timezone.utc).isoformat(), "crt": str(crt),
                "signed": False}
    if not args.prepare_only:
        write_file_lists(bundle, release)
        run([str(compiler), "/NOCONFIG", "/INPUTCHARSET", "UTF8", f"/DReleaseDir={release}",
             f"/DAppVersion={version}", f"/DFileVersion={file_version}",
             str(ROOT / "deploy/windows/installer.nsi")])
        installer = release / f"SkladKomforta-{file_version}-windows-x64-setup.exe"
        with installer.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        manifest["sha256"] = digest
        installer.with_suffix(".exe.sha256").write_text(f"{digest}  {installer.name}\n", encoding="ascii")
    (release / "release.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Готово: {release}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Ошибка: {error}", file=sys.stderr)
        sys.exit(1)
