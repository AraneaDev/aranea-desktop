#!/usr/bin/env python3
"""Sandbox wallpaper contrast command and control endpoint; never read host wallpaper."""
import fcntl
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["ARANEA_TEST_SANDBOX"]) / "bar-foreground-fixture"
root.mkdir(exist_ok=True)
args = sys.argv[1:]


def update(fn):
    with (root / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / "state.json"
        state = json.loads(path.read_text()) if path.exists() else {
            "response": "", "delay": 0, "started": 0, "finished": 0, "calls": [],
        }
        result = fn(state)
        path.write_text(json.dumps(state))
        return result


if Path(sys.argv[0]).name == "bar-foreground-fixture":
    def configure(state):
        state.update(json.loads(args[1]))
        return state
    if args[0] == "wallpaper":
        current = Path(os.environ["XDG_STATE_HOME"]) / "omarchy" / "current"
        current.write_text(current.read_text() + "changed\n")
    print(json.dumps(update(configure if args[0] == "configure" else lambda state: state)))
else:
    def accept(state):
        state["started"] += 1
        state["calls"].append(args)
        return state["delay"], state["response"]
    delay, response = update(accept)
    time.sleep(delay)
    print(response, flush=True)
    def finish(state):
        state["finished"] += 1
    update(finish)
