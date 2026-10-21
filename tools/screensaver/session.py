"""Single-owner screensaver supervision, private control IPC and grouped cleanup."""

import contextlib
import fcntl
import json
import os
import random
import re
import secrets
import select
import signal
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

from tools.screensaver.catalog import choose_scene, load_catalog, validate_id
from tools.screensaver.http_server import SceneServer
from tools.screensaver.hyprland import APP_ID, Hyprland
from tools.screensaver.preferences import (
    read_last_scene,
    read_preferences,
    write_last_scene,
)
from tools.screensaver.renderers import (
    launch_video,
    launch_web,
    terminate_group,
    video_ready,
)

FIRST_MAP_TIMEOUT = 2.5
READY_TIMEOUT = 20.0
STOCK_LAUNCHER = "/usr/share/omarchy/bin/omarchy-launch-screensaver"
REPO = Path(__file__).resolve().parents[2]
EMPTY = {"running": False, "ready": False, "sceneId": None, "preview": False}


def runtime_directory():
    value = os.environ.get("XDG_RUNTIME_DIR")
    if not value:
        raise ValueError("User runtime directory unavailable")
    return Path(value) / "aranea-screensaver"


def private_directory(path, create=False):
    if create:
        path.mkdir(mode=0o700, exist_ok=True)
    info = path.lstat()
    if (
        not stat.S_ISDIR(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_mode & 0o077
    ):
        raise ValueError("Screensaver runtime directory is not private")


def control_request(action):
    root = runtime_directory()
    private_directory(root)
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(0.5)
        client.connect(str(root / "control.sock"))
        _, uid, _ = struct.unpack(
            "3i", client.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
        )
        if uid != os.getuid():
            raise ValueError("Screensaver control owner mismatch")
        client.sendall(json.dumps({"version": 1, "action": action}).encode() + b"\n")
        response = client.recv(8193)
        if len(response) > 8192:
            raise ValueError("Oversized screensaver status")
        result = json.loads(response)
        if not isinstance(result, dict) or result.get("version") != 1:
            raise ValueError("Invalid screensaver status")
        return result


def session_status():
    """Read existing owned IPC/state without launching processes or creating paths."""
    try:
        return control_request("status")
    except (OSError, ValueError):
        try:
            root = runtime_directory()
            private_directory(root)
            path = root / "last.json"
            if path.is_symlink() or path.stat().st_size > 8192:
                return dict(EMPTY)
            result = json.loads(path.read_text())
            if (
                isinstance(result, dict)
                and result.get("version") == 1
                and result.get("running") is False
            ):
                return result
        except (OSError, ValueError):
            pass
        return dict(EMPTY)


def stop_session():
    """Ask the live owned supervisor to stop; never signal a persisted PID."""
    try:
        return control_request("stop")
    except (
        FileNotFoundError,
        ConnectionRefusedError,
        ConnectionResetError,
        BrokenPipeError,
    ):
        return dict(EMPTY)
    except ValueError:
        return dict(EMPTY)


class Supervisor:
    def __init__(self, scene, preview, root, hyprland, started):
        self.started = started
        self.addresses = {}
        self.scene = scene
        self.root = root
        self.hypr = hyprland
        self.stop = threading.Event()
        self.control_done = threading.Event()
        self.children = {}
        self.expected = {}
        self.ready = set()
        self.server = None
        self.control = None
        self.thread = None
        self.monitors = []
        self.focus = {}
        self.shown = set()
        self.state = dict(
            EMPTY,
            version=1,
            sessionId=secrets.token_hex(16),
            running=True,
            sceneId=scene.id,
            preview=preview,
            error=None,
        )

    def serve_control(self):
        while not self.control_done.is_set():
            try:
                client, _ = self.control.accept()
            except TimeoutError:
                continue
            except OSError:
                break
            with client:
                client.settimeout(0.1)
                try:
                    _, uid, _ = struct.unpack(
                        "3i",
                        client.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12),
                    )
                    request = json.loads(client.recv(1024))
                    if (
                        uid != os.getuid()
                        or not isinstance(request, dict)
                        or request.get("version") != 1
                    ):
                        continue
                    if request.get("action") == "stop":
                        self.stop.set()
                    elif request.get("action") != "status":
                        continue
                    client.sendall(json.dumps(self.state).encode() + b"\n")
                except (OSError, ValueError):
                    continue

    def open_control(self):
        path = self.root / "control.sock"
        path.unlink(missing_ok=True)
        self.control = socket.socket(socket.AF_UNIX)
        self.control.bind(str(path))
        self.control.listen(4)
        self.control.settimeout(0.1)
        self.thread = threading.Thread(target=self.serve_control, daemon=True)
        self.thread.start()

    def observe(self):
        if self.hypr.locked():
            raise ValueError("Session locked")
        current = {(m["name"], m["id"]) for m in self.hypr.monitors()}
        for name, monitor in list(self.expected.items()):
            if (name, monitor["id"]) not in current:
                del self.expected[name]
                self.ready.discard(name)
                child = self.children.get(name)
                if child:
                    terminate_group(child)
        return bool(self.expected)

    def mapped_client(self, owned):
        for client in self.hypr.clients():
            if client.get("class") != APP_ID or not client.get("mapped"):
                continue
            pid = client.get("pid")
            address = client.get("address", "")
            if type(pid) is not int or not re.fullmatch(r"0x[0-9a-fA-F]+", address):
                continue
            try:
                if os.getpgid(pid) == owned.pgid:
                    return client
            except ProcessLookupError:
                continue
        return None

    def restore(self):
        try:
            current = {m["name"]: m for m in self.hypr.monitors()}
            for saved in self.monitors:
                now = current.get(saved["name"])
                if not now or now["id"] != saved["id"]:
                    continue
                special = "special:screensaver-" + saved["name"]
                if (
                    saved["name"] in self.shown
                    and now["specialWorkspace"].get("name") == special
                ):
                    self.hypr.dispatch("focusmonitor", saved["name"])
                    self.hypr.dispatch(
                        "togglespecialworkspace", special.removeprefix("special:")
                    )
            focused = next((m for m in self.monitors if m.get("focused")), None)
            if (
                focused
                and focused["name"] in current
                and current[focused["name"]]["id"] == focused["id"]
            ):
                self.hypr.dispatch("focusmonitor", focused["name"])
                address = self.focus.get("address")
                if address and any(
                    c.get("address") == address and c.get("monitor") == focused["id"]
                    for c in self.hypr.clients()
                ):
                    self.hypr.dispatch("focuswindow", "address:" + address)
        except (OSError, ValueError):
            pass  # A lost compositor must not prevent process and IPC cleanup.

    @contextlib.contextmanager
    def resources(self):
        with tempfile.TemporaryDirectory(prefix="session-", dir=self.root) as temporary:
            try:
                yield Path(temporary)
            finally:
                for child in self.children.values():
                    terminate_group(child)
                if self.server:
                    self.server.shutdown()

    def closed_window(self, events):
        addresses = {
            self.addresses[name].removeprefix("0x")
            for name in self.expected
            if name in self.addresses
        }
        return any(
            event.startswith("closewindow>>")
            and event.split(">>", 1)[1].removeprefix("0x") in addresses
            for event in events
        )

    def renderer_events(self):
        for name, child in self.children.items():
            if name in self.expected and child.process.poll() is not None:
                if child.process.returncode:
                    raise ValueError("Renderer exited with an error")
                return False
        if self.server:
            for event in self.server.drain_events():
                if event["screenId"] not in self.expected:
                    continue
                if event["kind"] == "ready":
                    self.ready.add(event["screenId"])
                elif event["kind"] == "failed":
                    raise ValueError("Renderer failed")
                else:
                    return False
        return True

    def run(self, accepted=None):
        previous = {}
        try:
            for sig in (signal.SIGTERM, signal.SIGINT):
                previous[sig] = signal.signal(sig, lambda *_: self.stop.set())
            self.monitors = self.hypr.monitors()
            if not self.monitors:
                raise ValueError("No active monitors")
            self.expected = {m["name"]: m for m in self.monitors}
            self.focus = self.hypr.active_window()
            self.hypr.subscribe()
            self.open_control()
            if accepted:
                accepted({"accepted": True, "sessionId": self.state["sessionId"]})
            with self.resources() as directory:
                if self.scene.renderer == "web":
                    self.server = SceneServer(
                        self.scene, secrets.token_urlsafe(32), list(self.expected)
                    )
                    self.server.__enter__()
                start = time.monotonic()
                ready_deadline = start + READY_TIMEOUT
                observed = start
                mapped_any = False
                for index, monitor in enumerate(self.monitors):
                    name = monitor["name"]
                    if self.stop.is_set() or not self.observe():
                        return
                    if name not in self.expected:
                        continue
                    if (
                        not mapped_any
                        and time.monotonic() >= self.started + FIRST_MAP_TIMEOUT
                    ):
                        raise ValueError("Renderer mapping deadline exceeded")
                    self.hypr.dispatch("focusmonitor", name)
                    if self.scene.renderer == "web":
                        child = launch_web(
                            self.server.url(name),
                            directory / f"profile-{index}",
                            APP_ID,
                        )
                    else:
                        child = launch_video(
                            self.scene.asset,
                            directory / f"video-{index}.sock",
                            APP_ID,
                            REPO / "branding/3d/preview.lua",
                        )
                    self.children[name] = child
                    deadline = (
                        ready_deadline
                        if mapped_any
                        else self.started + FIRST_MAP_TIMEOUT
                    )
                    client = None
                    while not self.stop.is_set() and time.monotonic() < deadline:
                        events = self.hypr.events()
                        if events or time.monotonic() - observed >= 0.5:
                            observed = time.monotonic()
                            self.observe()
                        if self.closed_window(events) or not self.renderer_events():
                            return
                        if name not in self.expected:
                            break
                        if child.process.poll() is not None:
                            raise ValueError("Renderer exited before mapping")
                        client = self.mapped_client(child)
                        if client:
                            break
                        time.sleep(0.025)
                    if self.stop.is_set():
                        return
                    if name not in self.expected:
                        continue
                    if not client or time.monotonic() >= deadline:
                        raise ValueError("Renderer mapping deadline exceeded")
                    mapped_any = True
                    self.hypr.deadline = None
                    self.addresses[name] = client["address"]
                    workspace = (
                        monitor["specialWorkspace"].get("name")
                        or "special:screensaver-" + name
                    )
                    if (
                        not isinstance(workspace, str)
                        or not workspace.startswith("special:")
                        or not 8 < len(workspace) <= 168
                        or any(
                            ord(char) < 32 or ord(char) == 127 or char == ","
                            for char in workspace
                        )
                    ):
                        raise ValueError("Invalid special workspace identity")
                    self.hypr.dispatch(
                        "movetoworkspacesilent",
                        workspace + ",address:" + client["address"],
                    )
                    placed = self.mapped_client(child)
                    if (
                        not placed
                        or placed.get("monitor") != monitor["id"]
                        or placed.get("workspace", {}).get("name") != workspace
                    ):
                        raise ValueError(
                            "Renderer mapped on unexpected monitor/workspace"
                        )
                    if not monitor["specialWorkspace"].get("name"):
                        self.hypr.dispatch(
                            "togglespecialworkspace", workspace.removeprefix("special:")
                        )
                        self.shown.add(name)
                while not self.stop.is_set() and self.expected:
                    events = self.hypr.events()
                    if events or time.monotonic() - observed >= 0.5:
                        observed = time.monotonic()
                        if not self.observe():
                            break
                    if self.closed_window(events):
                        return
                    if not self.renderer_events():
                        return
                    if not self.server:
                        probe_deadline = time.monotonic() + 0.15
                        for index, monitor in enumerate(self.monitors):
                            if time.monotonic() >= probe_deadline:
                                break
                            name = monitor["name"]
                            if (
                                name in self.expected
                                and name not in self.ready
                                and video_ready(
                                    directory / f"video-{index}.sock", timeout=0.05
                                )
                            ):
                                self.ready.add(name)
                    if not self.state["ready"]:
                        if self.expected.keys() <= self.ready:
                            if not self.state["preview"]:
                                write_last_scene(None, self.scene.id)
                            self.state["ready"] = True
                        elif time.monotonic() >= ready_deadline:
                            raise ValueError("Renderer ready deadline exceeded")
                    time.sleep(0.025)
        except (OSError, ValueError, TypeError) as error:
            self.state["error"] = str(error)
            raise
        finally:
            self.stop.set()
            for child in self.children.values():
                terminate_group(child)
            if self.server:
                self.server.shutdown()
            self.hypr.deadline = None
            self.restore()
            self.hypr.close()
            self.state.update(running=False, ready=False)
            temporary_state = self.root / "last.tmp"
            temporary_state.write_text(json.dumps(self.state))
            temporary_state.replace(self.root / "last.json")
            self.control_done.set()
            if self.control:
                self.control.close()
                (self.root / "control.sock").unlink(missing_ok=True)
            if self.thread:
                self.thread.join(0.5)
            for sig, handler in previous.items():
                signal.signal(sig, handler)


