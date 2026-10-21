"""Session ownership, monitor placement and readiness through real child processes."""

import importlib
import json
import multiprocessing
import os
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))


def wait_for(check, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.025)
    raise AssertionError("condition did not become true")


class Compositor:
    """Only native compositor I/O is replaced; supervisor/children/HTTP stay real."""

    def __init__(self, root):
        self.root = root
        self.focus = "DP-1"

    def read(self, name):
        return json.loads((self.root / name).read_text())

    def locked(self):
        delay = self.root / "lock-delay"
        if delay.exists():
            seconds = float(delay.read_text())
            delay.unlink()  # Delay this preflight observation, not every later poll.
            time.sleep(seconds)
        value = self.read("locked")
        if type(value) is not bool:
            raise ValueError("Lock state unavailable")
        if value:
            (self.root / "lock-observed").write_text(str(time.monotonic()))
        return value

    def monitors(self):
        return self.read("monitors")

    def active_window(self):
        return {"address": "0xface", "monitor": 1}

    def subscribe(self):
        (self.root / "subscribed").touch()

    def events(self):
        path = self.root / "events"
        if path.exists():
            events = json.loads(path.read_text())
            path.unlink()
            return events
        return []

    def clients(self):
        result = [
            {"address": "0xface", "monitor": 1, "class": "terminal", "mapped": True}
        ]
        for file in self.root.glob("child-*"):
            child = json.loads(file.read_text())
            try:
                os.kill(child["pid"], 0)
            except ProcessLookupError:
                continue
            if child.get("mapped", True):
                result.append(child)
        return result

    def dispatch(self, name, value):
        with (self.root / "dispatches").open("a") as stream:
            stream.write(json.dumps([name, value]) + "\n")
        if name == "movetoworkspacesilent":
            workspace, address = value.split(",address:")
            for file in self.root.glob("child-*"):
                child = json.loads(file.read_text())
                if child["address"] == address:
                    child["workspace"] = {"name": workspace}
                    file.write_text(json.dumps(child))
        if name == "focusmonitor":
            self.focus = value
            (self.root / "focus").write_text(value)

    def close(self):
        (self.root / "event-closed").touch()


RENDERER = r"""#!/usr/bin/env python3
import json, os, pathlib, signal, subprocess, sys, time, urllib.parse, urllib.request
root = pathlib.Path(os.environ["FIXTURE_ROOT"])
assert (root / "subscribed").exists()
url = next(x.removeprefix("--app=") for x in sys.argv if x.startswith("--app="))
query = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
screen = query["screen"][0]
behavior = json.loads((root / "behavior").read_text())
if behavior == "slow-map" or (behavior == "second-slow" and screen == "HDMI-A-1"): time.sleep(3)
child = {"pid":os.getpid(),"address":hex(os.getpid()),"class":"org.omarchy.screensaver","mapped":behavior != "no-map","monitor":1 if screen == "DP-1" else 2,"workspace":{"name":"special:screensaver-" + screen},"screen":screen,"url":url}
(root / ("child-"+screen)).write_text(json.dumps(child))
if behavior == "stubborn-removed" and screen == "HDMI-A-1":
    signal.signal(signal.SIGTERM, lambda *_: (root / "removed-term").write_text(str(time.monotonic())))
if behavior == "orphan":
    p = subprocess.Popen([sys.executable,"-c","import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(90)"])
    (root / "descendant").write_text(str(p.pid))
    time.sleep(.1)
    sys.exit(0)
if behavior not in ("no-ready", "no-map", "slow-map"):
    time.sleep(.15)
    req = urllib.request.Request(url.split("/live/")[0]+"/__ready", data=json.dumps({"screenId":screen}).encode(), headers={"X-Aranea-Session":query["session"][0]})
    urllib.request.urlopen(req,timeout=2).close()
while True: time.sleep(.1)
"""


