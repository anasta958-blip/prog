"""Run the profile Web editor benchmark with Edge's real clock."""

import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
from urllib.request import urlopen

import websocket


ROOT = Path(__file__).resolve().parents[1]
EDGE = Path(
    os.environ.get(
        "EDGE_PATH",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    )
)
PAGE = ROOT / "build" / "web" / "index.html"


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def main():
    if not PAGE.exists():
        raise SystemExit("Build the profile Web benchmark first.")
    index = PAGE.read_text(encoding="utf-8")
    if '<base href="/">' in index:
        PAGE.write_text(index.replace('<base href="/">', '<base href="./">'), encoding="utf-8")
    cases = [(rows, complex) for rows in (100, 500, 1000) for complex in (False, True)]
    page_url = PAGE.resolve().as_uri()
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as profile:
        port = free_port()
        edge = subprocess.Popen(
            [
                str(EDGE),
                "--headless=new",
                "--no-sandbox",
                "--allow-file-access-from-files",
                "--remote-allow-origins=*",
                f"--remote-debugging-port={port}",
                f"--user-data-dir={profile}",
                f"{page_url}?rows=100&complex=0",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        try:
            endpoint = f"http://127.0.0.1:{port}/json"
            deadline = time.monotonic() + 30
            target = None
            while time.monotonic() < deadline:
                try:
                    with urlopen(endpoint, timeout=1) as response:
                        pages = json.load(response)
                    target = next(
                        (
                            page
                            for page in pages
                            if page.get("type") == "page"
                            and page.get("url", "").startswith("file:")
                        ),
                        None,
                    )
                    if target:
                        break
                except (OSError, ValueError):
                    pass
                time.sleep(0.2)
            if not target:
                raise RuntimeError("Edge did not expose the benchmark page")
            connection = websocket.create_connection(
                target["webSocketDebuggerUrl"], timeout=5
            )
            try:
                request_id = 0
                def call(method, params):
                    nonlocal request_id
                    request_id += 1
                    connection.send(
                        json.dumps(
                            {
                                "id": request_id,
                                "method": method,
                                "params": params,
                            }
                        )
                    )
                    while True:
                        reply = json.loads(connection.recv())
                        if reply.get("id") == request_id:
                            return reply

                for case_index, (rows, complex) in enumerate(cases):
                    if case_index:
                        call(
                            "Page.navigate",
                            {
                                "url": f"{page_url}?rows={rows}&complex={int(complex)}"
                            },
                        )
                    deadline = time.monotonic() + 90
                    expected = f"rows={rows} complex={str(complex).lower()}"
                    while time.monotonic() < deadline:
                        reply = call(
                            "Runtime.evaluate",
                            {
                                "expression": "document.getElementById('benchmark-result')?.textContent"
                            },
                        )
                        value = reply.get("result", {}).get("result", {}).get("value")
                        if isinstance(value, str) and value.startswith("BENCH error="):
                            raise RuntimeError(value)
                        if isinstance(value, str) and expected in value and "samples=" in value:
                            print(value, flush=True)
                            break
                        time.sleep(0.25)
                    else:
                        raise TimeoutError(f"Benchmark {expected} did not finish")
            finally:
                connection.close()
        finally:
            edge.terminate()
            edge.wait(timeout=10)


if __name__ == "__main__":
    main()
