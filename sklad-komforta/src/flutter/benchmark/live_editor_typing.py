"""Measure keyboard-to-paint latency in a manually opened Edge editor.

Usage: python benchmark/live_editor_typing.py 65 902 699 0.06
The x/y coordinates must point to a numeric input in the visible test document.
Edge must be started with --remote-debugging-port=9223.
"""

import json
import math
import os
import statistics
import sys
import time
from urllib.request import urlopen

import websocket


if len(sys.argv) < 4:
    raise SystemExit("Usage: live_editor_typing.py SAMPLES INPUT_X INPUT_Y [INTERVAL_SECONDS]")
samples = int(sys.argv[1])
x = int(sys.argv[2])
y = int(sys.argv[3])
interval = float(sys.argv[4]) if len(sys.argv) > 4 else 0.06
debug_port = int(os.environ.get("BENCH_DEBUG_PORT", "9223"))
page_prefix = os.environ.get("BENCH_PAGE_PREFIX", "https://app.eventlab.dpdns.org")
with urlopen(f"http://127.0.0.1:{debug_port}/json/list", timeout=5) as response:
    pages = json.load(response)
page = next(
    page for page in pages
    if page.get("type") == "page"
    and page.get("url", "").startswith(page_prefix)
)
connection = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=15)
request_id = 0


def call(method, params=None):
    global request_id
    request_id += 1
    connection.send(json.dumps({"id": request_id, "method": method, "params": params or {}}))
    while True:
        response = json.loads(connection.recv())
        if response.get("id") == request_id:
            if "error" in response:
                raise RuntimeError(response["error"])
            return response.get("result", {})


def key(key_name, code, virtual_key, text="", modifiers=0):
    call("Input.dispatchKeyEvent", {
        "type": "keyDown", "key": key_name, "code": code,
        "windowsVirtualKeyCode": virtual_key, "nativeVirtualKeyCode": virtual_key,
        "text": text, "unmodifiedText": text, "modifiers": modifiers,
    })
    call("Input.dispatchKeyEvent", {
        "type": "keyUp", "key": key_name, "code": code,
        "windowsVirtualKeyCode": virtual_key, "nativeVirtualKeyCode": virtual_key,
        "modifiers": modifiers,
    })


try:
    call("Runtime.evaluate", {
        "expression": """(() => {
          window.__typingSamples = [];
          window.__digitStarts = [];
          window.__eventEntries = [];
          window.__longFrames = [];
          if (window.__eventObserver) window.__eventObserver.disconnect();
          window.__eventObserver = new PerformanceObserver(list => {
            for (const entry of list.getEntries()) {
              if (entry.name === 'keydown') window.__eventEntries.push({ start: entry.startTime, duration: entry.duration });
            }
          });
          window.__eventObserver.observe({ type: 'event', durationThreshold: 16 });
          if (window.__frameObserver) window.__frameObserver.disconnect();
          window.__frameObserver = new PerformanceObserver(list => {
            for (const entry of list.getEntries()) {
              window.__longFrames.push({
                duration: entry.duration,
                blockingDuration: entry.blockingDuration,
                scripts: (entry.scripts || []).map(script => ({
                  duration: script.duration, invoker: script.invoker,
                  sourceURL: script.sourceURL, sourceFunctionName: script.sourceFunctionName,
                })),
              });
            }
          });
          window.__frameObserver.observe({ type: 'long-animation-frame' });
          if (window.__typingHandler) window.removeEventListener('keydown', window.__typingHandler, true);
          window.__typingHandler = event => {
            if (event.code !== 'Digit2' && event.code !== 'Digit3') return;
            window.__digitStarts.push(event.timeStamp);
            const start = performance.now();
            requestAnimationFrame(() => requestAnimationFrame(() => {
              window.__typingSamples.push(performance.now() - start);
            }));
          };
          window.addEventListener('keydown', window.__typingHandler, true);
        })()""",
    })
    for event_type in ("mousePressed", "mouseReleased"):
        call("Input.dispatchMouseEvent", {
            "type": event_type, "x": x, "y": y,
            "button": "left", "buttons": 1 if event_type == "mousePressed" else 0,
            "clickCount": 1,
        })
    time.sleep(0.2)
    active = call("Runtime.evaluate", {
        "expression": "document.activeElement?.tagName",
        "returnByValue": True,
    })["result"].get("value")
    if active != "INPUT":
        raise RuntimeError(f"Clicked target did not focus an input: {active}")
    for index in range(samples):
        key("a", "KeyA", 65, modifiers=2)
        time.sleep(0.012)  # Separate selection and digit events for Event Timing.
        digit = "2" if index % 2 == 0 else "3"
        key(digit, f"Digit{digit}", ord(digit), text=digit)
        time.sleep(interval)
    time.sleep(0.5)
    result = call("Runtime.evaluate", {
        "expression": "({samples: window.__typingSamples, digitStarts: window.__digitStarts, eventEntries: window.__eventEntries, longFrames: window.__longFrames, activeTag: document.activeElement?.tagName, activeValue: document.activeElement?.value})",
        "returnByValue": True,
    })["result"].get("value", {})
    recorded = result.get("samples") or []
    if len(recorded) < samples or len(recorded) % samples:
        raise RuntimeError(f"Expected {samples} keyboard samples, got {len(recorded)}; focus={result.get('activeTag')}")
    # Older listeners may remain after a probe in the same tab; they record the same event.
    one_per_event = recorded[::len(recorded) // samples]
    values = sorted(one_per_event[5:] if samples > 5 else one_per_event)
    digit_starts = result.get("digitStarts") or []
    event_entries = result.get("eventEntries") or []
    matched = []
    for start in digit_starts[5:]:
        if event_entries:
            nearest = min(event_entries, key=lambda entry: abs(entry["start"] - start))
            if abs(nearest["start"] - start) < 5:
                matched.append(nearest["duration"])
    matched.sort()
    long_frames = result.get("longFrames") or []
    long_durations = sorted(frame["duration"] for frame in long_frames)
    top_scripts = sorted(
        (script for frame in long_frames for script in frame.get("scripts", [])),
        key=lambda script: script.get("duration") or 0,
        reverse=True,
    )[:3]
    print(json.dumps({
        "samples": len(values),
        "p50_two_raf_ms": round(statistics.median(values), 2),
        "p95_two_raf_ms": round(values[math.floor(len(values) * 0.95)], 2),
        "max_two_raf_ms": round(values[-1], 2),
        "activeTag": result.get("activeTag"),
        "activeValue": result.get("activeValue"),
        "eventTimingCount": len(matched),
        "eventTimingP95Ms": matched[math.floor(len(matched) * 0.95)] if matched else None,
        "longFrameCount": len(long_frames),
        "longFrameP95Ms": round(long_durations[math.floor(len(long_durations) * 0.95)], 2) if long_durations else None,
        "topScripts": top_scripts,
    }))
finally:
    connection.close()
