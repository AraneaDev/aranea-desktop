"""Validate trusted scene definitions without executing catalog-controlled text."""

import json
import re
import shutil
from dataclasses import dataclass
from pathlib import Path

ID_PATTERN = re.compile(r"[a-z][a-z0-9-]{0,63}\Z")


class CatalogError(ValueError):
    """An invalid catalog or scene selection, suitable for an owner diagnostic."""


def validate_id(scene_id: str) -> str:
    """Return a bounded scene identifier or reject it before storage or lookup."""
    if not isinstance(scene_id, str) or not ID_PATTERN.fullmatch(scene_id):
        raise CatalogError(
            "Scene ID must start with a letter and contain at most 64 lowercase letters, digits, or hyphens"
        )
    return scene_id


@dataclass(frozen=True)
class Scene:
    """A validated scene with normalized absolute assets and a public projection."""

    id: str
    label: str
    description: str
    renderer: str
    thumbnail: Path | None
    available: bool
    reason: str | None
    shuffle_eligible: bool
    root: Path | None = None
    entry: Path | None = None
    public_paths: tuple[Path, ...] = ()
    asset: Path | None = None

    def projection(self) -> dict:
        """Expose display data, never renderer internals or executable commands."""
        return {
            "id": self.id,
            "label": self.label,
            "description": self.description,
            "renderer": self.renderer,
            "thumbnail": str(self.thumbnail) if self.thumbnail else None,
            "available": self.available,
            "reason": self.reason,
            "shuffleEligible": self.shuffle_eligible,
        }


def _text(value, field: str, limit: int) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise CatalogError(
            f"Catalog {field} must be nonempty plain text of at most {limit} characters"
        )
    if any(ord(char) < 32 or ord(char) == 127 or char in "<>" for char in value):
        raise CatalogError(
            f"Catalog {field} must be plain text without markup or control characters"
        )
    return value


def _path(repo: Path, value) -> Path:
    if (
        not isinstance(value, str)
        or not value
        or len(value) > 1024
        or "\\" in value
        or "\x00" in value
    ):
        raise CatalogError(
            "Catalog asset paths must be bounded repository-relative paths"
        )
    relative = Path(value)
    if (
        not relative.parts
        or relative.is_absolute()
        or relative.parts[0] != "branding"
        or ".." in relative.parts
    ):
        raise CatalogError(f"Catalog path must stay inside branding/: {value}")
    try:
        resolved = (repo / relative).resolve()
    except (OSError, RuntimeError) as error:
        raise CatalogError(f"Cannot resolve catalog path {value}: {error}") from error
    if not resolved.is_relative_to(repo / "branding"):
        raise CatalogError(f"Catalog symlink escapes branding/: {value}")
    return resolved


def _missing_file(path: Path) -> bool:
    return not path.is_file() or path.stat().st_size == 0


