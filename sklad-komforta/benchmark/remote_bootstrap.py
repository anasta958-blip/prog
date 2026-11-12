"""Run on the VM: bootstrap one director through the internal API only."""

import json
import subprocess
import sys
import urllib.error
import urllib.request

container = "sklad-komforta-server-api-1"
details = json.loads(subprocess.check_output(["docker", "inspect", container]))[0]
secret = next(value.split("=", 1)[1] for value in details["Config"]["Env"]
              if value.startswith("Security__BootstrapToken="))
addresses = [network["IPAddress"] for network in details["NetworkSettings"]["Networks"].values()]
payload = sys.stdin.buffer.read()
for address in addresses:
    url = f"http://{address}:8080/api/v1/auth/bootstrap/director"
    request = urllib.request.Request(url, data=payload, method="POST", headers={
        "Content-Type": "application/json", "X-Bootstrap-Token": secret})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            body = json.load(response)
        print(json.dumps({"status": 200, "ok": body.get("ok", True)}))
        break
    except urllib.error.HTTPError as error:
        try:
            data = json.load(error)
            failure = data.get("error", {})
            code = failure.get("code") if isinstance(failure, dict) else str(failure)
        except ValueError:
            code = "non_json_response"
        print(json.dumps({"status": error.code, "code": code}))
        break
    except (urllib.error.URLError, TimeoutError):
        continue
else:
    print(json.dumps({"status": 0, "code": "internal_api_unreachable"}))
