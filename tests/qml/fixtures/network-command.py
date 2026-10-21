#!/usr/bin/env python3
"""Sandbox command boundary for real Network telemetry, never host networking."""
import fcntl
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["ARANEA_TEST_SANDBOX"]) / "network-fixture"
root.mkdir(exist_ok=True)
name = Path(sys.argv[0]).name
args = sys.argv[1:]


def update(fn):
    with (root / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / "state.json"
        state = json.loads(path.read_text()) if path.exists() else {
            "response": "", "delay": 0, "started": 0, "finished": 0,
        }
        result = fn(state)
        path.write_text(json.dumps(state))
        return result


if name == "network-fixture":
    def configure(state):
        state.update(json.loads(args[1]))
        return state
    print(json.dumps(update(configure if args[0] == "configure" else lambda state: state)))
elif name == "omarchy-network-status" and args == ["--verbose"]:
    def accept(state):
        state["started"] += 1
        return state["delay"], state["response"]
    delay, response = update(accept)
    time.sleep(delay)
    print(response)
    def finish(state):
        state["finished"] += 1
    update(finish)
