#!/usr/bin/env python3
"""Sandbox-only Display command boundary, shared by real QML controller tests."""
import fcntl
import json
import os
from pathlib import Path
import sys
import time

name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == "ls" and args != ["/sys/class/leds"]:
    os.execv("/usr/bin/ls", ["ls", *args])
root = Path(os.environ["ARANEA_DISPLAY_FIXTURE_ROOT"])


def defaults():
    return {
        "textDelay": 0.15, "textFail": False, "textValues": [],
        "nightDelay": 0.15, "nightReadDelay": 0, "nightFail": False,
        "nightEnabled": False, "nightTemperature": None, "nightToggleCount": 0,
        "nightReadCount": 0,
        "kbdDevice": "platform::kbd_backlight", "kbdMax": 3, "kbdValue": 0,
        "kbdDelay": 0.15, "kbdReadDelay": 0, "kbdFail": False,
        "kbdValues": [], "kbdReadCount": 0, "discoveryCount": 0, "events": [],
    }


def update(fn):
    with (root / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / "state.json"
        state = json.loads(path.read_text()) if path.exists() else defaults()
        result = fn(state)
        path.write_text(json.dumps(state))
        return result


if name == "display-fixture":
    if args == ["snapshot"]:
        print(json.dumps(update(lambda state: state)))
    elif len(args) == 2 and args[0] == "configure":
        options = json.loads(args[1])

        def configure(state):
            if options.pop("reset", False):
                state.clear()
                state.update(defaults())
            state.update(options)
            return state

        print(json.dumps(update(configure)))
    else:
        sys.exit(64)
    sys.exit(0)


def accept(state):
    state["events"].append([name, *args])
    if name == "omarchy-monitor-state" and not args:
        return ("static", 0, False, "50\neDP-1\n\ntrue\n\neDP-1\n1\n[]")
    if ((name == "omarchy-battery-status" and args == ["--shell"])
            or (name == "omarchy-powerprofiles-list" and args == ["--active-state"])
            or (name == "upower" and args == ["-e"])):
        return ("static", 0, False, "")
    if name == "omarchy-display-text-size" and len(args) == 1 and args[0].isdigit():
        return ("text", state["textDelay"], state["textFail"], int(args[0]))
    if name == "omarchy-toggle-nightlight" and args == ["--status"]:
        state["nightReadCount"] += 1
        return ("nightRead", state["nightReadDelay"], False,
                {"enabled": state["nightEnabled"], "temperature": state["nightTemperature"]})
    if name == "omarchy-toggle-nightlight" and not args:
        return ("night", state["nightDelay"], state["nightFail"], None)
    if name == "ls" and args == ["/sys/class/leds"]:
        state["discoveryCount"] += 1
        return ("discover", 0, False, state["kbdDevice"])
    if name == "brightnessctl" and args == ["-d", state["kbdDevice"], "-m"]:
        state["kbdReadCount"] += 1
        return ("kbdRead", state["kbdReadDelay"], False,
                f'{state["kbdDevice"]},leds,{state["kbdValue"]},0%,{state["kbdMax"]}')
    if name == "brightnessctl" and len(args) == 4 and args[:3] == ["-sd", state["kbdDevice"], "set"] and args[3].isdigit():
        return ("kbd", state["kbdDelay"], state["kbdFail"], int(args[3]))
    if name == "omarchy-brightness-keyboard" and args == ["off"]:
        return ("kbd", state["kbdDelay"], state["kbdFail"], 0)
    return ("invalid", 0, True, None)


kind, delay, fail, result = update(accept)
time.sleep(delay)
if fail:
    sys.exit(17)
if kind == "text":
    update(lambda state: state["textValues"].append(result))
elif kind == "night":
    def toggle(state):
        state["nightToggleCount"] += 1
        state["nightEnabled"] = not state["nightEnabled"]
        state["nightTemperature"] = 4000 if state["nightEnabled"] else None
    update(toggle)
elif kind == "kbd":
    def set_kbd(state):
        state["kbdValues"].append(result)
        state["kbdValue"] = result
    update(set_kbd)
elif kind == "nightRead":
    print(json.dumps(result))
elif kind in ("kbdRead", "discover", "static"):
    print(result)
else:
    sys.exit(64)
