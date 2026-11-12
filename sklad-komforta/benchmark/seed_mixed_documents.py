"""Seed one КП, ПКП and комплектация in each test organization."""

import argparse
import json

import httpx

from create_load_users import BASE, STATE, regular_login, request, save


def client_payload(number):
    nullable = ("companyName", "legalName", "inn", "kpp", "ogrn", "contactName", "phone",
                "email", "address", "objectType", "objectAddress", "recipientName",
                "salutation", "proposalTitle", "introText", "bankName", "bankBik",
                "bankAccount", "corrAccount", "passportSeries", "passportNumber",
                "passportIssuedBy", "note")
    return {"name": f"Нагрузочный клиент {number}", "companyType": "person",
            **{key: None for key in nullable}}


def quote_payload(kind, client_id, executor_id, category_id, item_id, number):
    return {"quoteKind": kind, "title": f"НАГРУЗКА {kind} {number}",
            "clientId": client_id, "executorCompanyId": executor_id,
            "managerUserId": None, "salesHeadUserId": None,
            "selectionMode": "variant", "additionalInformation": None,
            "proposalTypes": [{"id": None, "name": "Основной тип", "selectedVariantId": None,
                               "variants": [{"id": None, "name": "Основной вариант",
                                             "subtitle": None, "vatRate": 20,
                                             "categories": [{"id": None,
                                                             "catalogCategoryId": category_id,
                                                             "name": "Тестовая категория",
                                                             "sections": [{"id": None,
                                                                           "catalogSectionId": None,
                                                                           "name": "Раздел",
                                                                           "markupPercent": None,
                                                                           "discountPercent": None,
                                                                           "positions": [{
                                                                               "id": None,
                                                                               "catalogItemId": item_id,
                                                                               "name": "Нагрузочный товар",
                                                                               "marking": "LT-01",
                                                                               "unit": "шт", "quantity": 1,
                                                                               "purchasePrice": 50,
                                                                               "basePrice": 100,
                                                                               "manualPrice": None,
                                                                               "markupPercent": None,
                                                                               "discountPercent": None,
                                                                               "excludeFromTotals": False,
                                                                               "values": {}}]}]}]}]}]}


def order_payload(client_id, executor_id, category_id, item_id, number):
    return {"title": f"НАГРУЗКА комплектация {number}", "objectType": None,
            "clientId": client_id, "executorCompanyId": executor_id,
            "managerUserId": None, "salesHeadUserId": None,
            "categories": [{"id": None, "catalogCategoryId": category_id,
                            "name": "Тестовая категория", "sections": [{
                                "id": None, "catalogSectionId": None, "name": "Раздел",
                                "positions": [{"id": None, "catalogItemId": item_id,
                                               "name": "Нагрузочный товар", "marking": "LT-01",
                                               "unit": "шт", "quantity": 1, "values": {}}]}]}]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directors", type=int, default=10)
    args = parser.parse_args()
    state = json.loads(STATE.read_text(encoding="utf-8"))
    with httpx.Client(base_url=BASE, timeout=60) as client:
        for index, director in enumerate(state["directors"][:args.directors], 1):
            token = regular_login(client, director)
            if not director.get("mixedClientId"):
                created = request(client, "POST", "/api/v1/company/clients", bearer=token,
                                  body=client_payload(index))
                director["mixedClientId"] = created["id"]
                save(state)
            company = request(client, "GET", "/api/v1/company/legal-entities", bearer=token)[0]
            boards = request(client, "GET", "/api/v1/kanbans/", bearer=token)
            by_code = {board["code"]: board["id"] for board in boards}
            director.setdefault("mixedDocuments", {})
            for key, code, action in (("quote", "load_quote", "quote"),
                                      ("prequote", "preliminary_quote", "prequote"),
                                      ("order", "order", "order")):
                if key in director["mixedDocuments"]:
                    continue
                board_id = by_code[code]
                board = request(client, "GET", f"/api/v1/kanbans/{board_id}", bearer=token)
                column = next(c for c in board["columns"] if action in c["creationActions"])
                category_id = board["categories"][0]["categoryId"]
                item_id = director["loadCatalogItems"][0]
                if key == "order":
                    path = f"/api/v1/kanbans/{board_id}/orders"
                    body = {"columnId": column["id"], "order": order_payload(
                        director["mixedClientId"], company["id"], category_id, item_id, index)}
                else:
                    path = f"/api/v1/kanbans/{board_id}/quotes"
                    body = {"columnId": column["id"], "quote": quote_payload(
                        key, director["mixedClientId"], company["id"], category_id, item_id, index)}
                created = request(client, "POST", path, bearer=token, body=body)
                director["mixedDocuments"][key] = {
                    "boardId": board_id, "cardId": created["cardId"], "columnId": column["id"]}
                save(state)
            print(f"director={index} quote/prequote/order ready", flush=True)


if __name__ == "__main__":
    main()
