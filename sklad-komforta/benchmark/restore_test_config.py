"""Restore missing configuration drafts in the 10 isolated load-test tenants.

The onboarding API can synthesize the active draft, while the settings API
requires its persisted copy. This one-time repair only inserts missing rows.
"""

import argparse
import json
import re
import subprocess
import uuid

import httpx

from create_load_users import BASE, STATE, regular_login, request

POSTGRES = "sklad-komforta-server-postgres-1"


def ssh(*args, input_text=None):
    process = subprocess.run(["ssh", "-o", "BatchMode=yes", "codex-vm", *args],
                             input=input_text, text=True, encoding="utf-8",
                             capture_output=True, check=True)
    return process.stdout.strip()


def db_settings():
    values = dict(line.split("=", 1) for line in ssh(f"docker exec {POSTGRES} env").splitlines()
                  if "=" in line)
    return values["POSTGRES_USER"], values["POSTGRES_DB"]


def sql(user, database, statement):
    return ssh(f"docker exec -i {POSTGRES} psql -X -q -t -A -v ON_ERROR_STOP=1 "
               f"-U {user} -d {database}", input_text=statement + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directors", type=int, default=10)
    args = parser.parse_args()
    state = json.loads(STATE.read_text(encoding="utf-8"))
    db_user, database = db_settings()
    with httpx.Client(base_url=BASE, timeout=30) as client:
        for index, director in enumerate(state["directors"][:args.directors], 1):
            token = regular_login(client, director)
            onboarding = request(client, "GET", "/api/v1/onboarding/", bearer=token)
            if not onboarding["isCompleted"]:
                raise RuntimeError(f"director {index}: onboarding incomplete")
            organization = str(uuid.UUID(director["organizationId"]))
            schema = sql(db_user, database,
                         f"SELECT schema_name FROM public.organizations WHERE id='{organization}';")
            if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", schema):
                raise RuntimeError(f"director {index}: invalid tenant schema")
            draft = onboarding["draft"]
            draft["currentStep"] = 10
            payload = json.dumps(draft, ensure_ascii=False, separators=(",", ":")).replace("'", "''")
            command = f"""INSERT INTO {schema}.onboarding_draft
                (singleton, current_step, payload, updated_by, updated_at)
                VALUES (true, 10, '{payload}'::jsonb,
                    (SELECT user_id FROM public.organization_members
                     WHERE organization_id='{organization}' AND is_director LIMIT 1), now())
                ON CONFLICT (singleton) DO NOTHING;"""
            sql(db_user, database, command)
            request(client, "GET", "/api/v1/company/configuration", bearer=token)
            print(f"director={index} configuration ready", flush=True)


if __name__ == "__main__":
    main()
