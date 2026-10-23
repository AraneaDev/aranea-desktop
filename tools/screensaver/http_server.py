"""Bounded loopback assets and authenticated events for one owned scene session."""

import hmac
import json
import mimetypes
import queue
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote, unquote, urlencode, urlsplit

ASSET_LIMIT = 32 * 1024 * 1024
EVENT_LIMIT = 8 * 1024


def asset_path(scene, url):
    """Resolve only regular public assets, without following request-time symlinks."""
    try:
        raw = unquote(urlsplit(url).path, errors="strict")
        if not raw.startswith("/") or "\\" in raw or "\x00" in raw:
            return None
        relative = Path(raw.lstrip("/"))
        if ".." in relative.parts:
            return None
        path = scene.root / relative
        if raw.endswith("/"):
            path /= "index.html"
        resolved = path.resolve()
        if not resolved.is_relative_to(scene.root):
            return None
        if any(
            part.is_symlink()
            for part in [path, *path.parents]
            if part.is_relative_to(scene.root)
        ):
            return None
        if not any(
            resolved == public or (public.is_dir() and resolved.is_relative_to(public))
            for public in scene.public_paths
        ):
            return None
        return resolved if resolved.is_file() else None
    except (ValueError, OSError, RuntimeError):
        return None


class SceneServer:
    """Own a loopback server; legacy mode preserves standalone preview requests."""

    def __init__(self, scene, token, screen_ids, *, legacy=False):
        self.scene = scene
        self.token = token
        self.screen_ids = frozenset(screen_ids)
        if not self.screen_ids or not isinstance(token, str) or not token:
            raise ValueError("Scene server requires a token and screen IDs")
        self.legacy = legacy
        if legacy and len(self.screen_ids) != 1:
            raise ValueError("Legacy preview requires exactly one screen")
        self._events = queue.Queue()
        self._seen = set()
        self._lock = threading.Lock()
        self._server = None
        self._worker = None

    def __enter__(self):
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(0.5)

            def log_message(self, *_):
                pass

            def parse_request(self):
                if len(self.raw_requestline) > 8192:
                    self.requestline = ""
                    self.request_version = "HTTP/1.0"
                    self.command = ""
                    self.send_error(414)
                    return False
                return super().parse_request()

            def do_GET(self):
                path = asset_path(owner.scene, self.path)
                if path is None:
                    self.send_error(404)
                    return
                try:
                    with path.open("rb") as source:
                        if path.stat().st_size > ASSET_LIMIT:
                            self.send_error(413)
                            return
                        data = source.read(ASSET_LIMIT + 1)
                    if len(data) > ASSET_LIMIT:
                        self.send_error(413)
                        return
                except OSError:
                    self.send_error(404)
                    return
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
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            def do_POST(self):
                kind = {
                    "/__ready": "ready",
                    "/__dismiss": "dismiss",
                    "/__failed": "failed",
                }.get(self.path)
                if kind is None or not hmac.compare_digest(
                    self.headers.get("X-Aranea-Session", "").encode("utf-8"),
                    owner.token.encode("utf-8"),
                ):
                    self.send_error(403)
                    return
                lengths = self.headers.get_all("Content-Length", [])
                try:
                    if self.headers.get("Transfer-Encoding") or len(lengths) > 1:
                        raise ValueError
                    length = int(lengths[0]) if lengths else 0
                    if length < 0:
                        raise ValueError
                except ValueError:
                    self.send_error(400)
                    return
                if length > EVENT_LIMIT:
                    self.send_error(413)
                    return
                try:
                    deadline = time.monotonic() + 0.5
                    raw = b""
                    while len(raw) < length:
                        remaining = deadline - time.monotonic()
                        if remaining <= 0:
                            raise TimeoutError
                        self.connection.settimeout(remaining)
                        chunk = self.rfile.read1(length - len(raw))
                        if not chunk:
                            break
                        raw += chunk
                    if len(raw) != length:
                        raise ValueError
                    body = (
                        json.loads(raw)
                        if raw
                        else (
                            {"screenId": next(iter(owner.screen_ids))}
                            if owner.legacy
                            else None
                        )
                    )
                    if not isinstance(body, dict):
                        raise TypeError
                    screen = body.get("screenId")
                    if not isinstance(screen, str) or screen not in owner.screen_ids:
                        self.send_error(403)
                        return
                    message = body.get("message", "")
                    if (
                        not isinstance(message, str)
                        or len(message) > 512
                        or any(ord(char) < 32 for char in message)
                    ):
                        raise ValueError
                except (ValueError, TypeError, UnicodeError):
                    self.send_error(400)
                    return
                except TimeoutError:
                    self.send_error(408)
                    return
                with owner._lock:
                    key = (kind, screen)
                    if key not in owner._seen:
                        owner._seen.add(key)
                        owner._events.put(
                            {
                                "kind": kind,
                                "screenId": screen,
                                "message": message if kind == "failed" else "",
                            }
                        )
                self.send_response(204)
                self.end_headers()

        self._server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self._server.daemon_threads = True
        self._worker = threading.Thread(
            target=self._server.serve_forever,
            kwargs={"poll_interval": 0.05},
            daemon=True,
        )
        self._worker.start()
        return self

    def url(self, screen_id):
        """Preserve the entry's directory so relative imports keep their base URL."""
        if screen_id not in self.screen_ids:
            raise ValueError("Unknown scene screen")
        entry = self.scene.entry.relative_to(self.scene.root).as_posix()
        if entry.endswith("/index.html"):
            entry = entry[: -len("index.html")]
        query = {"session": self.token}
        if not self.legacy:
            query["screen"] = screen_id
        return f"http://127.0.0.1:{self._server.server_port}/{quote(entry)}?{urlencode(query)}"

    def rearm(self, screen_id):
        """Require a fresh ready event when an already-ready owned page reloads."""
        if screen_id not in self.screen_ids:
            raise ValueError("Unknown scene screen")
        with self._lock:
            self._seen.discard(("ready", screen_id))

    def drain_events(self):
        """Return pending bounded, deduplicated renderer events without blocking."""
        events = []
        while True:
            try:
                events.append(self._events.get_nowait())
            except queue.Empty:
                return events

    def shutdown(self):
        """Release the listening socket and finish the server worker."""
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()
            self._worker.join(timeout=2)
            self._server = None

    def __exit__(self, *_):
        self.shutdown()
