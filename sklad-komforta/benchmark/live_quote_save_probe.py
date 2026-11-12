"""Measure one unchanged full quote save through the public site.

Save pending editor changes first. This probe rotates the Edge refresh cookie;
reload the browser page afterwards to synchronize the interactive session.
"""

import json
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx

from edge_session import edge_token

BASE = "https://app.eventlab.dpdns.org"

BOARD_ID = "a6e39036-60c7-4329-b1d9-637df5f5119d"
CARD_ID = "264ce6d8-3bed-4195-aa4c-f9d1c929181d"
PATH = f"/api/v1/kanbans/{BOARD_ID}/cards/{CARD_ID}/quote/"


def main():
    token = edge_token()
    result = {"at_utc": datetime.now(timezone.utc).isoformat(), "path": PATH}
    with httpx.Client(base_url=BASE, headers={"Authorization": "Bearer " + token},
                      timeout=120) as client:
        start = time.perf_counter()
        response = client.get(PATH)
        result["get_ms"] = round((time.perf_counter() - start) * 1000, 1)
        result["get_status"] = response.status_code
        if response.status_code != 200:
            print(f"quote GET status={response.status_code}")
            return
        quote = response.json()["data"]
        result["positions"] = sum(len(section["positions"])
            for kind in quote["proposalTypes"] for variant in kind["variants"]
            for category in variant["categories"] for section in category["sections"])
        result["request_bytes"] = len(json.dumps(quote, ensure_ascii=False).encode("utf-8"))
        start = time.perf_counter()
        saved = client.put(PATH, json=quote)
        result["put_ms"] = round((time.perf_counter() - start) * 1000, 1)
        result["put_status"] = saved.status_code
        if saved.status_code != 200:
            try:
                error = saved.json().get("error", {})
                result["put_error_code"] = error.get("code") if isinstance(error, dict) else str(error)
            except ValueError:
                result["put_error_code"] = "non_json_response"
    target = Path("benchmark/live-quote-save-result.json")
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"quote positions={result['positions']} GET={result['get_ms']}ms "
          f"PUT={result['put_ms']}ms status={result['put_status']}")


if __name__ == "__main__":
    main()
