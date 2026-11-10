#!/usr/bin/env python3
"""Sandbox command boundary for real Weather location, never host networking."""
import fcntl
import json
import os
import signal
from pathlib import Path
import sys
import tempfile
import time

root = Path(os.environ["ARANEA_TEST_SANDBOX"]) / "weather-fixture"
root.mkdir(exist_ok=True)
name = Path(sys.argv[0]).name
args = sys.argv[1:]


def update(fn, *, read_only=False):
    with (root / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / "state.json"
        state = json.loads(path.read_text()) if path.exists() else {
            "response": "", "delay": 0, "started": 0, "finished": 0,
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


if name == "weather-fixture":
    def configure(state):
        options = json.loads(args[1])
        state.update(options)
        if "locationFile" in options:
            path = root / "weather.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            if options["locationFile"] is None:
                path.unlink(missing_ok=True)
            else:
                path.write_text(json.dumps(options["locationFile"]))
        return state
    if args[0] == "configure":
        print(json.dumps(update(configure)))
    else:
        print(json.dumps(update(lambda state: state, read_only=True)))
elif name == "curl":
    url = args[-1]
    kind = "geo" if url == "https://geo.omarchy.org/" else "air" if "air-quality-api" in url else "daily" if "api.open-meteo.com" in url else "forecast"
    def accept(state):
        state.setdefault("calls", []).append({"kind": kind, "argv": args, "tag": state.get("requestTag", "")})
        state[kind + "Started"] = state.get(kind + "Started", 0) + 1
        return state.get(kind + "Delay", 0), state.get(kind + "Body", ""), state.get(kind + "Exit", 0), state.get("cancelDelays", {}).get(kind, 0), state.get("ignoreCancel", False), state.get("requestTag", "")
    delay, response, code, cancel_delay, ignore_cancel, tag = update(accept)
    def canceled(_signal, _frame):
        if ignore_cancel:
            return
        time.sleep(cancel_delay)
        sys.exit(143)
    signal.signal(signal.SIGTERM, canceled)
    time.sleep(delay)
    print(response, flush=True)
    def finish(state):
        state[kind + "Finished"] = state.get(kind + "Finished", 0) + 1
        state.setdefault("completed", []).append({"kind": kind, "tag": tag})
    update(finish)
    sys.exit(code)
elif name == "omarchy-weather-location":
    update(lambda state: state.setdefault("saved", []).append(args))
