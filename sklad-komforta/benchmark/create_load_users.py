"""Create isolated test directors and employees for the live load test.

Credentials and TOTP seeds stay in an ignored local file. API/bootstrap tokens
are never printed. Re-running resumes from the last persisted account.
"""

import argparse
import base64
import hashlib
import hmac
import json
import secrets
import struct
import subprocess
import time
from pathlib import Path

import httpx

BASE = "http://127.0.0.1:58080"
STATE = Path(".codex-load-test-credentials.json")


def save(state):
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def password():
    return "Ld!" + secrets.token_urlsafe(18) + "9aA"


def totp(secret):
    key = base64.b32decode(secret + "=" * ((8 - len(secret) % 8) % 8))
    counter = struct.pack(">Q", int(time.time() // 30))
    digest = hmac.new(key, counter, hashlib.sha1).digest()
    offset = digest[-1] & 15
    return f"{(struct.unpack('>I', digest[offset:offset + 4])[0] & 0x7fffffff) % 1000000:06d}"


def request(client, method, path, *, bearer=None, bootstrap=None, body=None):
    headers = {}
    if bearer:
        headers["Authorization"] = "Bearer " + bearer
    if bootstrap:
        headers["X-Bootstrap-Token"] = bootstrap
    response = client.request(method, path, headers=headers, json=body)
    try:
        data = response.json()
    except ValueError as error:
        raise RuntimeError(f"{path}: HTTP {response.status_code}, content-type={response.headers.get('content-type')}") from error
    if response.status_code >= 400 or not data.get("ok", True):
        error = data.get("error") or {}
        code = error.get("code") if isinstance(error, dict) else str(error)
        raise RuntimeError(f"{path}: HTTP {response.status_code}, {code}")
    return data.get("data", data)


def bootstrap_director(body):
    process = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "codex-vm", "python3 /tmp/codex-remote-bootstrap.py"],
        input=json.dumps(body), capture_output=True, text=True, check=True,
    )
    result = json.loads(process.stdout)
    if result["status"] != 200 or not result.get("ok", False):
        raise RuntimeError(f"director bootstrap: HTTP {result['status']}, {result.get('code')}")


def finish_first_login(client, account):
    login = request(client, "POST", "/api/v1/auth/login", body={
        "login": account["login"], "password": account["temporaryPassword"],
        "deviceType": 1, "deviceName": "Codex load test"})
    challenge = login["challengeToken"]
    if login["step"] == 1:
        changed = request(client, "POST", "/api/v1/auth/initial-password", body={
            "challengeToken": challenge, "newPassword": account["password"]})
        challenge = changed["challengeToken"]
    setup = request(client, "POST", "/api/v1/auth/totp/setup", body={
        "challengeToken": challenge})
    account["totpSecret"] = setup["secret"]
    confirmed = request(client, "POST", "/api/v1/auth/totp/confirm", body={
        "challengeToken": challenge, "code": totp(account["totpSecret"])})
    account.pop("temporaryPassword", None)
    return confirmed["tokens"]["accessToken"]


def create_director(client, state, index):
    suffix = state["suffix"]
    account = {"login": f"load{suffix}d{index:02d}",
               "password": password(), "temporaryPassword": password(),
               "employees": [], "phase": "new"}
    bootstrap_director({"login": account["login"], "displayName": f"Нагрузка директор {index}",
                        "temporaryPassword": account["temporaryPassword"], "employeeLimit": 10})
    state["directors"].append(account)
    account["phase"] = "bootstrapped"
    save(state)
    return account


def ensure_director_ready(client, state, account, index):
    if account["phase"] == "bootstrapped":
        token = finish_first_login(client, account)
        account["phase"] = "logged_in"
        save(state)
    else:
        token = regular_login(client, account)
    if account["phase"] == "logged_in":
        organization = request(client, "POST", "/api/v1/identity/organization",
                               bearer=token, body={"name": f"Нагрузочный тест {state['suffix']} {index}"})
        token = organization["accessToken"]
        account["organizationId"] = organization["organizationId"]
        account["phase"] = "organization"
        save(state)
    if account["phase"] == "organization":
        request(client, "POST", "/api/v1/onboarding/activate", bearer=token)
        account["phase"] = "ready"
        save(state)
    return token


def regular_login(client, account):
    started = request(client, "POST", "/api/v1/auth/login", body={
        "login": account["login"], "password": account["password"],
        "deviceType": 1, "deviceName": "Codex load test"})
    verified = request(client, "POST", "/api/v1/auth/totp/verify", body={
        "challengeToken": started["challengeToken"], "code": totp(account["totpSecret"])})
    return verified["tokens"]["accessToken"]


def ensure_employees(client, state, account, token, target):
    roles = request(client, "GET", "/api/v1/settings/access/roles", bearer=token)
    role = next((role for role in roles if role["name"].casefold() in ("менеджер", "manager")), None)
    if role is None:
        role = next((role for role in roles if role["name"] != "Директор"), None)
    if role is None:
        permissions = request(client, "GET", "/api/v1/settings/access/permissions", bearer=token)
        role = request(client, "POST", "/api/v1/settings/access/roles", bearer=token, body={
            "name": "Нагрузочный тест", "permissionCodes": [item["code"] for item in permissions],
            "subordinateRoleIds": [], "cardVisibilityMode": "all",
            "cardVisibilityMembershipIds": []})
    for employee in account["employees"]:
        if employee["phase"] == "created":
            finish_first_login(client, employee)
            employee["phase"] = "ready"
            save(state)
    while len(account["employees"]) < target:
        number = len(account["employees"]) + 1
        employee = {"login": f"{account['login']}e{number:02d}",
                    "password": password(), "temporaryPassword": password(), "phase": "new"}
        request(client, "POST", "/api/v1/company/employees", bearer=token, body={
            "login": employee["login"], "displayName": f"Нагрузка сотрудник {number}",
            "temporaryPassword": employee["temporaryPassword"],
            "roleId": role["id"], "supervisorMembershipId": None,
            "email": None, "phone": None, "telegram": None})
        employee["phase"] = "created"
        account["employees"].append(employee)
        save(state)
        finish_first_login(client, employee)
        employee["phase"] = "ready"
        save(state)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directors", type=int, default=10)
    parser.add_argument("--employees", type=int, default=10)
    args = parser.parse_args()
    if args.directors < 1 or args.directors > 10 or args.employees < 0 or args.employees > 10:
        raise ValueError("Maximum: 10 directors, 10 employees each")
    state = json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else {
        "suffix": time.strftime("%y%m%d%H%M"), "directors": []}
    with httpx.Client(base_url=BASE, timeout=30) as client:
        for index in range(1, args.directors + 1):
            account = state["directors"][index - 1] if len(state["directors"]) >= index else \
                create_director(client, state, index)
            token = ensure_director_ready(client, state, account, index)
            ensure_employees(client, state, account, token, args.employees)
            print(f"director={index} employees={len(account['employees'])} ready", flush=True)
    print(f"accounts={sum(1 + len(x['employees']) for x in state['directors'])}")


if __name__ == "__main__":
    main()
