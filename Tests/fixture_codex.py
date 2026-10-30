#!/usr/bin/python3
"""Local protocol fixture. No account, network, or credentials are used."""
import json
import sys

initialized = False
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialize":
        assert message["params"]["clientInfo"]["name"] == "dockgrove"
        print(json.dumps({"id": 0, "result": {"userAgent": "fixture"}}), flush=True)
    elif method == "initialized":
        initialized = True
    elif method == "account/rateLimits/read":
        assert initialized
        reply = json.dumps({"id": 1, "result": {"rateLimits": {"limitId": "codex", "primary": {"usedPercent": 37, "windowDurationMins": 300, "resetsAt": 2000000000}}}})
        # Write an unrelated notification and a split response to exercise framing.
        print(json.dumps({"method": "account/updated", "params": {}}), flush=True)
        sys.stdout.write(reply[:20]); sys.stdout.flush()
        sys.stdout.write(reply[20:] + "\n"); sys.stdout.flush()
    else:
        raise AssertionError("Unexpected or mutating RPC: " + str(method))
