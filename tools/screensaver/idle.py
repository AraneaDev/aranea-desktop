"""Omarchy-owned timing persistence and managed automatic-launch diagnostics."""

import fcntl
import json
import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path

from tools.screensaver.preferences import config_directory

DEFAULTS = {"screensaverSeconds": 150, "lockSeconds": 300}


def omarchy_root() -> Path:
    """Use the established packaged root, never a launcher found through PATH."""
    return Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))


def shell_document(path: Path) -> dict:
    """Reject malformed user data instead of normalizing away unrelated fields."""
    document = json.loads(path.read_text())
    if not isinstance(document, dict) or not isinstance(document.get("idle", {}), dict):
        raise TypeError("Omarchy shell.json and its idle section must be objects")
    return document


def read_idle(config_home: Path | None = None) -> dict:
    """Observe timings and persisted host pauses without creating any paths."""
    timing = dict(DEFAULTS)
    error = None
    try:
        idle = shell_document(config_directory(config_home) / "omarchy/shell.json").get(
            "idle", {}
        )
        for key, public in (
            ("screensaver", "screensaverSeconds"),
            ("lock", "lockSeconds"),
        ):
            value = idle.get(key, DEFAULTS[public])
            timing[public] = (
                value if type(value) is int and 0 <= value <= 86400 else None
            )
            if timing[public] is None:
                error = "Omarchy idle deadlines must be integer seconds from 0 to 86400"
    except FileNotFoundError:
        pass
    except (OSError, ValueError, TypeError) as exception:
        timing = dict.fromkeys(DEFAULTS)
        error = str(exception)
    host = (omarchy_root() / "shell/plugins/services/idle/Service.qml").is_file()
    home = Path.home() / ".local/state/omarchy"
    timing.update(
        stayAwake=(home / "indicators/stay-awake").is_file() if host else None,
        screensaverOff=(home / "toggles/screensaver-off").is_file() if host else None,
        error=error,
    )
    return timing


def configure_idle(
    screensaver: str, lock: str, config_home: Path | None = None
) -> dict:
    """Save only two deadlines under an adjacent lock, then request bounded reload."""
    values = []
    for value in (screensaver, lock):
        if not re.fullmatch(r"[0-9]{1,5}", value) or int(value) > 86400:
            raise ValueError(
                "Use integer seconds from 0 to 86400 (0 disables a deadline)"
            )
        values.append(int(value))
    saver_seconds, lock_seconds = values
    if saver_seconds and lock_seconds and lock_seconds <= saver_seconds:
        raise ValueError("Lock must be later than screensaver when both are enabled")
    given = config_directory(config_home) / "omarchy/shell.json"
    target = given.resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    with Path(str(target) + ".aranea-idle.lock").open("a", encoding="utf-8") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        try:
            document = shell_document(target)
            mode = stat.S_IMODE(target.stat().st_mode)
        except FileNotFoundError:
            document = shell_document(omarchy_root() / "config/omarchy/shell.json")
            mode = 0o600
        document.setdefault("idle", {}).update(
            screensaver=saver_seconds, lock=lock_seconds
        )
        descriptor, temporary = tempfile.mkstemp(
            prefix=".shell.json.aranea.", dir=target.parent
        )
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                os.fchmod(stream.fileno(), mode)
                json.dump(document, stream, indent=2, allow_nan=False)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, target)
        finally:
            Path(temporary).unlink(missing_ok=True)
        error = None
        try:
            result = subprocess.run(
                ["omarchy-shell", "shell", "reloadConfig"],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            if result.returncode:
                error = (
                    result.stderr.strip() or f"reloadConfig exited {result.returncode}"
                )
        except (OSError, subprocess.TimeoutExpired) as exception:
            error = str(exception)
    if error:
        error = "Timing saved but not applied: " + error
    return {"persisted": True, "applied": error is None, "error": error}


def integration_status() -> dict:
    """Require the stable owned shim and report actual bash-login-shell resolution."""
    home = Path.home()
    target = (
        Path(os.environ.get("XDG_BIN_HOME", str(home / ".local/bin")))
        / "omarchy-launch-screensaver"
    )
    source = (
        home
        / ".config/omarchy/themes/aranea/integrations/session/bin/omarchy-launch-screensaver"
    )
    state = Path(
        os.environ.get(
            "ARANEA_STATE_ROOT",
            str(
                Path(os.environ.get("XDG_STATE_HOME", str(home / ".local/state")))
                / "aranea"
            ),
        )
    )
    ledger = Path(os.environ.get("ARANEA_OWNERSHIP_ROOT", str(state))) / "managed-files"
    installed = False
    try:
        installed = (
            target.is_symlink()
            and target.readlink() == source
            and source.is_file()
            and str(target) in ledger.read_text().splitlines()
        )
    except OSError:
        pass
    result = {"installed": installed, "reachable": False}
    if not installed:
        return result
    result.update(path=str(target), resolvedCommand=None, error=None)
    try:
        probe = subprocess.run(
            ["/bin/bash", "-lc", "command -v omarchy-launch-screensaver"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        resolved = probe.stdout.strip()
        result["resolvedCommand"] = resolved or None
        result["reachable"] = probe.returncode == 0 and resolved == str(target)
        if not result["reachable"]:
            result["error"] = (
                "Login shell does not resolve the managed screensaver launcher"
            )
    except (OSError, subprocess.TimeoutExpired) as exception:
        result["error"] = str(exception)
    return result
