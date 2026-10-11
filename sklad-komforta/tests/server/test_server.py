"""Регрессии административной утилиты без Docker и без рабочих данных."""

import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "server", Path(__file__).resolve().parents[2] / "scripts/server.py")
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = server.Server(self.root, "sklad-server-check")

    def init(self):
        self.app.init("app.example.com", "files.example.com")

    def test_init_generates_valid_distinct_secrets(self):
        self.init()
        values = server.read_env(self.app.env)
        self.assertEqual(len({values[k] for k in server.SECRET_NAMES}), 7)
        self.assertEqual(self.app.token.read_bytes(), b"")

    def test_init_never_overwrites(self):
        self.init()
        original = self.app.env.read_bytes()
        with self.assertRaises(FileExistsError):
            self.init()
        self.assertEqual(self.app.env.read_bytes(), original)

    def test_domain_rejects_urls_interpolation_and_invalid_dns(self):
        for value in ("https://app.example.com", "a.com:80", "$(cmd).com", "a..com",
                      "-a.com", "a_.com", "a.com\nSECRET=x", "*.example.com"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                server.domain(value)

    def test_same_domains_rejected_before_writing(self):
        with self.assertRaises(ValueError):
            self.app.init("a.example.com", "a.example.com")
        self.assertFalse(self.app.env.exists())

    def test_env_rejects_duplicate_and_unknown_keys(self):
        self.init()
        original = self.app.env.read_bytes()
        for addition in (b"APP_DOMAIN=a.example.com\n", b"COMPOSE_FILE=bad.yaml\n"):
            self.app.env.write_bytes(original + addition)
            with self.assertRaises(ValueError):
                server.read_env(self.app.env)

    def test_env_rejects_secret_substitution(self):
        self.init()
        contents = self.app.env.read_text()
        value = server.read_env(self.app.env)["S3_SECRET_KEY"]
        self.app.env.write_text(contents.replace(value, "${OTHER_SECRET}"))
        with self.assertRaises(ValueError):
            server.read_env(self.app.env)

    def test_compose_does_not_inherit_overrides(self):
        with patch.dict(server.os.environ, {"COMPOSE_PROFILES": "public", "JWT_SIGNING_KEY": "wrong"}), \
                patch.object(server.subprocess, "run") as run:
            self.app.compose("config", "--quiet")
        args, kwargs = run.call_args
        self.assertNotIn("JWT_SIGNING_KEY", kwargs["env"])
        self.assertNotIn("COMPOSE_PROFILES", kwargs["env"])
        self.assertIn("sklad-server-check", args[0])
        self.assertIn(str(self.root / "compose.server.yaml"), args[0])

    def test_development_project_forbidden(self):
        with self.assertRaises(ValueError):
            server.Server(self.root, "sklad-komforta")

    def test_restore_rejects_existing_env(self):
        self.init()
        with self.assertRaises(ValueError):
            self.app.assert_fresh()

    def test_restore_rejects_existing_docker_resources(self):
        with patch.object(server.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "resource\n")), \
                self.assertRaises(ValueError):
            self.app.assert_fresh()

    def test_pause_restores_only_previously_running_services_after_error(self):
        with patch.object(self.app, "running", return_value={"postgres", "api", "web", "minio", "redis"}), \
                patch.object(self.app, "wait_ready"), \
                patch.object(self.app, "compose"), \
                patch.object(self.app, "start_existing") as start:
            with self.assertRaisesRegex(ValueError, "failure"):
                with self.app.paused_writes():
                    raise ValueError("failure")
        calls = [call.args[0] for call in start.call_args_list]
        self.assertNotIn("cloudflared", str(calls))
        self.assertIn(["minio", "redis"], calls)
        self.assertIn(["web"], calls)

    def test_resume_attempts_all_services_even_if_storage_fails(self):
        with patch.object(self.app, "running", return_value={"postgres", "web", "minio"}), \
                patch.object(self.app, "wait_ready", side_effect=[ValueError("unhealthy"), None]), \
                patch.object(self.app, "compose"), \
                patch.object(self.app, "start_existing") as start:
            with self.assertRaisesRegex(ValueError, "minio"):
                with self.app.paused_writes():
                    pass
        self.assertIn(["web"], [c.args[0] for c in start.call_args_list])

    def test_volume_archive_validation(self):
        path = self.root / "volumes.tar.gz"
        for name, kind, allowed in (("minio/bucket/file", tarfile.REGTYPE, True),
                                    ("redis/aof/file", tarfile.REGTYPE, True),
                                    ("minio/../../etc/passwd", tarfile.REGTYPE, False),
                                    ("/minio/file", tarfile.REGTYPE, False),
                                    ("minio/link", tarfile.SYMTYPE, False),
                                    ("redis/device", tarfile.CHRTYPE, False)):
            with tarfile.open(path, "w:gz") as archive:
                member = tarfile.TarInfo(name)
                member.type = kind
                archive.addfile(member, io.BytesIO(b""))
            with self.subTest(name=name):
                if allowed:
                    server.validate_volume_archive(path)
                else:
                    with self.assertRaises(ValueError):
                        server.validate_volume_archive(path)

    def test_bootstrap_secrets_go_to_stdin_only(self):
        self.init()
        with patch("builtins.input", side_effect=["director", "Директор", "5"]), \
                patch.object(server.getpass, "getpass", return_value="SafePassword123!"), \
                patch.object(self.app, "compose", return_value=subprocess.CompletedProcess(
                    [], 0, json.dumps({"data": {"userId": "test"}}).encode())) as compose:
            self.app.bootstrap()
        self.assertNotIn("SafePassword123!", str(compose.call_args.args))
        self.assertIn(b"SafePassword123!", compose.call_args.kwargs["input"])


if __name__ == "__main__":
    unittest.main()
