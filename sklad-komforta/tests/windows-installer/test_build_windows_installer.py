"""Проверки входов сборки и ограничений пользовательского установщика."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("builder", ROOT / "scripts/build_windows_installer.py")
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class InstallerTests(unittest.TestCase):
    def test_origin(self):
        self.assertEqual(builder.public_origin("https://APP.example.com/"), "https://app.example.com")

    def test_reject_unsafe_origins(self):
        for value in ("http://app.example.com", "https://localhost", "https://a.com/api/v1",
                      "https://user:password@a.com", "https://a.com?token=x", "https://a.com:443",
                      "https://a.com&whoami", "https://a.com/%PATH%", 'https://a.com"'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                builder.public_origin(value)

    def test_version(self):
        self.assertEqual(builder.read_version("name: app\nversion: 1.2.3+4\n"), ("1.2.3+4", "1.2.3.4"))

    def test_invalid_version(self):
        for value in ("version: 1.0.0", "version: 1.2.3+65536", "version: 1.0.0-beta+1"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                builder.read_version(value)

    def test_production_arguments(self):
        args = builder.build_arguments("https://app.example.com")
        self.assertIn("--release", args)
        self.assertEqual(args[:3], ["build", "windows", "--release"])
        self.assertIn("--dart-define=API_BASE_URL=https://app.example.com/api/v1", args)
        self.assertIn("--dart-define=PUBLIC_APP_BASE_URL=https://app.example.com", args)
        self.assertIn("--dart-define=APP_ENVIRONMENT=production", args)

    def test_bundle_validation(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder)
            with self.assertRaises(ValueError):
                builder.validate_bundle(bundle)
            for name in ("sklad_komforta_app.exe", "flutter_windows.dll", "data/icudtl.dat",
                         "data/app.so", "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"):
                path = bundle / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            (bundle / "data/flutter_assets").mkdir()
            builder.validate_bundle(bundle)
            (bundle / ".env.server").touch()
            with self.assertRaises(ValueError):
                builder.validate_bundle(bundle)

    def test_installer_is_per_user_and_has_no_destructive_cleanup(self):
        script = (ROOT / "deploy/windows/installer.nsi").read_text(encoding="utf-8")
        self.assertIn("RequestExecutionLevel user", script)
        self.assertIn('InstallDir "$LOCALAPPDATA\\Programs\\SkladKomforta"', script)
        self.assertIn("${IsNativeAMD64}", script)
        self.assertIn('MUI_LANGUAGE "Russian"', script)
        self.assertNotIn("RMDir /r", script)
        self.assertNotIn("HKLM", script)

    def test_file_lists_preserve_unknown_files_and_escape_dollars(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle = root / "bundle"
            (bundle / "data").mkdir(parents=True)
            (bundle / "data/$test.txt").touch()
            builder.write_file_lists(bundle, root)
            install = (root / "install-files.nsh").read_text(encoding="utf-8-sig")
            uninstall = (root / "uninstall-files.nsh").read_text(encoding="utf-8-sig")
            self.assertIn("$$test.txt", install)
            self.assertIn('Delete "$INSTDIR\\data\\$$test.txt"', uninstall)
            self.assertNotIn("/r", uninstall)
            self.assertNotIn("*", uninstall)

    def test_nsis_newline_rejected(self):
        with self.assertRaises(ValueError):
            builder.nsis_escape("file\nExec evil")


if __name__ == "__main__":
    unittest.main()