def start_session(
    scene_id=None, preview=False, force=False, *, hyprland=None, accepted=None
):
    """Block until the owned session ends; only preflight availability falls back."""
    started = time.monotonic()
    root = runtime_directory()
    private_directory(root, create=True)
    descriptor = os.open(
        root / "owner.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
    )
    with os.fdopen(descriptor, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("Screensaver busy") from error
        hypr = hyprland or Hyprland()
        hypr.deadline = started + FIRST_MAP_TIMEOUT
        if hypr.locked():
            raise ValueError("Session locked")
        if (
            not (preview or force)
            and (Path.home() / ".local/state/omarchy/toggles/screensaver-off").exists()
        ):
            raise ValueError("Screensaver disabled")
        if any(c.get("class") == APP_ID and c.get("mapped") for c in hypr.clients()):
            raise ValueError("Screensaver busy: existing packaged or unowned surface")
        catalog = load_catalog(REPO)
        prefs = read_preferences()
        if scene_id is not None:
            validate_id(scene_id)
            prefs = {"selectedId": scene_id, "mode": "single"}
        if not any(scene.id == prefs["selectedId"] for scene in catalog):
            raise ValueError("Unknown screensaver selection")
        try:
            last = read_last_scene() if not preview else None
        except ValueError:
            last = None
        try:
            scene = choose_scene(catalog, prefs, last, random)
        except ValueError:
            if preview:
                raise
            scene = next(s for s in catalog if s.renderer == "stock")
        if scene.renderer == "stock":
            if hypr.locked():
                raise ValueError("Session locked")
            if not os.access(STOCK_LAUNCHER, os.X_OK):
                raise ValueError("Packaged screensaver launcher unavailable")
            if accepted:
                accepted({"accepted": True, "sessionId": None, "delegated": "stock"})
            result = subprocess.run(
                [STOCK_LAUNCHER, *(["force"] if preview or force else [])], check=False
            )
            if result.returncode:
                raise ValueError("Packaged screensaver launch failed")
            return
        Supervisor(scene, preview, root, hypr, started).run(accepted)


def preview_scene(scene_id):
    """Detach a supervisor and return bounded acceptance, independently of readiness."""
    validate_id(scene_id)
    reader, writer = os.pipe()
    process = None
    try:
        process = subprocess.Popen(
            [
                sys.executable,
                str(REPO / "tools/screensaver/cli.py"),
                "_preview",
                scene_id,
                str(writer),
            ],
            pass_fds=(writer,),
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.close(writer)
        writer = None
        if not select.select([reader], [], [], 4)[0]:
            process.terminate()
            process.wait(timeout=4)
            raise ValueError("Preview acceptance timed out")
        result = json.loads(os.read(reader, 8192))
        if not result.get("accepted"):
            process.wait(timeout=4)
            raise ValueError(result.get("error", "Preview unavailable"))
        return result
    finally:
        os.close(reader)
        if writer is not None:
            os.close(writer)
