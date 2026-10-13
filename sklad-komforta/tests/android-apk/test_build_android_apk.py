"""Проверки безопасной конфигурации Android release и сценария упаковки."""

from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import build_android_apk as builder


class AndroidApkTests(unittest.TestCase):
    def test_production_arguments(self):
        args = builder.build_arguments("https://app.example.com/")
        self.assertEqual(args[:3], ["build", "apk", "--release"])
        self.assertIn("--dart-define=API_BASE_URL=https://app.example.com/api/v1", args)
        self.assertIn("--dart-define=PUBLIC_APP_BASE_URL=https://app.example.com", args)
        self.assertIn("--dart-define=APP_ENVIRONMENT=production", args)

    def test_reject_non_https_and_credentials(self):
        for url in ("http://app.example.com", "https://user:pass@app.example.com", "https://app.example.com/api"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                builder.build_arguments(url)

    def test_repository_cannot_hold_signing_key(self):
        for path in (ROOT, ROOT / "build/keys", ROOT / "../keys"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                builder.signing_directory(path)

    def test_existing_key_directory_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(FileExistsError):
                builder.init_signing(Path(folder), Path("missing-java"))

    def test_certificate_fingerprint(self):
        fingerprint = "AB" * 32
        self.assertEqual(builder.certificate_fingerprint(
            f"Signer #1 certificate SHA-256 digest: {fingerprint}\n"), fingerprint.lower())

    def test_reject_missing_or_multiple_signers(self):
        line = "Signer #1 certificate SHA-256 digest: " + "ab" * 32
        for output in ("", "SHA-256: bad", line + "\n" + line):
            with self.subTest(output=output), self.assertRaises(ValueError):
                builder.certificate_fingerprint(output)

    def test_windows_sdk_path_properties(self):
        with tempfile.TemporaryDirectory() as folder:
            flutter = Path(folder)
            (flutter / "android").mkdir()
            (flutter / "android/local.properties").write_text("sdk.dir=E:\\\\Android\\\\Sdk\n", encoding="utf-8")
            with patch.object(builder, "FLUTTER", flutter), patch.dict(builder.os.environ, {}, clear=True):
                self.assertEqual(builder.sdk_directory(None), Path("E:\\Android\\Sdk").resolve())

    def test_release_manifest_has_network_and_disables_backup(self):
        manifest = ET.parse(ROOT / "src/flutter/android/app/src/main/AndroidManifest.xml").getroot()
        android = "{http://schemas.android.com/apk/res/android}"
        self.assertTrue(any(p.get(android + "name") == "android.permission.INTERNET"
                            for p in manifest.findall("uses-permission")))
        application = manifest.find("application")
        self.assertEqual(application.get(android + "allowBackup"), "false")
        self.assertNotEqual(application.get(android + "usesCleartextTraffic"), "true")
        self.assertEqual(application.get(android + "label"), "@string/app_name")

    def test_release_does_not_fall_back_to_debug_key(self):
        gradle = (ROOT / "src/flutter/android/app/build.gradle.kts").read_text(encoding="utf-8")
        self.assertNotIn('signingConfigs.getByName("debug")', gradle)
        self.assertIn('signingConfigs.findByName("release")', gradle)
        self.assertIn('throw GradleException', gradle)
        self.assertIn('SKLAD_ANDROID_SIGNING_DIR', gradle)


if __name__ == "__main__":
    unittest.main()
