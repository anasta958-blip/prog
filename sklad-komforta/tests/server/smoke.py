"""Создаёт два одноразовых проекта и проверяет backup/restore и S3 через Nginx.

Запускать только на тестовом Docker daemon. По окончании удаляет ТОЛЬКО
собственные проекты sklad-server-smoke-<nonce> / sklad-restore-smoke-<nonce>.
Секреты и ключ находятся в приватном TemporaryDirectory, не в репозитории.
"""

from datetime import datetime, timezone
import base64
import hashlib
import hmac
import json
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch
from urllib.parse import urlencode, quote

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from server import Server, private_write, read_env  # noqa: E402


def signed_url(secret, method, key):
    """Подписывает тестовый объект AWS SigV4 с публичным Host файлов."""
    now = datetime.now(timezone.utc)
    timestamp, day = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y%m%d")
    scope = day + "/us-east-1/s3/aws4_request"
    path = "/sklad-komforta/" + key
    params = {
        "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
        "X-Amz-Credential": "sklad-app/" + scope,
        "X-Amz-Date": timestamp, "X-Amz-Expires": "300",
        "X-Amz-SignedHeaders": "host",
    }
    query = urlencode(sorted(params.items()), quote_via=quote)
    canonical = "\n".join((method, path, query, "host:files.example.com\n", "host", "UNSIGNED-PAYLOAD"))
    to_sign = "\n".join(("AWS4-HMAC-SHA256", timestamp, scope,
                           hashlib.sha256(canonical.encode()).hexdigest()))
    signing = ("AWS4" + secret).encode()
    for value in (day, "us-east-1", "s3", "aws4_request"):
        signing = hmac.new(signing, value.encode(), hashlib.sha256).digest()
    signature = hmac.new(signing, to_sign.encode(), hashlib.sha256).hexdigest()
    return "http://web" + path + "?" + query + "&X-Amz-Signature=" + signature


def curl(app, url, host="app.example.com", extra=()):
    result = app.compose("--profile", "tools", "run", "--rm", "-T", "--no-deps",
                         "admin", "--config", "-", input=(
                             "url = " + json.dumps(url) + "\nheader = " + json.dumps("Host: " + host)
                             + "\n" + "\n".join(extra) + "\n").encode(), stdout=subprocess.PIPE)
    return result.stdout


def scalar(app, sql):
    return app.compose("exec", "-T", "postgres", "psql", "-U", "sklad", "-d", "sklad_komforta",
                       "-tAc", sql, stdout=subprocess.PIPE, text=True).stdout.strip()


def post(app, path, payload, token=None, include=False):
    config = ['header = "Content-Type: application/json"', "data = " + json.dumps(json.dumps(payload))]
    if token:
        config.append("header = " + json.dumps("Authorization: Bearer " + token))
    if include:
        config.append("include")
    response = curl(app, "http://web/api/v1/" + path, extra=config)
    if include:
        headers, response = response.split(b"\r\n\r\n", 1)
        cookies = [line.lower() for line in headers.splitlines() if line.lower().startswith(b"set-cookie:")]
        assert cookies and all(b"secure" in line and b"httponly" in line for line in cookies)
    return json.loads(response)["data"]


def totp(secret):
    counter = int(time.time()) // 30
    hashed = hmac.new(base64.b32decode(secret), counter.to_bytes(8, "big"), hashlib.sha1).digest()
    offset = hashed[-1] & 15
    code = (int.from_bytes(hashed[offset:offset + 4], "big") & 0x7fffffff) % 1000000
    return f"{code:06d}"


