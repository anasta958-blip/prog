"""Authenticated public-site load with 100 distinct test identities."""

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

PUBLIC_BASE = "https://app.eventlab.dpdns.org"


def percentile(values, percent):
    if not values:
        return None
    values = sorted(values)
    index = (len(values) - 1) * percent / 100
    lower = int(index)
    return round(values[lower] + (values[min(lower + 1, len(values) - 1)] - values[lower]) * (index - lower), 1)


def identities():
    state = json.loads(STATE.read_text(encoding="utf-8"))
    rows = []
    with httpx.Client(base_url=INTERNAL_BASE, timeout=20) as client:
        for director in state["directors"]:
            accounts = [director] + director["employees"][:9]
            for account, card in zip(accounts, director["loadCards"]):
                token = regular_login(client, account)
                live_card = request(client, "GET",
                    f"/api/v1/kanbans/{card['boardId']}/cards/{card['cardId']}", bearer=token)
                current = card.copy()
                current["columnId"] = live_card["columnId"]
                current["categoryId"] = live_card["categoryId"]
                rows.append({"token": token, "card": current,
                             "boardId": card["boardId"], "moved": False,
                             "counter": 0})
    # First ten users span all organizations; subsequent users are employees.
    return [rows[index] for index in range(0, len(rows), 10)] + [
        rows[index] for index in range(len(rows)) if index % 10 != 0]


class Load:
    def __init__(self, client):
        self.client = client
        self.samples = defaultdict(list)
        self.statuses = defaultdict(Counter)
        self.transition = {}

    async def call(self, user, name, method, path, **kwargs):
        begin = time.perf_counter()
        try:
            response = await self.client.request(method, path,
                headers={"Authorization": "Bearer " + user["token"]}, **kwargs)
            duration = (time.perf_counter() - begin) * 1000
            self.samples[name].append(duration)
            self.statuses[name][str(response.status_code)] += 1
            if response.status_code >= 400:
                return None
            data = response.json()
            if not data.get("ok", True):
                self.statuses[name]["api_error"] += 1
                return None
            return data.get("data", data)
        except Exception as error:
            self.samples[name].append((time.perf_counter() - begin) * 1000)
            self.statuses[name][type(error).__name__] += 1
            return None

    async def action(self, user, rng):
        card = user["card"]
        board = user["boardId"]
        base = f"/api/v1/kanbans/{board}"
        card_path = base + f"/cards/{card['cardId']}"
        choice = rng.random()
        if choice < .10:
            await self.call(user, "boards", "GET", "/api/v1/kanbans/")
        elif choice < .23:
            await self.call(user, "board", "GET", base)
        elif choice < .43:
            await self.call(user, "cards", "GET", base + "/cards", params={
                "columnId": card["columnId"], "page": 1, "pageSize": 20})
        elif choice < .56:
            await self.call(user, "card_search", "GET", base + "/cards", params={
                "columnId": card["columnId"], "search": "НАГРУЗОЧНЫЙ", "page": 1, "pageSize": 20})
        elif choice < .72:
            await self.call(user, "catalog_search", "GET", "/api/v1/catalog/items", params={
                "search": rng.choice(["НАГРУЗОЧНЫЙ", "товар 1", "LT-"]),
                "page": 1, "pageSize": 50})
        elif choice < .82:
            await self.call(user, "catalog_page", "GET", "/api/v1/catalog/items",
                            params={"page": 1, "pageSize": 50})
        elif choice < .90:
            await self.call(user, "card_open", "GET", card_path)
        elif choice < .96:
            user["counter"] += 1
            title = f"НАГРУЗОЧНЫЙ ТЕСТ {user['counter']}"
            result = await self.call(user, "card_edit", "PUT", card_path, json={
                "columnId": card["columnId"], "categoryId": card["categoryId"],
                "sectionId": None, "title": title, "values": {}})
            if result:
                card["title"] = title
        else:
            if not user["moved"]:
                board_data = await self.call(user, "board", "GET", base)
                transition = next((item for item in (board_data or {}).get("transitions", [])
                                   if item["fromColumnId"] == card["columnId"]), None)
                target = transition["toColumnId"] if transition else card["columnId"]
            else:
                target = card["columnId"]
            result = await self.call(user, "card_move", "POST", card_path + "/move", json={
                "targetColumnId": target, "targetIndex": 0})
            if result:
                card["columnId"] = result["columnId"]
                user["moved"] = True

    async def worker(self, number, user, end):
        rng = random.Random(number)
        while time.monotonic() < end:
            await self.action(user, rng)
            await asyncio.sleep(rng.uniform(.5, 1.5))

    async def phase(self, users, seconds, accounts):
        self.samples.clear()
        self.statuses.clear()
        start = time.monotonic()
        await asyncio.gather(*(self.worker(i, account, start + seconds)
                               for i, account in enumerate(accounts[:users])))
        operations = {}
        for name, values in self.samples.items():
            statuses = dict(self.statuses[name])
            operations[name] = {"count": len(values), "p50_ms": percentile(values, 50),
                                "p95_ms": percentile(values, 95), "p99_ms": percentile(values, 99),
                                "max_ms": percentile(values, 100),
                                "failures": sum(n for code, n in statuses.items() if code != "200"),
                                "status": statuses}
        total = sum(row["count"] for row in operations.values())
        errors = sum(row["failures"] for row in operations.values())
        elapsed = time.monotonic() - start
        return {"users": users, "duration_s": round(elapsed, 1), "requests": total,
                "rps": round(total / elapsed, 1),
                "failure_rate": round(errors / total, 4) if total else None,
                "operations": operations}


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=int, default=45)
    parser.add_argument("--users", type=str, default="10,25,50,100")
    parser.add_argument("--output", type=Path, default=Path("benchmark/live-distinct-100-result.json"))
    args = parser.parse_args()
    accounts = identities()
    if len(accounts) < 100:
        raise RuntimeError(f"Only {len(accounts)} test accounts are ready")
    result = {"started_utc": datetime.now(timezone.utc).isoformat(),
              "site": PUBLIC_BASE, "identity_model": "100 distinct accounts in 10 organizations",
              "phases": []}
    limits = httpx.Limits(max_connections=140, max_keepalive_connections=140)
    async with httpx.AsyncClient(base_url=PUBLIC_BASE, limits=limits, timeout=20) as client:
        workload = Load(client)
        for count in [int(item) for item in args.users.split(",")]:
            phase = await workload.phase(count, args.seconds, accounts)
            result["phases"].append(phase)
            print(f"users={count} requests={phase['requests']} rps={phase['rps']} "
                  f"failures={phase['failure_rate']:.2%}", flush=True)
            if phase["failure_rate"] > .05:
                result["stopped_early"] = "failure rate exceeded 5%"
                break
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"result={args.output}")


if __name__ == "__main__":
    asyncio.run(main())
