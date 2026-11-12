"""Create independent universal cards for load-test users in each organization."""

import argparse
import json

import httpx

from create_load_users import BASE, STATE, regular_login, request, save


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directors", type=int, default=10)
    args = parser.parse_args()
    state = json.loads(STATE.read_text(encoding="utf-8"))
    with httpx.Client(base_url=BASE, timeout=30) as client:
        for index, director in enumerate(state["directors"][:args.directors], 1):
            token = regular_login(client, director)
            boards = request(client, "GET", "/api/v1/kanbans/", bearer=token)
            board = request(client, "GET", f"/api/v1/kanbans/{boards[0]['id']}", bearer=token)
            column = board["columns"][0]
            category = board["categories"][0]
            director.setdefault("loadCatalogItems", [])
            while len(director["loadCatalogItems"]) < 30:
                number = len(director["loadCatalogItems"]) + 1
                item = request(client, "POST", "/api/v1/catalog/items", bearer=token, body={
                    "categoryId": category["categoryId"], "sectionId": None, "groupId": None,
                    "name": f"НАГРУЗОЧНЫЙ ТЕСТ товар {index}-{number}",
                    "marking": f"LT-{index:02d}-{number:03d}", "status": "approved", "values": {}})
                director["loadCatalogItems"].append(item["id"])
                save(state)
            director.setdefault("loadCards", [])
            while len(director["loadCards"]) < 10:
                number = len(director["loadCards"]) + 1
                payload = {"columnId": column["id"], "categoryId": category["categoryId"],
                           "sectionId": None, "title": f"НАГРУЗОЧНЫЙ ТЕСТ {index}-{number}",
                           "values": {}}
                card = request(client, "POST", f"/api/v1/kanbans/{board['id']}/cards",
                               bearer=token, body=payload)
                director["loadCards"].append({"boardId": board["id"], "cardId": card["id"],
                                              "columnId": column["id"],
                                              "categoryId": category["categoryId"],
                                              "title": card["title"]})
                save(state)
            print(f"director={index} cards={len(director['loadCards'])} items={len(director['loadCatalogItems'])}", flush=True)


if __name__ == "__main__":
    main()