def main():
    if "--allow-disposable-projects" not in sys.argv:
        raise SystemExit("Нужен явный флаг --allow-disposable-projects.")
    nonce = secrets.token_hex(4)
    with tempfile.TemporaryDirectory(prefix="sklad-smoke-") as folder:
        directory = Path(folder)
        original = Server(project="sklad-server-smoke-" + nonce, env=directory / "source.env")
        restored = Server(project="sklad-restore-smoke-" + nonce, env=directory / "restored.env")
        try:
            original.init("app.example.com", "files.example.com")
            original.check()
            config = json.loads(original.compose("--profile", "public", "config", "--format", "json",
                                                 stdout=subprocess.PIPE).stdout)
            assert all(not service.get("ports") for service in config["services"].values())
            original.compose("up", "-d", "--build", "--wait", "--wait-timeout", "300")
            assert "cloudflared" not in original.running()
            assert scalar(original, "SELECT count(*) FROM public.users") == "0"
            assert scalar(original, "SELECT rolsuper FROM pg_roles WHERE rolname='sklad'") == "f"
            assert b"html" in curl(original, "http://web/").lower()
            assert curl(original, "http://web/health/ready")
            status = ['no-fail-with-body', 'output = "/dev/null"', 'write-out = "%{http_code}"']
            assert curl(original, "http://web/api/v1/auth/bootstrap/director", extra=status) == b"404"
            assert curl(original, "http://web/api/v1/Auth/Bootstrap/director", extra=status) == b"404"
            assert curl(original, "http://web/", "files.example.com", status) == b"404"
            assert curl(original, "http://web/sklad-komforta/test.txt", "files.example.com", status) == b"403"
            password = "Aa1!" + secrets.token_hex(20)
            with patch("builtins.input", side_effect=["smokedirector", "Проверка директора", "5"]), \
                    patch("getpass.getpass", return_value=password):
                original.bootstrap()
            assert scalar(original, "SELECT count(*) FROM public.users") == "1"
            login = post(original, "auth/login", dict(login="smokedirector", password=password, deviceType=1))
            password = "Bb2!" + secrets.token_hex(20)
            challenge = post(original, "auth/initial-password", dict(
                challengeToken=login["challengeToken"], newPassword=password))["challengeToken"]
            otp_secret = post(original, "auth/totp/setup", dict(challengeToken=challenge))["secret"]
            auth = post(original, "auth/totp/confirm", dict(challengeToken=challenge, code=totp(otp_secret)), include=True)
            post(original, "identity/organization", dict(name="Проверка чистой организации"), auth["tokens"]["accessToken"])
            assert scalar(original, "SELECT count(*) FROM public.organizations") == "1"
            secret = read_env(original.env)["S3_SECRET_KEY"]
            curl(original, signed_url(secret, "PUT", "test.txt"), "files.example.com",
                 ['request = "PUT"', 'data = "backup-test-object"'])
            assert curl(original, signed_url(secret, "GET", "test.txt"), "files.example.com") == b"backup-test-object"
            cors = curl(original, signed_url(secret, "PUT", "test.txt"), "files.example.com", [
                'request = "OPTIONS"', 'header = "Origin: https://app.example.com"',
                'header = "Access-Control-Request-Method: PUT"', 'include',
            ])
            assert b"access-control-allow-origin: https://app.example.com" in cors.lower()
            key = directory / "backup.key"
            private_write(key, secrets.token_hex(48).encode())
            original.backup(directory / "backup.tar.gpg", key)
            assert "web" in original.running()
            assert "cloudflared" not in original.running()
            restored.restore(directory / "backup.tar.gpg", key)
            assert restored.running() == {"postgres"}
            assert scalar(restored, "SELECT count(*) FROM public.users") == "1"
            assert scalar(restored, "SELECT count(*) FROM public.organizations") == "1"
            # Тот же web/API образ: восстановление проверяется на той же версии кода.
            for service in ("api", "worker", "web"):
                subprocess.run(["docker", "tag", original.project + "-" + service,
                                restored.project + "-" + service], check=True)
            restored.compose("up", "-d", "--wait", "--wait-timeout", "300")
            assert curl(restored, signed_url(secret, "GET", "test.txt"), "files.example.com") == b"backup-test-object"
            assert read_env(restored.env) == read_env(original.env)
            login = post(restored, "auth/login", dict(login="smokedirector", password=password, deviceType=1))
            auth = post(restored, "auth/totp/verify", dict(
                challengeToken=login["challengeToken"], code=totp(otp_secret)), include=True)
            assert auth["tokens"]["organizationId"]
            print("SMOKE OK: чистая БД, bootstrap, TOTP/Secure-cookie, организация, S3 PUT/GET/CORS, backup/restore и повторный вход.")
        finally:
            for app in (restored, original):
                if app.env.exists():
                    # Имена с случайным суффиксом создаются только этим тестом.
                    app.compose("--profile", "public", "--profile", "tools", "down", "--volumes", "--remove-orphans")


if __name__ == "__main__":
    main()
