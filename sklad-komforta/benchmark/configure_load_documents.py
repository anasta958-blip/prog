"""Add specialized quote, prequote and order boards to test organizations."""

import argparse
import copy
import json

import httpx

from create_load_users import BASE, STATE, regular_login, request


def configure(draft):
    workflows = draft["workflows"]
    if not any(item["code"] == "load_quote" for item in workflows):
        original = next(item for item in workflows if item["code"] == "quote")
        added = copy.deepcopy(original)
        added["code"] = "load_quote"
        added["name"] = "Нагрузочное КП"
        added["specialization"] = "quote"
        column_ids = {}
        for index, column in enumerate(added["columns"], 1):
            column_ids[column["clientId"]] = f"load_quote-{index}"
            column["clientId"] = f"load_quote-{index}"
            column["creationActions"] = ["quote"] if index == 1 else []
        for transition in added["transitions"]:
            transition["fromClientId"] = column_ids[transition["fromClientId"]]
            transition["toClientId"] = column_ids[transition["toClientId"]]
        workflows.append(added)
    for workflow in workflows:
        if workflow["code"] == "preliminary_quote":
            workflow["specialization"] = "prequote"
            workflow["columns"][0]["creationActions"] = ["prequote"]
        elif workflow["code"] == "order":
            workflow["specialization"] = "order"
            workflow["columns"][0]["creationActions"] = ["order"]
    return draft


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directors", type=int, default=10)
    args = parser.parse_args()
    state = json.loads(STATE.read_text(encoding="utf-8"))
    with httpx.Client(base_url=BASE, timeout=60) as client:
        for index, director in enumerate(state["directors"][:args.directors], 1):
            token = regular_login(client, director)
            draft = request(client, "GET", "/api/v1/company/configuration", bearer=token)
            update = configure(draft)
            request(client, "PUT", "/api/v1/company/configuration", bearer=token,
                    body={"draft": update, "deleteCategoryData": []})
            boards = request(client, "GET", "/api/v1/kanbans/", bearer=token)
            codes = {board["code"] for board in boards}
            if not {"load_quote", "preliminary_quote", "order"} <= codes:
                raise RuntimeError(f"director {index}: specialized boards missing")
            print(f"director={index} specialized boards ready", flush=True)


if __name__ == "__main__":
    main()
