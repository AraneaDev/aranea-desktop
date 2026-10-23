"""Private Chromium target events and bounded recovery over owned OS pipes."""

from dataclasses import dataclass
import json
import os
import re
import sys

FRAME_LIMIT = 65536


def identity(value):
    return isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", value)


@dataclass(frozen=True)
class BrowserCrash:
    target_id: str
    status: str
    error_code: int


class BrowserControl:
    """Own both ends until spawn, then retain only the parent's protocol FDs."""

    def __init__(self):
        self._incoming = self._writer = self._reader = self._outgoing = None
        self.closed = False
        self._pending = b""
        self._next_id = 0
        self._requests = {}
        self._pages = set()
        self._discovered = False
        try:
            self._incoming, self._writer = os.pipe()
            self._reader, self._outgoing = os.pipe()
            os.set_blocking(self._reader, False)
            os.set_blocking(self._writer, False)
        except OSError:
            self.close()
            raise

    @property
    def child_fds(self):
        if self._incoming is None or self._outgoing is None:
            raise ValueError("Browser child descriptors unavailable")
        return self._incoming, self._outgoing

    @property
    def connected(self):
        return not self.closed and self._discovered and bool(self._pages)

    def started(self):
        for name in ("_incoming", "_outgoing"):
            fd = getattr(self, name)
            if fd is None:
                raise ValueError("Browser control already started")
            os.close(fd)
            setattr(self, name, None)
        self._send("Target.setDiscoverTargets", {"discover": True})

    def _send(self, method, params, *, target=None, session=None):
        if self.closed:
            raise ValueError("Browser control closed")
        self._next_id += 1
        message = {"id": self._next_id, "method": method, "params": params}
        if session is not None:
            message["sessionId"] = session
        data = json.dumps(message, separators=(",", ":")).encode() + b"\0"
        try:
            if os.write(self._writer, data) != len(data):
                raise ValueError("Incomplete browser control command")
        except OSError as error:
            raise ValueError("Browser control unavailable") from error
        self._requests[self._next_id] = (method, target)

    def reload(self, target_id):
        if target_id not in self._pages:
            raise ValueError("Cannot reload an unknown browser page")
        self._send(
            "Target.attachToTarget",
            {"targetId": target_id, "flatten": True},
            target=target_id,
        )

    def _message(self, message):
        if not isinstance(message, dict):
            raise ValueError("Invalid browser control message")
        if "id" in message:
            request_id = message["id"]
            if type(request_id) is not int:
                raise ValueError("Invalid browser control response")
            request = self._requests.pop(request_id, None)
            if request is None:
                return None
            if "error" in message or not isinstance(message.get("result"), dict):
                raise ValueError("Browser control command failed")
            method, target = request
            if method == "Target.setDiscoverTargets":
                self._discovered = True
            elif method == "Target.attachToTarget":
                session = message["result"].get("sessionId")
                if not identity(session) or target not in self._pages:
                    raise ValueError("Invalid browser recovery session")
                self._send("Page.reload", {}, target=target, session=session)
            return None
        method = message.get("method")
        if method not in (
            "Target.targetCreated",
            "Target.targetDestroyed",
            "Target.targetCrashed",
        ):
            return None
        params = message.get("params")
        if not isinstance(params, dict):
            raise ValueError("Invalid browser target event")
        if method == "Target.targetCreated":
            info = params.get("targetInfo")
            if not isinstance(info, dict) or not identity(info.get("targetId")):
                raise ValueError("Invalid browser target identity")
            if info.get("type") == "page":
                self._pages.add(info["targetId"])
                if len(self._pages) > 64:
                    raise ValueError("Too many browser page targets")
            return None
        target = params.get("targetId")
        if not identity(target):
            raise ValueError("Invalid browser target identity")
        if method == "Target.targetDestroyed":
            self._pages.discard(target)
            return None
        status, code = params.get("status"), params.get("errorCode")
        if (
            not isinstance(status, str)
            or not re.fullmatch(r"[A-Za-z0-9 _-]{1,64}", status)
            or type(code) is not int
            or not -(2**31) <= code < 2**31
        ):
            raise ValueError("Invalid browser crash event")
        return BrowserCrash(target, status, code) if target in self._pages else None

    def poll(self):
        if self.closed:
            raise ValueError("Browser control closed")
        try:
            chunk = os.read(self._reader, FRAME_LIMIT)
        except BlockingIOError:
            return []
        except OSError as error:
            raise ValueError("Browser control unavailable") from error
        if not chunk:
            raise ValueError("Browser control disconnected")
        self._pending += chunk
        crashes = []
        count = 0
        while b"\0" in self._pending:
            raw, self._pending = self._pending.split(b"\0", 1)
            count += 1
            if len(raw) > FRAME_LIMIT or count > 256:
                raise ValueError("Oversized browser control message")
            try:
                message = json.loads(raw)
            except (ValueError, UnicodeError, RecursionError) as error:
                raise ValueError("Invalid browser control JSON") from error
            event = self._message(message)
            if event is not None:
                crashes.append(event)
        if len(self._pending) > FRAME_LIMIT:
            raise ValueError("Oversized browser control message")
        return crashes

    def close(self):
        if self.closed:
            return
        self.closed = True
        for name in ("_incoming", "_writer", "_reader", "_outgoing"):
            fd = getattr(self, name)
            setattr(self, name, None)
            if fd is not None:
                os.close(fd)


def exec_browser(argv):
    """Map Chrome's FD 3/4 in a fresh child, without a threaded preexec_fn."""
    if len(argv) < 3:
        raise ValueError("Browser pipe launcher requires descriptors and a command")
    incoming, outgoing = map(int, argv[:2])
    if min(incoming, outgoing) < 3 or incoming == outgoing:
        raise ValueError("Invalid browser child descriptors")
    saved_incoming, saved_outgoing = os.dup(incoming), os.dup(outgoing)
    os.dup2(saved_incoming, 3, inheritable=True)
    os.dup2(saved_outgoing, 4, inheritable=True)
    # dup2(fd, fd) preserves CLOEXEC; these must also survive that case.
    os.set_inheritable(3, True)
    os.set_inheritable(4, True)
    for fd in {incoming, outgoing, saved_incoming, saved_outgoing} - {3, 4}:
        os.close(fd)
    os.execvp(argv[2], argv[2:])


if __name__ == "__main__":
    exec_browser(sys.argv[1:])
