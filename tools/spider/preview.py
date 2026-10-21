#!/usr/bin/env python3
"""Serve only the local spider assets and own one isolated preview browser.

Usage: python3 tools/spider/preview.py [--serve-only] [--browser PATH]
"""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import mimetypes
from pathlib import Path
import secrets
import shutil
import signal
import subprocess
import tempfile
import threading
from urllib.parse import unquote, urlsplit

ASSETS = Path(__file__).resolve().parents[2] / "branding/3d"


def asset_path(url):
    """Map a request to a regular, non-symlinked public scene file only."""
    raw = unquote(urlsplit(url).path)
    if raw == "/live/":
        raw += "index.html"
    if raw == "/aranea-spider.glb":
        return ASSETS / "aranea-spider.glb"
    if not raw.startswith("/live/") or "\\" in raw or "\x00" in raw:
        return None
    relative = Path(raw.lstrip("/"))
    if ".." in relative.parts:
        return None
    path = ASSETS / relative
    if (
        not path.resolve().is_relative_to((ASSETS / "live").resolve())
        or path.is_symlink()
    ):
        return None
    return path if path.is_file() else None


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

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            path = asset_path(self.path)
            if path is None:
                self.send_error(404)
                return
            data = path.read_bytes()
            self.send_response(200)
            mime = (
                "text/javascript"
                if path.suffix in (".js", ".mjs")
                else mimetypes.guess_type(path)[0] or "application/octet-stream"
            )
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header(
                "Content-Security-Policy",
                "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' blob: data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
            )
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            if (
                self.path != "/__dismiss"
                or self.headers.get("X-Aranea-Session") != token
            ):
                self.send_error(403)
                return
            self.send_response(204)
            self.end_headers()
            stop.set()

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    url = f"http://127.0.0.1:{server.server_port}/live/?session={token}"
    print(url, flush=True)
    child = None
    returncode = 0
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stop.set())
    try:
        if args.serve_only:
            stop.wait()
            return
        with tempfile.TemporaryDirectory(prefix="aranea-spider-browser-") as profile:
            try:
                child = subprocess.Popen(
                    [
                        browser,
                        f"--user-data-dir={profile}",
                        f"--app={url}",
                        "--start-fullscreen",
                        "--no-first-run",
                        "--no-default-browser-check",
                        "--disable-background-networking",
                        "--disable-component-update",
                        "--disable-sync",
                        "--disable-extensions",
                        "--disable-features=MediaRouter",
                        "--class=org.aranea.spider-preview",
                    ],
                    start_new_session=True,
                )
                while child.poll() is None and not stop.wait(0.15):
                    pass
                if not stop.is_set() and child.returncode not in (0, None):
                    returncode = 1
            finally:
                if child is not None and child.poll() is None:
                    import os

                    os.killpg(child.pid, signal.SIGTERM)
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=2)
    return returncode


if __name__ == "__main__":
    raise SystemExit(main())
