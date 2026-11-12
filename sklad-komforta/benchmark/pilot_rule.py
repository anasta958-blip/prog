"""Verify rule creation and stale-document recalculation in test org one."""

import argparse
import json

import httpx

from create_load_users import BASE, STATE, regular_login, request


def rule(index):
    return {"clientId": f"load-rule-{index}", "name": f"Нагрузочное правило {index}",
            "categoryClientId": "equipment", "eventType": "row_calculation",
            "isEnabled": True, "eventFieldCode": None,
            "conditions": [{"fieldCode": "quantity", "operator": "greater_than",
                            "comparisonValue": "999999", "comparisonFieldCode": None}],
            "actions": [{"actionType": "exclude_row"}]}


def api_result(response):
    payload = response.json()
    if response.status_code == 200:
        return payload["data"], None
    error = payload.get("error") or {}
    return None, error.get("code") if isinstance(error, dict) else str(error)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--director", type=int, default=1)
    args = parser.parse_args()
    state = json.loads(STATE.read_text(encoding="utf-8"))
    director = state["directors"][args.director - 1]
    with httpx.Client(base_url=BASE, timeout=60) as client:
        token = regular_login(client, director)
        draft = request(client, "GET", "/api/v1/company/configuration", bearer=token)
        draft["rules"] = draft.get("rules") or []
        pilot_id = f"load-rule-pilot-{args.director}"
        if not any(item["clientId"] == pilot_id for item in draft["rules"]):
            item = rule(f"pilot-{args.director}")
            draft["rules"].append(item)
            request(client, "PUT", "/api/v1/company/configuration", bearer=token,
                    body={"draft": draft, "deleteCategoryData": []})
        print("rule created")
        document = director["mixedDocuments"]["quote"]
        path = f"/api/v1/kanbans/{document['boardId']}/cards/{document['cardId']}/quote/"
        quote = request(client, "GET", path, bearer=token)
        headers = {"Authorization": "Bearer " + token}
        response = client.put(path, headers=headers, json=quote)
        _, code = api_result(response)
        print("save before recalculation", response.status_code, code)
        if code == "quote_calculation_outdated":
            preview = request(client, "GET", path + "calculation-preview", bearer=token)
            request(client, "POST", path + "apply-calculation", bearer=token, body={
                "currentCalculationVersion": preview["currentCalculationVersion"],
                "quoteUpdatedAt": preview["quoteUpdatedAt"]})
            quote = request(client, "GET", path, bearer=token)
            request(client, "PUT", path, bearer=token, body=quote)
            print("recalculation and save OK")


if __name__ == "__main__":
    main()