VIDEO_RENDERER = r"""#!/usr/bin/env python3
import json, os, pathlib, signal, socket, sys, time
root = pathlib.Path(os.environ["FIXTURE_ROOT"])
screen = (root / "focus").read_text()
ipc = next(x.removeprefix("--input-ipc-server=") for x in sys.argv if x.startswith("--input-ipc-server="))
child = {"pid":os.getpid(),"address":hex(os.getpid()),"class":"org.omarchy.screensaver","mapped":True,"monitor":1 if screen == "DP-1" else 2,"workspace":{"name":"special:screensaver-" + screen},"screen":screen}
(root / ("child-"+screen)).write_text(json.dumps(child))
signal.signal(signal.SIGUSR1, lambda *_: sys.exit(0))
server = socket.socket(socket.AF_UNIX)
server.bind(ipc)
server.listen()
while True:
    client, _ = server.accept()
    with client:
        stream = client.makefile("rb")
        while line := stream.readline():
            request = json.loads(line)
            value = True if request["command"][1] == "vo-configured" else 1
            client.sendall(json.dumps({"request_id":request["request_id"],"error":"success","data":value}).encode()+b"\n")
"""


def run_session(root, preview, ready_timeout):
    from tools.screensaver import session

    session.READY_TIMEOUT = ready_timeout
    try:
        session.start_session(preview=preview, hyprland=Compositor(Path(root)))
    except (OSError, ValueError) as error:
        (Path(root) / "error").write_text(str(error))


class SessionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert (REPO / "tools/screensaver/session.py").exists(), (
            "session supervisor is missing"
        )
        cls.api = importlib.import_module("tools.screensaver.session")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="ss-", dir="/tmp")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = patch.dict(
            os.environ,
            {
                "HOME": str(self.root / "home"),
                "XDG_RUNTIME_DIR": str(self.root / "run"),
                "XDG_CONFIG_HOME": str(self.root / "config"),
                "XDG_STATE_HOME": str(self.root / "state"),
                "FIXTURE_ROOT": str(self.root),
                "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
            },
        )
        self.env.start()
        self.addCleanup(self.env.stop)
        (self.root / "run").mkdir(mode=0o700)
        (self.root / "bin").mkdir()
        (self.root / "bin/chromium").write_text(RENDERER)
        (self.root / "bin/chromium").chmod(0o755)
        self.write("locked", False)
        self.write("behavior", "normal")
        self.write(
            "monitors",
            [
                {
                    "id": 1,
                    "name": "DP-1",
                    "focused": True,
                    "activeWorkspace": {"id": 2, "name": "2"},
                    "specialWorkspace": {"id": -1, "name": "special:scratch"},
                },
                {
                    "id": 2,
                    "name": "HDMI-A-1",
                    "focused": False,
                    "activeWorkspace": {"id": 3, "name": "3"},
                    "specialWorkspace": {"id": 0, "name": ""},
                },
            ],
        )
        self.guard = Path(os.environ["ARANEA_TEST_SANDBOX"]) / "guard.log"
        self.guard_before = self.guard.read_bytes() if self.guard.exists() else b""
        self.processes = []
        self.addCleanup(self.cleanup)

    def write(self, name, value):
        temporary = self.root / (name + ".tmp")
        temporary.write_text(json.dumps(value))
        temporary.replace(self.root / name)

    def tearDown(self):
        self.assertEqual(
            self.guard.read_bytes() if self.guard.exists() else b"",
            self.guard_before,
            "unexpected external effect reached a guard",
        )

    def cleanup(self):
        self.api.stop_session()
        for process in self.processes:
            process.join(5)
            if process.is_alive():
                process.kill()
                process.join()

    def start(self, preview=False, timeout=20):
        process = multiprocessing.get_context("fork").Process(
            target=run_session, args=(str(self.root), preview, timeout)
        )
        process.start()
        self.processes.append(process)
        return process

    def ready(self):
        return wait_for(lambda: self.api.session_status().get("ready"))

    def assert_closed(self, process):
        process.join(6)
        self.assertFalse(process.is_alive())
        self.assertFalse(self.api.session_status()["running"])
        self.assertEqual(
            list((self.root / "run/aranea-screensaver").glob("session-*")), []
        )
        self.assertFalse((self.root / "run/aranea-screensaver/control.sock").exists())
        for file in self.root.glob("child-*"):
            pid = json.loads(file.read_text())["pid"]
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)

    def event(self, kind, screen="DP-1"):
        import urllib.parse
        import urllib.request

        child = json.loads((self.root / ("child-" + screen)).read_text())
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(child["url"]).query)
        req = urllib.request.Request(
            child["url"].split("/live/")[0] + "/__" + kind,
            data=json.dumps({"screenId": screen}).encode(),
            headers={"X-Aranea-Session": query["session"][0]},
        )
        urllib.request.urlopen(req, timeout=2).close()

    def test_shared_session_readiness_dismissal_and_restoration(self):
        process = self.start()
        self.ready()
        self.assertEqual(len(list(self.root.glob("child-*"))), 2)
        self.assertEqual(
            json.loads((self.root / "state/aranea/screensaver-last.json").read_text())[
                "lastId"
            ],
            "silk-journey",
        )
        self.event("dismiss")
        self.assert_closed(process)
        calls = [
            json.loads(line)
            for line in (self.root / "dispatches").read_text().splitlines()
        ]
        self.assertIn(
            [
                "movetoworkspacesilent",
                "special:scratch,address:"
                + json.loads((self.root / "child-DP-1").read_text())["address"],
            ],
            calls,
        )
        self.assertEqual(calls[-1], ["focuswindow", "address:0xface"])
        self.assertTrue((self.root / "event-closed").exists())

    def test_preview_never_writes_preferences_or_history(self):
        process = self.start(preview=True)
        self.ready()
        self.api.stop_session()
        self.assert_closed(process)
        self.assertFalse((self.root / "config").exists())
        self.assertFalse((self.root / "state").exists())

    def test_duplicate_start_refused_without_replacing_owner(self):
        first = self.start()
        self.ready()
        second = self.start()
        second.join(3)
        self.assertFalse(second.is_alive())
        self.assertIn("busy", (self.root / "error").read_text().lower())
        self.assertTrue(first.is_alive())
        self.assertEqual(len(list(self.root.glob("child-*"))), 2)

    def test_locked_or_unknown_state_refuses_even_for_preview(self):
        for value in (True, None):
            self.write("locked", value)
            process = self.start(preview=True)
            process.join(3)
            self.assertFalse(process.is_alive())
            self.assertFalse(list(self.root.glob("child-*")))
            self.assertIn("lock", (self.root / "error").read_text().lower())

    def test_lock_or_unknown_during_run_ends_all_children(self):
        for value in (True, None):
            self.write("locked", False)
            process = self.start()
            self.ready()
            self.write("locked", value)
            self.assert_closed(process)
            for file in self.root.glob("child-*"):
                file.unlink()

    def test_monitor_removed_preserves_remaining_surface(self):
        process = self.start()
        self.ready()
        self.write("monitors", [Compositor(self.root).monitors()[0]])
        pid = json.loads((self.root / "child-HDMI-A-1").read_text())["pid"]

        def gone():
            try:
                os.kill(pid, 0)
                return False
            except ProcessLookupError:
                return True

        wait_for(gone)
        self.assertTrue(process.is_alive())
        self.assertTrue(self.api.session_status()["ready"])
        self.event("dismiss")
        self.assert_closed(process)

    def test_removed_stubborn_renderer_does_not_delay_lock_observation(self):
        self.write("behavior", "stubborn-removed")
        process = self.start()
        self.ready()
        survivor = json.loads((self.root / "child-DP-1").read_text())["pid"]
        removed = json.loads((self.root / "child-HDMI-A-1").read_text())["pid"]
        self.write("monitors", [Compositor(self.root).monitors()[0]])
        wait_for(lambda: (self.root / "removed-term").exists())
        # The removed real child received TERM but ignores it. A surviving
        # surface is still running when the lock changes during its grace.
        os.kill(removed, 0)
        os.kill(survivor, 0)
        changed = time.monotonic()
        self.write("locked", True)
        wait_for(lambda: (self.root / "lock-observed").exists(), timeout=2)
        observed = float((self.root / "lock-observed").read_text())
        self.assertLess(observed - changed, 0.9)
        self.assert_closed(process)
        self.assertIn("locked", (self.root / "error").read_text().lower())

    def test_failure_exit_and_sigterm_cleanup(self):
        for action in ("failed", "exit", "signal"):
            process = self.start()
            self.ready()
            if action == "failed":
                self.event("failed")
            elif action == "exit":
                os.kill(
                    json.loads((self.root / "child-DP-1").read_text())["pid"],
                    signal.SIGTERM,
                )
            else:
                process.terminate()
            self.assert_closed(process)
            for file in self.root.glob("child-*"):
                file.unlink()

    def test_owned_close_event_ends_session_even_with_browser_alive(self):
        process = self.start()
        self.ready()
        address = json.loads((self.root / "child-DP-1").read_text())["address"]
        self.write("events", ["closewindow>>" + address.removeprefix("0x")])
        self.assert_closed(process)

    def test_orphan_descendant_is_terminated(self):
        self.write("behavior", "orphan")
        process = self.start()
        wait_for(lambda: (self.root / "descendant").exists())
        pid = int((self.root / "descendant").read_text())
        self.assert_closed(process)
        status = Path(f"/proc/{pid}/stat")
        self.assertTrue(not status.exists() or status.read_text().split()[2] == "Z")

    def test_owner_cli_routes_and_invalid_preview(self):
        self.native_boundary()
        result = subprocess.run(
            [
                sys.executable,
                str(REPO / "tools/screensaver/cli.py"),
                "preview-scene",
                "unknown",
                "--json",
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unknown", json.loads(result.stdout)["error"])
        result = subprocess.run(
            [sys.executable, str(REPO / "tools/screensaver/cli.py"), "stop", "--json"],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def native_boundary(self):
        command = (
            "#!/usr/bin/env python3\n"
            + "import importlib.util, json, os, pathlib, sys\n"
            + f"spec=importlib.util.spec_from_file_location('fixture', {str(Path(__file__).resolve())!r})\n"
            + "module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)\nroot=pathlib.Path(os.environ['FIXTURE_ROOT']);compositor=module.Compositor(root)\n"
            + "name=pathlib.Path(sys.argv[0]).name\nif name == 'omarchy-shell':\n print(json.dumps(compositor.read('locked')))\nelif sys.argv[1] == 'monitors': print(json.dumps(compositor.monitors()))\nelif sys.argv[1] == 'clients': print(json.dumps(compositor.clients()))\nelif sys.argv[1] == 'activewindow': print(json.dumps(compositor.active_window()))\nelif sys.argv[1] == 'dispatch': compositor.dispatch(sys.argv[2], sys.argv[3])\nelse: sys.exit(19)\n"
        )
        for name in ("hyprctl", "omarchy-shell"):
            path = self.root / "bin" / name
            path.write_text(command)
            path.chmod(0o755)
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "fixture"
        self.addCleanup(os.environ.pop, "HYPRLAND_INSTANCE_SIGNATURE", None)
        path = self.root / "run/hypr/fixture/.socket2.sock"
        path.parent.mkdir(parents=True)
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(path))
        server.listen()
        server.settimeout(0.1)
        stop = threading.Event()

        def serve():
            while not stop.is_set():
                try:
                    client, _ = server.accept()
                except TimeoutError:
                    continue
                with client:
                    (self.root / "subscribed").touch()
                    stop.wait(10)

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()

        def close():
            stop.set()
            thread.join(2)
            server.close()

        self.addCleanup(close)

    def test_detached_preview_accepts_before_ready_and_reports_live_state(self):
        self.native_boundary()
        self.write("behavior", "no-ready")
        before = time.monotonic()
        result = subprocess.run(
            [
                sys.executable,
                str(REPO / "tools/screensaver/cli.py"),
                "preview-scene",
                "silk-journey",
                "--json",
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(time.monotonic() - before, 3)
        acknowledgement = json.loads(result.stdout)
        self.assertTrue(acknowledgement["accepted"])
        self.assertIsInstance(acknowledgement["sessionId"], str)
        status = self.api.session_status()
        self.assertTrue(status["running"])
        self.assertFalse(status["ready"])
        self.assertEqual(status["sessionId"], acknowledgement["sessionId"])
        wait_for(lambda: len(list(self.root.glob("child-*"))) == 2)
        self.api.stop_session()
        wait_for(lambda: not self.api.session_status()["running"])
        self.assertFalse((self.root / "state").exists())
        self.assertFalse((self.root / "run/aranea-screensaver/control.sock").exists())

    def test_stock_window_blocks_custom_ownership(self):
        with patch.object(
            Compositor,
            "clients",
            return_value=[
                {"class": "org.omarchy.screensaver", "mapped": True, "pid": os.getpid()}
            ],
        ):
            process = self.start()
            process.join(3)
            self.assertFalse(process.is_alive())
            self.assertIn("busy", (self.root / "error").read_text().lower())
            self.assertFalse(list(self.root.glob("child-*")))

    def test_shuffle_chooses_once_and_persists_only_after_readiness(self):
        config = self.root / "config/aranea/screensaver.json"
        config.parent.mkdir(parents=True)
        config.write_text('{"version":1,"selectedId":"silk-chamber","mode":"shuffle"}')
        history = self.root / "state/aranea/screensaver-last.json"
        history.parent.mkdir(parents=True)
        history.write_text('{"version":1,"lastId":"silk-chamber"}')
        self.write("behavior", "no-ready")
        process = self.start()
        wait_for(lambda: len(list(self.root.glob("child-*"))) == 2)
        self.assertEqual(json.loads(history.read_text())["lastId"], "silk-chamber")
        self.event("ready", "DP-1")
        time.sleep(0.1)
        self.assertFalse(self.api.session_status()["ready"])
        self.assertEqual(json.loads(history.read_text())["lastId"], "silk-chamber")
        self.event("ready", "HDMI-A-1")
        self.ready()
        self.assertEqual(json.loads(history.read_text())["lastId"], "silk-journey")
        self.assertEqual(json.loads(config.read_text())["selectedId"], "silk-chamber")
        self.event("dismiss")
        self.assert_closed(process)

    def test_preflight_availability_only_delegates_to_fixed_stock_launcher(self):
        stock = self.root / "stock"
        stock.write_text('#!/bin/sh\ntouch "$FIXTURE_ROOT/stock-called"\n')
        stock.chmod(0o755)
        with patch.object(self.api, "STOCK_LAUNCHER", str(stock)):
            # Remove the catalog's supported binary without exposing the real one.
            with patch("tools.screensaver.catalog.shutil.which", return_value=None):
                process = self.start()
                process.join(3)
                self.assertFalse(process.is_alive())
                self.assertTrue((self.root / "stock-called").exists())
                (self.root / "stock-called").unlink()
            self.write("locked", None)
            process = self.start()
            process.join(3)
            self.assertFalse((self.root / "stock-called").exists())
            self.write("locked", False)
            self.write("behavior", "no-ready")
            process = self.start(timeout=0.5)
            self.assert_closed(process)
            self.assertFalse((self.root / "stock-called").exists())

    def test_screensaver_off_refuses_automatic_but_allows_preview(self):
        toggle = self.root / "home/.local/state/omarchy/toggles/screensaver-off"
        toggle.parent.mkdir(parents=True)
        toggle.touch()
        process = self.start()
        process.join(3)
        self.assertIn("disabled", (self.root / "error").read_text().lower())
        self.assertFalse(list(self.root.glob("child-*")))
        process = self.start(preview=True)
        self.ready()
        self.api.stop_session()
        self.assert_closed(process)

    def test_adapter_bounds_unresponsive_lock_command(self):
        from tools.screensaver.hyprland import Hyprland

        executable = self.root / "bin/omarchy-shell"
        executable.write_text("#!/usr/bin/env python3\nimport time\ntime.sleep(4)\n")
        executable.chmod(0o755)
        before = time.monotonic()
        with self.assertRaisesRegex(ValueError, "timed out"):
            Hyprland().locked()
        self.assertLess(time.monotonic() - before, 0.7)

    def test_first_surface_input_during_later_mapping_dismisses_promptly(self):
        self.write("behavior", "second-slow")
        process = self.start()
        wait_for(lambda: (self.root / "child-DP-1").exists())
        before = time.monotonic()
        self.event("dismiss")
        self.assert_closed(process)
        self.assertLess(time.monotonic() - before, 1.5)
        self.assertFalse((self.root / "state").exists())

    def test_placement_readback_must_match_saved_special_workspace(self):
        original = Compositor.dispatch

        def ignore_move(compositor, name, value):
            if name != "movetoworkspacesilent":
                original(compositor, name, value)

        with patch.object(Compositor, "dispatch", ignore_move):
            process = self.start()
            process.join(3)
            self.assertFalse(process.is_alive())
            self.assertIn("workspace", (self.root / "error").read_text().lower())

    def test_video_first_frame_readiness_and_input_close_share_lifecycle(self):
        mpv = self.root / "bin/mpv"
        mpv.write_text(VIDEO_RENDERER)
        mpv.chmod(0o755)
        config = self.root / "config/aranea/screensaver.json"
        config.parent.mkdir(parents=True)
        config.write_text('{"version":1,"selectedId":"silk-chamber","mode":"single"}')
        process = self.start()
        self.ready()
        self.assertEqual(self.api.session_status()["sceneId"], "silk-chamber")
        self.assertEqual(len(list(self.root.glob("child-*"))), 2)
        os.kill(
            json.loads((self.root / "child-DP-1").read_text())["pid"], signal.SIGUSR1
        )
        self.assert_closed(process)

    def test_stock_rechecks_lock_after_availability_preflight(self):
        stock = self.root / "stock"
        stock.write_text('#!/bin/sh\ntouch "$FIXTURE_ROOT/stock-called"\n')
        stock.chmod(0o755)
        with (
            patch.object(self.api, "STOCK_LAUNCHER", str(stock)),
            patch("tools.screensaver.catalog.shutil.which", return_value=None),
            patch.object(Compositor, "locked", side_effect=[False, True]),
        ):
            process = self.start()
            process.join(3)
            self.assertFalse((self.root / "stock-called").exists())
            self.assertIn("locked", (self.root / "error").read_text().lower())

    def test_existing_special_workspace_with_spaces_is_preserved(self):
        monitors = Compositor(self.root).monitors()
        monitors[0]["specialWorkspace"]["name"] = "special:work notes"
        self.write("monitors", monitors)
        process = self.start()
        self.ready()
        self.event("dismiss")
        self.assert_closed(process)
        calls = [
            json.loads(line)
            for line in (self.root / "dispatches").read_text().splitlines()
        ]
        self.assertNotIn(["togglespecialworkspace", "work notes"], calls)
        self.assertEqual(
            json.loads((self.root / "child-DP-1").read_text())["workspace"]["name"],
            "special:work notes",
        )

    def test_first_map_deadline_is_inside_upstream_grace(self):
        self.write("behavior", "slow-map")
        before = time.monotonic()
        process = self.start()
        self.assert_closed(process)
        self.assertLess(time.monotonic() - before, 3.0)
        self.assertIn("mapping", (self.root / "error").read_text())
        self.assertFalse((self.root / "state").exists())

    def test_first_map_budget_includes_preflight_observation(self):
        (self.root / "lock-delay").write_text("0.4")
        self.write("behavior", "slow-map")
        before = time.monotonic()
        process = self.start()
        self.assert_closed(process)
        self.assertLess(time.monotonic() - before, 3.0)

    def test_renderer_ready_timeout_is_separate_from_mapping(self):
        self.write("behavior", "no-ready")
        process = self.start(timeout=0.7)
        wait_for(lambda: len(list(self.root.glob("child-*"))) == 2)
        self.assertFalse(self.api.session_status()["ready"])
        self.assert_closed(process)
        self.assertIn("ready", (self.root / "error").read_text())
        self.assertFalse((self.root / "state").exists())

    def test_status_and_stop_without_owner_are_side_effect_free(self):
        before = sorted(str(p) for p in self.root.rglob("*"))
        with patch(
            "subprocess.Popen", side_effect=AssertionError("read started a process")
        ):
            self.assertFalse(self.api.session_status()["running"])
            self.api.stop_session()
        self.assertEqual(before, sorted(str(p) for p in self.root.rglob("*")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
