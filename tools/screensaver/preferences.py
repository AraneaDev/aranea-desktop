"""Side-effect-free reads and locked atomic writes for Aranea screensavers."""

import fcntl
import json
import os
import tempfile
from pathlib import Path

from .catalog import Scene, validate_id, validate_selection

DEFAULT_PREFERENCES = {"version": 1, "selectedId": "silk-journey", "mode": "single"}


class PreferenceError(ValueError):
    """Persisted preferences need user attention rather than silent replacement."""


def config_directory(config_home: Path | None = None) -> Path:
    """Return the XDG config home; do not create it on read routes."""
    return (
        Path(config_home)
        if config_home is not None
        else Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    )


def state_directory(state_home: Path | None = None) -> Path:
    """Return Aranea state root, honoring its existing override unless explicit."""
    if state_home is not None:
        return Path(state_home) / "aranea"
    override = os.environ.get("ARANEA_STATE_ROOT")
    return (
        Path(override)
        if override
        else Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
        / "aranea"
    )


def _read_object(path: Path) -> dict | None:
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as error:
        raise PreferenceError(
            f"Cannot read {path}; repair or remove this file: {error}"
        ) from error
    if not isinstance(value, dict):
        raise PreferenceError(
            f"Expected a JSON object in {path}; repair or remove this file"
        )
    return value


def read_preferences(config_home: Path | None = None) -> dict:
    """Return version-1 preferences or defaults, creating no files or directories."""
    path = config_directory(config_home) / "aranea/screensaver.json"
    value = _read_object(path)
    if value is None:
        return dict(DEFAULT_PREFERENCES)
    if (
        set(value) != {"version", "selectedId", "mode"}
        or type(value.get("version")) is not int
        or value["version"] != 1
    ):
        raise PreferenceError(
            f"Unsupported screensaver preferences in {path}; expected version 1 with selectedId and mode"
        )
    try:
        validate_id(value["selectedId"])
    except ValueError as error:
        raise PreferenceError(f"Invalid selectedId in {path}: {error}") from error
    if value["mode"] not in ("single", "shuffle"):
        raise PreferenceError(f"Invalid mode in {path}; use single or shuffle")
    return value


def _atomic_write(path: Path, value: dict) -> None:
    descriptor, name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def configure_preferences(
    config_home: Path | None, scene_id: str, mode: str, catalog: list[Scene]
) -> dict:
    """Validate then save preferences under a stable adjacent flock; retain malformed files."""
    value = {"version": 1, "selectedId": scene_id, "mode": mode}
    validate_selection(catalog, value)
    path = config_directory(config_home) / "aranea/screensaver.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    with (path.parent / "screensaver.json.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        read_preferences(config_home)
        _atomic_write(path, value)
    return value


def read_last_scene(state_home: Path | None = None) -> str | None:
    """Read the last automatic scene from Aranea state without creating storage."""
    path = state_directory(state_home) / "screensaver-last.json"
    value = _read_object(path)
    if value is None:
        return None
    if (
        set(value) != {"version", "lastId"}
        or type(value.get("version")) is not int
        or value["version"] != 1
    ):
        raise PreferenceError(
            f"Unsupported screensaver state in {path}; expected version 1 with lastId"
        )
    return validate_id(value["lastId"])


def write_last_scene(state_home: Path | None, scene_id: str) -> None:
    """Atomically record a successful automatic scene; explicit home is XDG state home."""
    validate_id(scene_id)
    path = state_directory(state_home) / "screensaver-last.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    _atomic_write(path, {"version": 1, "lastId": scene_id})
