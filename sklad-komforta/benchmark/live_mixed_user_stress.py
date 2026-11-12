"""Mixed public-site workload with 100 distinct, independently acting users."""

import argparse
import asyncio
import json
import random
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import httpx

from create_load_users import BASE as INTERNAL_BASE, STATE, regular_login, request
from live_distinct_user_stress import percentile
from pilot_rule import rule
from seed_mixed_documents import order_payload, quote_payload

PUBLIC_BASE = "https://app.eventlab.dpdns.org"
ROLES = ("rules", "quote", "quote", "prequote", "order", "order",
         "catalog", "catalog", "kanban", "kanban")


def prepare_users():
    state = json.loads(STATE.read_text(encoding="utf-8"))
    groups = []
    with httpx.Client(base_url=INTERNAL_BASE, timeout=30) as client:
        for org_index, director in enumerate(state["directors"]):
            accounts = [director] + director["employees"][:9]
            tokens = [regular_login(client, account) for account in accounts]
            boards = request(client, "GET", "/api/v1/kanbans/", bearer=tokens[0])
            board_ids = {board["code"]: board["id"] for board in boards}
            board_data = {}
            for code in ("load_quote", "preliminary_quote", "order"):
                board_data[code] = request(client, "GET",
                    f"/api/v1/kanbans/{board_ids[code]}", bearer=tokens[0])
            company = request(client, "GET", "/api/v1/company/legal-entities",
                              bearer=tokens[0])[0]
            group = []
            for position, token in enumerate(tokens):
                card = director["loadCards"][position].copy()
                if ROLES[position] == "kanban":
                    live = request(client, "GET",
                        f"/api/v1/kanbans/{card['boardId']}/cards/{card['cardId']}",
                        bearer=token)
                    card["columnId"] = live["columnId"]
                    card["categoryId"] = live["categoryId"]
                group.append({"token": token, "role": ROLES[position], "org": org_index,
                              "position": position,
                              "director": director, "boardIds": board_ids,
                              "boards": board_data, "executorId": company["id"],
                              "card": card, "document": None,
                              "created": 0, "edited": 0, "rulesCreated": 0,
                              "ruleAttempts": 0,
                              "item": None, "moved": False})
            groups.append(group)
    return [groups[org][position] for position in range(10) for org in range(10)]


