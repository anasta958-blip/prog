"""Print only the structure of a test organization's configuration."""

import json

import httpx

from create_load_users import BASE, STATE, regular_login, request

state = json.loads(STATE.read_text(encoding="utf-8"))
with httpx.Client(base_url=BASE, timeout=30) as client:
    token = regular_login(client, state["directors"][0])
    config = request(client, "GET", "/api/v1/onboarding/", bearer=token)
    print("configuration keys", list(config))
    draft = config.get("draft", config)
    print("draft keys", list(draft))
    for workflow in draft.get("workflows", []):
        print("workflow", {key: workflow.get(key) for key in (
            "code", "name", "specialization", "clientId", "creationActions")},
            "columns", [(column.get("clientId"), column.get("name"), column.get("creationActions"))
                       for column in workflow.get("columns", [])])
    print("rules", len(draft.get("rules") or []), "fields", len(draft.get("fields") or []))
    print("category fields", [(category["clientId"], [field["fieldCode"] for field in category["fields"]])
                              for category in draft["categories"]])
