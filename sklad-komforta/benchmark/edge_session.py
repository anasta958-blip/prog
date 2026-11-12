"""Read the signed-in test Edge session without printing its access token.

Refresh rotates the browser cookie. Reload the page after a probe to synchronize
the app's in-memory token, and save any editor changes before calling this.
"""

import json
import os
import urllib.request

import websocket


def edge_token():
    port = os.getenv("BENCH_DEBUG_PORT", "9224")
    pages = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
    page = next(item for item in pages if item.get("type") == "page"
                and item.get("url", "").startswith("https://app.eventlab.dpdns.org"))
    connection = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=20)
    expression = """(async () => {
      const response = await fetch('/api/v1/auth/refresh', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body:JSON.stringify({refreshToken:''})});
      const body = await response.json();
      return (body.data ?? body).accessToken ?? null;
    })()"""
    connection.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {
        "expression": expression, "awaitPromise": True, "returnByValue": True}}))
    try:
        while True:
            response = json.loads(connection.recv())
            if response.get("id") == 1:
                token = response.get("result", {}).get("result", {}).get("value")
                if not token:
                    raise RuntimeError("Edge session is not authenticated")
                return token
    finally:
        connection.close()