class MixedLoad:
    def __init__(self, client, run_id):
        self.client = client
        self.run_id = run_id
        self.samples = defaultdict(list)
        self.statuses = defaultdict(Counter)
        self.expected_recalculations = Counter()
        self.unresolved_conflicts = 0

    async def call(self, user, name, method, path, **kwargs):
        start = time.perf_counter()
        try:
            response = await self.client.request(method, path,
                headers={"Authorization": "Bearer " + user["token"]}, **kwargs)
            elapsed = (time.perf_counter() - start) * 1000
            self.samples[name].append(elapsed)
            body = response.json()
            if response.status_code == 200 and body.get("ok", True):
                self.statuses[name]["200"] += 1
                return body.get("data", body), None
            error = body.get("error") or {}
            code = error.get("code") if isinstance(error, dict) else str(error)
            if response.status_code == 409 and code in (
                "quote_calculation_outdated", "order_calculation_outdated",
                "quote_calculation_preview_outdated", "order_calculation_preview_outdated"):
                self.statuses[name]["expected_409"] += 1
                self.expected_recalculations[name] += 1
            else:
                self.statuses[name][str(response.status_code) + ":" + str(code)] += 1
            return None, code
        except Exception as error:
            self.samples[name].append((time.perf_counter() - start) * 1000)
            self.statuses[name][type(error).__name__] += 1
            return None, type(error).__name__

    async def search(self, user, rng):
        choice = rng.randrange(4)
        if choice == 0:
            await self.call(user, "boards", "GET", "/api/v1/kanbans/")
        elif choice == 1:
            board_id = user["card"]["boardId"]
            await self.call(user, "kanban_search", "GET",
                f"/api/v1/kanbans/{board_id}/cards", params={
                    "columnId": user["card"]["columnId"], "search": "НАГРУЗОЧНЫЙ",
                    "page": 1, "pageSize": 20})
        elif choice == 2:
            await self.call(user, "catalog_search", "GET", "/api/v1/catalog/items",
                params={"search": rng.choice(["НАГРУЗОЧНЫЙ", "товар", "LT-"]),
                        "page": 1, "pageSize": 50})
        else:
            await self.call(user, "catalog_page", "GET", "/api/v1/catalog/items",
                params={"page": 1, "pageSize": 50})

    async def change_rule(self, user):
        user["ruleAttempts"] += 1
        draft, error = await self.call(user, "configuration_read", "GET",
                                      "/api/v1/company/configuration")
        if error:
            return
        draft["rules"] = draft.get("rules") or []
        index = user["rulesCreated"] + 1
        key = f"{self.run_id}-{user['org']}-{index}"
        draft["rules"].append(rule(key))
        updated, error = await self.call(user, "rule_create", "PUT",
            "/api/v1/company/configuration",
            json={"draft": draft, "deleteCategoryData": []})
        if not error:
            user["rulesCreated"] += 1

    def document_info(self, user):
        kind = user["role"]
        code = {"quote": "load_quote", "prequote": "preliminary_quote",
                "order": "order"}[kind]
        board = user["boards"][code]
        action = "order" if kind == "order" else kind
        column = next(item for item in board["columns"] if action in item["creationActions"])
        return kind, board, column

    async def create_document(self, user):
        kind, board, column = self.document_info(user)
        director = user["director"]
        category_id = board["categories"][0]["categoryId"]
        item_id = director["loadCatalogItems"][0]
        serial = f"{self.run_id}-{user['org']}-{user['position']}-{user['created'] + 1}"
        if kind == "order":
            body = order_payload(director["mixedClientId"], user["executorId"],
                                 category_id, item_id, serial)
            route = "orders"
        else:
            body = quote_payload(kind, director["mixedClientId"], user["executorId"],
                                 category_id, item_id, serial)
            route = "quotes"
        created, error = await self.call(user, kind + "_create", "POST",
            f"/api/v1/kanbans/{board['id']}/{route}",
            json={"columnId": column["id"], "order" if kind == "order" else "quote": body})
        if not error:
            user["created"] += 1
            user["document"] = {"kind": kind, "boardId": board["id"],
                                "cardId": created["cardId"]}

    async def open_document(self, user):
        doc = user["document"] or user["director"]["mixedDocuments"][user["role"]]
        path = f"/api/v1/kanbans/{doc['boardId']}/cards/{doc['cardId']}/"
        path += "order/" if user["role"] == "order" else "quote/"
        return await self.call(user, user["role"] + "_open", "GET", path)

    async def save_document(self, user):
        if user["document"] is None:
            await self.create_document(user)
            if user["document"] is None:
                return
        doc = user["document"]
        path = f"/api/v1/kanbans/{doc['boardId']}/cards/{doc['cardId']}/"
        path += "order/" if user["role"] == "order" else "quote/"
        data, error = await self.call(user, user["role"] + "_open", "GET", path)
        if error:
            return
        if user["role"] == "order":
            position = data["categories"][0]["sections"][0]["positions"][0]
        else:
            position = data["proposalTypes"][0]["variants"][0]["categories"][0]["sections"][0]["positions"][0]
        position["quantity"] = 1 if position["quantity"] != 1 else 2
        desired_quantity = position["quantity"]
        saved, error = await self.call(user, user["role"] + "_save", "PUT", path, json=data)
        expected = "order_calculation_outdated" if user["role"] == "order" else "quote_calculation_outdated"
        if error == expected:
            preview_outdated = ("order_calculation_preview_outdated" if user["role"] == "order"
                                else "quote_calculation_preview_outdated")
            for _ in range(3):
                preview, preview_error = await self.call(user, "calculation_preview", "GET",
                                                         path + "calculation-preview")
                if preview_error:
                    return
                request_body = {"currentCalculationVersion": preview["currentCalculationVersion"],
                                ("orderUpdatedAt" if user["role"] == "order" else "quoteUpdatedAt"):
                                    preview["orderUpdatedAt" if user["role"] == "order" else "quoteUpdatedAt"]}
                _, apply_error = await self.call(user, "calculation_apply", "POST",
                                                 path + "apply-calculation", json=request_body)
                if apply_error == preview_outdated:
                    continue
                if apply_error:
                    return
                refreshed, get_error = await self.call(user, user["role"] + "_open", "GET", path)
                if get_error:
                    return
                if user["role"] == "order":
                    refreshed["categories"][0]["sections"][0]["positions"][0]["quantity"] = desired_quantity
                else:
                    refreshed["proposalTypes"][0]["variants"][0]["categories"][0]["sections"][0]["positions"][0]["quantity"] = desired_quantity
                saved, error = await self.call(user, user["role"] + "_save_retry", "PUT", path,
                                               json=refreshed)
                if error != expected:
                    break
            if error == expected:
                self.unresolved_conflicts += 1
        if not error:
            user["edited"] += 1

    async def catalog_action(self, user, rng):
        if user["created"] < 5 and rng.random() < .45:
            index = user["created"] + 1
            category = user["boards"]["load_quote"]["categories"][0]["categoryId"]
            item, error = await self.call(user, "catalog_create", "POST", "/api/v1/catalog/items",
                json={"categoryId": category, "sectionId": None, "groupId": None,
                      "name": f"НАГРУЗОЧНЫЙ ТЕСТ товар {self.run_id}-{user['org']}-{user['position']}-{index}",
                      "marking": f"LT-{user['org']}-{user['position']}-{index}",
                      "status": "approved", "values": {}})
            if not error:
                user["created"] += 1
                user["item"] = item["id"]
        elif user["item"] and rng.random() < .35:
            item, error = await self.call(user, "catalog_open", "GET",
                f"/api/v1/catalog/items/{user['item']}")
            if error:
                return
            await self.call(user, "catalog_edit", "PUT",
                f"/api/v1/catalog/items/{user['item']}", json={
                    "categoryId": item["categoryId"], "sectionId": item["sectionId"],
                    "groupId": item["groupId"], "name": item["name"],
                    "marking": item["marking"], "status": item["status"],
                    "values": item["values"]})
        else:
            await self.search(user, rng)

    async def kanban_action(self, user, rng):
        card = user["card"]
        path = f"/api/v1/kanbans/{card['boardId']}/cards/{card['cardId']}"
        choice = rng.random()
        if choice < .3:
            await self.call(user, "card_open", "GET", path)
        elif choice < .6:
            await self.search(user, rng)
        elif choice < .8:
            user["edited"] += 1
            await self.call(user, "card_edit", "PUT", path, json={
                "columnId": card["columnId"], "categoryId": card["categoryId"],
                "sectionId": None,
                "title": f"НАГРУЗОЧНЫЙ ТЕСТ {self.run_id}-{user['edited']}", "values": {}})
        else:
            board, error = await self.call(user, "board", "GET",
                f"/api/v1/kanbans/{card['boardId']}")
            if error:
                return
            transition = next((item for item in board["transitions"]
                               if item["fromColumnId"] == card["columnId"]), None)
            target = transition["toColumnId"] if transition and not user["moved"] else card["columnId"]
            moved, move_error = await self.call(user, "card_move", "POST", path + "/move",
                json={"targetColumnId": target, "targetIndex": 0})
            if not move_error:
                card["columnId"] = moved["columnId"]
                user["moved"] = True

    async def worker(self, number, user, phase_users, phase_start, stop_at):
        rng = random.Random(number + phase_users * 1000)
        while time.monotonic() < stop_at:
            role = user["role"]
            if role == "rules":
                should_create = user["ruleAttempts"] == 0 or (
                    phase_users >= 100 and user["ruleAttempts"] == 1
                    and time.monotonic() - phase_start >= 40)
                if should_create:
                    await self.change_rule(user)
                else:
                    await self.search(user, rng)
            elif role in ("quote", "prequote", "order"):
                choice = rng.random()
                if user["document"] is None or (user["created"] < 2 and phase_users >= 100 and choice < .08):
                    await self.create_document(user)
                elif choice < .55:
                    await self.save_document(user)
                elif choice < .75:
                    await self.open_document(user)
                else:
                    await self.search(user, rng)
            elif role == "catalog":
                await self.catalog_action(user, rng)
            else:
                await self.kanban_action(user, rng)
            await asyncio.sleep(rng.uniform(1.0, 3.0))

    async def phase(self, count, seconds, users):
        self.samples.clear()
        self.statuses.clear()
        self.expected_recalculations.clear()
        self.unresolved_conflicts = 0
        start = time.monotonic()
        await asyncio.gather(*(self.worker(i, user, count, start, start + seconds)
                               for i, user in enumerate(users[:count])))
        operations = {}
        for name, timings in self.samples.items():
            statuses = dict(self.statuses[name])
            failures = sum(value for code, value in statuses.items()
                           if code not in ("200", "expected_409"))
            operations[name] = {"count": len(timings), "p50_ms": percentile(timings, 50),
                                "p95_ms": percentile(timings, 95), "p99_ms": percentile(timings, 99),
                                "max_ms": percentile(timings, 100), "failures": failures,
                                "status": statuses}
        count_requests = sum(item["count"] for item in operations.values())
        failures = sum(item["failures"] for item in operations.values()) + self.unresolved_conflicts
        elapsed = time.monotonic() - start
        return {"users": count, "duration_s": round(elapsed, 1),
                "requests": count_requests, "rps": round(count_requests / elapsed, 1),
                "unexpected_failures": failures,
                "failure_rate": round(failures / count_requests, 5) if count_requests else 0,
                "unresolved_conflicts": self.unresolved_conflicts,
                "expected_recalculations": dict(self.expected_recalculations),
                "operations": operations}


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--users", default="10,25,50,100")
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--output", type=Path, default=Path("benchmark/live-mixed-100-result.json"))
    args = parser.parse_args()
    users = prepare_users()
    if len(users) != 100:
        raise RuntimeError(f"Expected 100 users, got {len(users)}")
    result = {"started_utc": datetime.now(timezone.utc).isoformat(),
              "site": PUBLIC_BASE, "identity_model": "100 accounts across 10 organizations",
              "roles": Counter(user["role"] for user in users), "phases": []}
    limits = httpx.Limits(max_connections=150, max_keepalive_connections=150)
    async with httpx.AsyncClient(base_url=PUBLIC_BASE, limits=limits, timeout=20) as client:
        load = MixedLoad(client, datetime.now(timezone.utc).strftime("%y%m%d%H%M%S"))
        for count in [int(value) for value in args.users.split(",")]:
            phase = await load.phase(count, args.seconds, users)
            result["phases"].append(phase)
            print(f"users={count} requests={phase['requests']} rps={phase['rps']} "
                  f"unexpected={phase['unexpected_failures']} "
                  f"recalculations={sum(phase['expected_recalculations'].values())}", flush=True)
            if phase["failure_rate"] > .05:
                result["stopped_early"] = "unexpected failure rate exceeded 5%"
                break
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"result={args.output}")


if __name__ == "__main__":
    asyncio.run(main())
