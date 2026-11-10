#!/usr/bin/env python3
"""Sandbox wallpaper contrast command and control endpoint; never read host wallpaper."""
import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile
import time

if not os.environ.get("ARANEA_TEST_SANDBOX"):
    raise RuntimeError("bar foreground fixture requires a test sandbox")
state_home = Path(os.environ["XDG_STATE_HOME"])
if not state_home.is_absolute():
    raise RuntimeError("bar foreground fixture requires an absolute private state root")
root = state_home / "bar-foreground-fixture"
root.mkdir(exist_ok=True)
args = sys.argv[1:]


def update(fn, *, read_only=False):
    with (root / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / "state.json"
        state = json.loads(path.read_text()) if path.exists() else {
            "response": "", "delay": 0, "started": 0, "finished": 0, "calls": [],
        }
        result = fn(state)
        if read_only:
            return result
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", dir=root, prefix=".state-", delete=False,
            ) as stream:
                temporary = Path(stream.name)
                json.dump(state, stream)
            temporary.replace(path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        return result


if Path(sys.argv[0]).name == "bar-foreground-fixture":
    def configure(state):
        state.update(json.loads(args[1]))
        return state
    if args[0] == "wallpaper":
        current = Path(os.environ["XDG_STATE_HOME"]) / "omarchy" / "current"
        current.write_text(current.read_text() + "changed\n")
    print(json.dumps(update(
        configure if args[0] == "configure" else lambda state: state,
        read_only=args[0] != "configure",
    )))
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