def load_catalog(repo_root: Path) -> list[Scene]:
    """Load all scenes; absent assets/dependencies disable only their own entry."""
    repo = Path(repo_root).resolve()
    try:
        source = json.loads((repo / "branding/screensavers/catalog.json").read_text())
    except (OSError, ValueError) as error:
        raise CatalogError(f"Cannot read screensaver catalog: {error}") from error
    if (
        not isinstance(source, dict)
        or set(source) != {"version", "scenes"}
        or type(source["version"]) is not int
        or source["version"] != 1
    ):
        raise CatalogError("Screensaver catalog requires version 1 and a scenes array")
    if not isinstance(source["scenes"], list) or not 1 <= len(source["scenes"]) <= 128:
        raise CatalogError("Screensaver catalog must contain 1 to 128 scenes")
    scenes = []
    ids = set()
    for raw in source["scenes"]:
        if not isinstance(raw, dict):
            raise CatalogError("Each catalog scene must be an object")
        scene_id = validate_id(raw.get("id"))
        if scene_id in ids:
            raise CatalogError(f"Duplicate scene ID: {scene_id}")
        ids.add(scene_id)
        renderer = raw.get("renderer")
        extra = {
            "web": {"root", "entry", "publicPaths"},
            "video": {"asset"},
            "stock": set(),
        }
        if not isinstance(renderer, str) or renderer not in extra:
            raise CatalogError(f"Unsupported renderer for {scene_id}")
        expected = {"id", "label", "description", "renderer", "thumbnail"} | extra[
            renderer
        ]
        if set(raw) != expected:
            raise CatalogError(f"Unexpected or missing catalog fields for {scene_id}")
        label = _text(raw["label"], "label", 128)
        description = _text(raw["description"], "description", 512)
        thumbnail = (
            _path(repo, raw["thumbnail"]) if raw["thumbnail"] is not None else None
        )
        if renderer != "stock" and thumbnail is None:
            raise CatalogError(f"Scene {scene_id} requires a thumbnail")
        if renderer == "stock" and thumbnail is not None:
            raise CatalogError("Stock scenes use terminal text and no thumbnail")
        root = entry = asset = None
        public_paths = ()
        required = [thumbnail] if thumbnail else []
        missing = []
        if renderer == "web":
            root = _path(repo, raw["root"])
            entry = _path(repo, raw["entry"])
            if (
                not isinstance(raw["publicPaths"], list)
                or not 1 <= len(raw["publicPaths"]) <= 32
            ):
                raise CatalogError(
                    f"Scene {scene_id} requires a bounded publicPaths array"
                )
            public_paths = tuple(_path(repo, item) for item in raw["publicPaths"])
            if not entry.is_relative_to(root) or any(
                not path.is_relative_to(root) for path in public_paths
            ):
                raise CatalogError(
                    f"Web assets for {scene_id} must stay inside its root"
                )
            if not any(
                entry == path or entry.is_relative_to(path) for path in public_paths
            ):
                raise CatalogError(
                    f"Web entry for {scene_id} must be allowed by publicPaths"
                )
            for path in public_paths:
                if path.is_dir():
                    for child in path.rglob("*"):
                        _path(repo, str(child.relative_to(repo)))
                elif _missing_file(path):
                    missing.append(str(path))
            if not root.is_dir():
                missing.append(str(root))
            required.append(entry)
        elif renderer == "video":
            asset = _path(repo, raw["asset"])
            required.append(asset)
        missing.extend(str(path) for path in required if _missing_file(path))
        dependency = {"web": "chromium", "video": "mpv"}.get(renderer)
        if dependency and not shutil.which(dependency):
            missing.append(f"{dependency} executable (install {dependency})")
        reason = (
            "Missing required screensaver resources: " + ", ".join(missing)
            if missing
            else None
        )
        scenes.append(
            Scene(
                scene_id,
                label,
                description,
                renderer,
                thumbnail,
                not missing,
                reason,
                renderer != "stock",
                root,
                entry,
                public_paths,
                asset,
            )
        )
    return scenes


def validate_selection(catalog: list[Scene], prefs: dict) -> Scene:
    """Validate selection semantics without choosing or mutating shuffle state."""
    scene_id = validate_id(prefs.get("selectedId"))
    selected = next((scene for scene in catalog if scene.id == scene_id), None)
    if selected is None:
        raise CatalogError(
            f"Unknown screensaver ID: {scene_id}; choose an entry from the catalog"
        )
    mode = prefs.get("mode")
    if mode == "single":
        if not selected.available:
            raise CatalogError(
                f"Screensaver {scene_id} is unavailable: {selected.reason}"
            )
    elif mode == "shuffle":
        if not any(scene.available and scene.shuffle_eligible for scene in catalog):
            raise CatalogError(
                "Shuffle requires at least one available Aranea screensaver"
            )
    else:
        raise CatalogError("Screensaver mode must be single or shuffle")
    return selected


def choose_scene(catalog: list[Scene], prefs: dict, last_id: str | None, rng) -> Scene:
    """Choose once per session; exclude stock and avoid the previous scene if possible."""
    selected = validate_selection(catalog, prefs)
    if prefs["mode"] == "single":
        return selected
    pool = [scene for scene in catalog if scene.available and scene.shuffle_eligible]
    alternatives = [scene for scene in pool if scene.id != last_id]
    return rng.choice(alternatives or pool)
