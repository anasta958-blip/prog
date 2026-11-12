"""Smoke-test employee document creation and full save before mixed load."""

import json

import httpx

from create_load_users import BASE, STATE, regular_login, request
from seed_mixed_documents import order_payload, quote_payload

state = json.loads(STATE.read_text(encoding="utf-8"))
director = state["directors"][0]
employee = director["employees"][0]
with httpx.Client(base_url=BASE, timeout=60) as client:
    token = regular_login(client, employee)
    company = request(client, "GET", "/api/v1/company/legal-entities", bearer=token)[0]
    boards = request(client, "GET", "/api/v1/kanbans/", bearer=token)
    ids = {item["code"]: item["id"] for item in boards}
    for kind, code in (("quote", "load_quote"), ("order", "order")):
        board_id = ids[code]
        board = request(client, "GET", f"/api/v1/kanbans/{board_id}", bearer=token)
        column = next(item for item in board["columns"] if kind in item["creationActions"])
        category = board["categories"][0]["categoryId"]
        item_id = director["loadCatalogItems"][0]
        if kind == "quote":
            payload = quote_payload(kind, director["mixedClientId"], company["id"],
                                    category, item_id, 1001)
            route = "quotes"
        else:
            payload = order_payload(director["mixedClientId"], company["id"],
                                    category, item_id, 1001)
            route = "orders"
        created = request(client, "POST", f"/api/v1/kanbans/{board_id}/{route}",
                          bearer=token, body={"columnId": column["id"], kind: payload})
        card_id = created["cardId"]
        path = f"/api/v1/kanbans/{board_id}/cards/{card_id}/{kind}/"
        opened = request(client, "GET", path, bearer=token)
        saved = request(client, "PUT", path, bearer=token, body=opened)
        print(kind, "create/open/save OK", card_id, saved["title"])
