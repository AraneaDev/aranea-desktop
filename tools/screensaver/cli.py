"""Owner command boundary for catalog reads and explicit preference mutations."""

import json
import os
import sys
from pathlib import Path

# Support the Bash launcher's direct file execution as well as package imports.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.screensaver.catalog import load_catalog, validate_selection
from tools.screensaver.preferences import (
    config_directory,
    configure_preferences,
    read_preferences,
)
from tools.screensaver.session import (
    preview_scene,
    session_status,
    start_session,
    stop_session,
)


def read_idle(config_home: Path | None = None) -> dict:
    """Read actual valid Omarchy shell timing; unknown or invalid values remain null."""
    defaults = {"screensaverSeconds": 150, "lockSeconds": 300}
    unknown = {"screensaverSeconds": None, "lockSeconds": None}
    try:
        shell = json.loads(
            (config_directory(config_home) / "omarchy/shell.json").read_text()
        )
    except FileNotFoundError:
        return defaults
    except (OSError, ValueError):
        return unknown
    if not isinstance(shell, dict) or not isinstance(shell.get("idle", {}), dict):
        return unknown
    idle = shell.get("idle", {})
    timing = dict(unknown)
    for key, public in (("screensaver", "screensaverSeconds"), ("lock", "lockSeconds")):
        value = idle.get(key, defaults[public])
        if type(value) is int and value >= 0:
            timing[public] = value
    return timing


def snapshot(repo_root: Path, config_home: Path | None = None) -> dict:
    """Return read-only preferences, timing and owned-session state."""
    state = {
        "availability": "unavailable",
        "catalogAvailable": False,
        "selectedId": None,
        "mode": None,
        "choices": [],
        "integration": {"installed": False, "reachable": False},
        "idle": read_idle(config_home),
        "session": session_status(),
        "error": None,
    }
    try:
        catalog = load_catalog(repo_root)
        state["catalogAvailable"] = True
        state["choices"] = [scene.projection() for scene in catalog]
        prefs = read_preferences(config_home)
        state["selectedId"] = prefs["selectedId"]
        state["mode"] = prefs["mode"]
        validate_selection(catalog, prefs)
        state["availability"] = "available"
    except (OSError, ValueError, TypeError) as error:
        state["error"] = str(error)
    return state


def main(argv: list[str] | None = None) -> int:
    """Print one JSON result on owner routes; send diagnostics to stderr on errors."""
    args = list(sys.argv[1:] if argv is None else argv)
    repo = Path(__file__).resolve().parents[2]
    if len(args) == 3 and args[0] == "_preview":
        descriptor = int(args[2])
        acknowledged = False

        def accept(value):
            nonlocal acknowledged
            os.write(descriptor, json.dumps(value).encode() + b"\n")
            os.close(descriptor)
            acknowledged = True

        try:
            start_session(args[1], preview=True, accepted=accept)
            return 0
        except (OSError, ValueError, TypeError) as error:
            if not acknowledged:
                accept({"accepted": False, "error": str(error)})
            return 1
    try:
        if args in (["start"], ["start", "force"]):
            start_session(force=len(args) == 2)
            return 0
        if len(args) == 3 and args[0] == "preview-scene" and args[-1] == "--json":
            result = preview_scene(args[1])
            print(json.dumps(result, separators=(",", ":")))
            return 0
        if args == ["stop", "--json"]:
            stop_session()
            state = snapshot(repo)
        elif args in (["list", "--json"], ["status", "--json"]):
            state = snapshot(repo)
        elif len(args) == 4 and args[0] == "configure" and args[-1] == "--json":
            configure_preferences(None, args[1], args[2], load_catalog(repo))
            state = snapshot(repo)
        else:
            raise ValueError(
                "Usage: aranea-screensaver list|status --json | configure ID single|shuffle --json | start [force] | preview-scene ID --json | stop --json"
            )
    except (OSError, ValueError, TypeError) as error:
        state = snapshot(repo)
        state["error"] = str(error)
    print(json.dumps(state, separators=(",", ":")))
    if state["error"]:
        print(state["error"], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
