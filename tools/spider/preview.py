"""Serve only the local spider assets and own one isolated preview browser.

Usage: python3 tools/spider/preview.py [--serve-only] [--browser PATH]
"""

import argparse
import secrets
import shutil
import signal
import sys
import tempfile
import threading
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.screensaver.catalog import Scene
from tools.screensaver.http_server import SceneServer
from tools.screensaver.http_server import asset_path as scene_asset_path
from tools.screensaver.renderers import launch_web, terminate_group

ASSETS = Path(__file__).resolve().parents[2] / "branding/3d"


def preview_scene():
    """Keep the legacy entry and allowlist independent of catalog availability."""
    return Scene(
        "silk-journey",
        "Silk Journey",
        "Live preview",
        "web",
        None,
        True,
        None,
        True,
        ASSETS,
        ASSETS / "live/index.html",
        (ASSETS / "live", ASSETS / "aranea-spider.glb"),
    )


def asset_path(url):
    """Preserve the legacy public asset lookup API."""
    return scene_asset_path(preview_scene(), url)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serve-only", action="store_true")
    parser.add_argument("--browser")
    args = parser.parse_args()
    browser = args.browser or shutil.which("chromium")
    if not args.serve_only and not browser:
        parser.error(
            "Chromium is required for the live preview; use aranea-screensaver video for the rendered loop"
        )
    if not (ASSETS / "aranea-spider.glb").is_file():
        parser.error("the rigged spider model is missing")
    token = secrets.token_urlsafe(24)
    stop = threading.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stop.set())
    returncode = 0
    with SceneServer(preview_scene(), token, ["legacy"], legacy=True) as server:
        url = server.url("legacy")
        print(url, flush=True)

        def dismissed():
            if any(event["kind"] == "dismiss" for event in server.drain_events()):
                stop.set()
            return stop.is_set()

        if args.serve_only:
            while not dismissed() and not stop.wait(0.05):
                pass
            return 0
        with tempfile.TemporaryDirectory(prefix="aranea-spider-browser-") as profile:
            child = launch_web(
                url, profile, "org.aranea.spider-preview", browser=browser
            )
            try:
                while (
                    child.process.poll() is None
                    and not dismissed()
                    and not stop.wait(0.05)
                ):
                    pass
                if not stop.is_set() and child.process.returncode not in (0, None):
                    returncode = 1
            finally:
                terminate_group(child)
    return returncode


if __name__ == "__main__":
    raise SystemExit(main())
