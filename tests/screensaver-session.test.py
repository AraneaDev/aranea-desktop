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

    def refresh_pointer(self, addresses):
        history = self.root / "state/aranea/screensaver-last.json"
        record = {
            "addresses": addresses,
            "history": json.loads(history.read_text()) if history.exists() else None,
        }
        with (self.root / "pointer-refreshes").open("a") as stream:
            stream.write(json.dumps(record) + "\n")
        failure = self.root / "refresh-failure"
        if failure.exists() and len(
            (self.root / "pointer-refreshes").read_text().splitlines()
        ) == int(failure.read_text() or "1"):
            raise ValueError("Pointer refresh unavailable")
        return True

    def close(self):
        (self.root / "event-closed").touch()


RENDERER = r"""#!/usr/bin/env python3
import json, os, pathlib, signal, subprocess, sys, time, urllib.parse, urllib.request
root = pathlib.Path(os.environ["FIXTURE_ROOT"])
assert (root / "subscribed").exists()
assert "--kiosk" in sys.argv
assert not any(x.startswith("--app=") for x in sys.argv)
url = sys.argv[sys.argv.index("--kiosk") + 1]
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


LUA_DISPATCH = r"""local seen = false
local function fields(value, names)
  assert(type(value) == "table")
  local count = 0
  for key, _ in pairs(value) do
    assert(names[key], "unexpected constructor field")
    count = count + 1
  end
  local wanted = 0
  for key, expected in pairs(names) do
    assert(type(value[key]) == expected, "incorrect typed field")
    wanted = wanted + 1
  end
  assert(count == wanted)
end
local hl = { dsp = { window = {}, workspace = {} } }
function hl.dsp.focus(value)
  if value.monitor ~= nil then
    fields(value, {monitor="string"})
    return {"focusmonitor", value.monitor}
  end
  fields(value, {window="string"})
  return {"focuswindow", value.window}
end
function hl.dsp.window.move(value)
  fields(value, {workspace="string",follow="boolean",window="string"})
  assert(value.follow == false)
  return {"movetoworkspacesilent", value.workspace .. "," .. value.window}
end
function hl.dsp.workspace.toggle_special(value)
  assert(type(value) == "string")
  return {"togglespecialworkspace", value}
end
function hl.dispatch(action)
  assert(not seen, "multiple dispatches from one expression")
  seen = true
  for _, value in ipairs(action) do
    io.write(tostring(#value), ":", value)
  end
end
local chunk, problem = load("return hl.dispatch(" .. arg[1] .. ")", "hyprctl-dispatch", "t", {hl=hl})
assert(chunk, problem)
chunk()
assert(seen)
"""


LUA_REFRESH = r"""local fixture = assert(load("return " .. arg[2]))()
local p = {x=123.75, y=-45.125}
local monitor = {name="DP-1"}
local workspace = {name="special:screensaver-DP-1"}
local window = {address="0xbeef", class="org.omarchy.screensaver", mapped=true,
  visible=true, hidden=false, fullscreen=2, monitor=monitor, workspace=workspace}
for _, key in ipairs({"address", "class", "mapped", "visible", "hidden", "fullscreen"}) do
  if fixture[key] ~= nil then window[key] = fixture[key] end
end
monitor.active_special_workspace = workspace
workspace.fullscreen_window = window
if fixture.ordinary_workspace then monitor.active_special_workspace = nil end
if fixture.no_fullscreen then workspace.fullscreen_window = nil end
if fixture.foreign_monitor then window.monitor = {} end
if fixture.foreign_workspace then window.workspace = {} end
local moves = 0
local hl = {dsp={cursor={}}}
function hl.get_cursor_pos() return {x=p.x, y=p.y} end
function hl.get_monitor_at(point)
  assert(point.x == p.x and point.y == p.y, "monitor lookup changed cursor coordinates")
  if fixture.no_monitor then return nil end
  return monitor
end
function hl.dsp.cursor.move(value)
  assert(type(value) == "table" and type(value.x) == "number" and type(value.y) == "number")
  local count = 0
  for key in pairs(value) do assert(key == "x" or key == "y"); count = count + 1 end
  assert(count == 2, "unexpected cursor constructor field")
  assert(value.x == p.x and value.y == p.y, "cursor coordinates changed")
  return {cursor_move=value}
end
function hl.dispatch(action)
  assert(action.cursor_move, "unexpected dispatch")
  moves = moves + 1
  assert(moves == 1, "multiple pointer refreshes")
  io.write("MOVE ", action.cursor_move.x, " ", action.cursor_move.y, "\n")
end
local env = setmetatable({hl=hl}, {__index=_G})
local chunk, problem = load(arg[1], "hyprctl-eval", "t", env)
assert(chunk, problem)
chunk()
io.write("RESULT ", moves == 1 and "refreshed" or "skipped", "\n")
"""


def lua_fixture(value):
    """Encode inert fixture values independently of the production Lua encoder."""
    if isinstance(value, dict):
        return (
            "{"
            + ",".join(
                "[" + lua_fixture(key) + "]=" + lua_fixture(item)
                for key, item in value.items()
            )
            + "}"
        )
    if isinstance(value, str):
        return '"' + "".join(f"\\{byte:03d}" for byte in value.encode()) + '"'
    if type(value) is bool:
        return "true" if value else "false"
    return str(value)


def native_eval(compositor, argv):
    """Run the production eval chunk in a typed compositor fixture using real Lua."""
    assert len(argv) == 3
    with (compositor.root / "eval-argv").open("a") as stream:
        stream.write(json.dumps(argv[1:]) + "\n")
    fixture = compositor.root / "cursor-fixture"
    values = json.loads(fixture.read_text()) if fixture.exists() else {}
    result = subprocess.run(
        ["lua", str(compositor.root / "refresh.lua"), argv[2], lua_fixture(values)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        sys.stderr.write(result.stderr)
        raise SystemExit(7)
    for line in result.stdout.splitlines():
        if line.startswith("MOVE "):
            with (compositor.root / "cursor-moves").open("a") as stream:
                stream.write(
                    json.dumps([float(number) for number in line.split()[1:]]) + "\n"
                )
        elif line.startswith("RESULT "):
            value = line.removeprefix("RESULT ")
            with (compositor.root / "eval-results").open("a") as stream:
                stream.write(value + "\n")
    print("ok")


def native_dispatch(compositor, argv):
    """Fake Hyprland's Lua-only constructor boundary, using the real parser."""
    if len(argv) != 3:
        print("return hl.dispatch(focusmonitor eDP-1): ')' expected near 'eDP'")
        raise SystemExit(7)
    with (compositor.root / "dispatch-argv").open("a") as stream:
        stream.write(json.dumps(argv[1:]) + "\n")
    result = subprocess.run(
        ["lua", str(compositor.root / "dispatch.lua"), argv[2]],
        capture_output=True,
        check=False,
    )
    if result.returncode:
        sys.stderr.buffer.write(result.stderr)
        raise SystemExit(7)
    pending = result.stdout
    decoded = []
    while pending:
        count, pending = pending.split(b":", 1)
        length = int(count)
        decoded.append(pending[:length].decode("utf-8"))
        pending = pending[length:]
    compositor.dispatch(*decoded)


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
        # Lifecycle tests retain all supported renderers independently of the shipped collection.
        fixture_repo = self.root / "renderer-fixture"
        fixture_catalog = fixture_repo / "branding/screensavers/catalog.json"
        fixture_catalog.parent.mkdir(parents=True)
        fixture_catalog.write_text((REPO / "tests/fixtures/screensaver-catalog.json").read_text())
        for name in ("live/index.html", "live/preview.png", "aranea-spider.glb", "silk-chamber.mp4", "silk-chamber.png"):
            asset = fixture_repo / "branding/3d" / name
            asset.parent.mkdir(parents=True, exist_ok=True)
            asset.write_bytes(b"renderer fixture")
        from tools.screensaver.catalog import load_catalog

        self.enterContext(patch.object(self.api, "load_catalog", lambda _: load_catalog(fixture_repo)))
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
        (self.root / "dispatch.lua").write_text(LUA_DISPATCH)
        (self.root / "refresh.lua").write_text(LUA_REFRESH)
        command = (
            "#!/usr/bin/env python3\n"
            + "import importlib.util, json, os, pathlib, sys\n"
            + f"spec=importlib.util.spec_from_file_location('fixture', {str(Path(__file__).resolve())!r})\n"
            + "module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)\nroot=pathlib.Path(os.environ['FIXTURE_ROOT']);compositor=module.Compositor(root)\n"
            + "name=pathlib.Path(sys.argv[0]).name\nif name == 'omarchy-shell':\n print(json.dumps(compositor.read('locked')))\nelif sys.argv[1] == 'monitors': print(json.dumps(compositor.monitors()))\nelif sys.argv[1] == 'clients': print(json.dumps(compositor.clients()))\nelif sys.argv[1] == 'activewindow': print(json.dumps(compositor.active_window()))\nelif sys.argv[1] == 'dispatch': module.native_dispatch(compositor, sys.argv)\nelif sys.argv[1] == 'eval': module.native_eval(compositor, sys.argv)\nelse: sys.exit(19)\n"
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

    def test_native_lua_dispatch_templates(self):
        from tools.screensaver.hyprland import Hyprland

        self.native_boundary()
        adapter = Hyprland()
        cases = [
            ("focusmonitor", "eDP-1", 'hl.dsp.focus({ monitor = "eDP-1" })'),
            (
                "focuswindow",
                "address:0xface",
                'hl.dsp.focus({ window = "address:0xface" })',
            ),
            (
                "movetoworkspacesilent",
                "special:work notes,address:0xbeef",
                'hl.dsp.window.move({ workspace = "special:work notes", follow = false, window = "address:0xbeef" })',
            ),
            (
                "togglespecialworkspace",
                "work notes",
                'hl.dsp.workspace.toggle_special("work notes")',
            ),
        ]
        for operation, value, _ in cases:
            adapter.dispatch(operation, value)
        calls = [
            json.loads(line)
            for line in (self.root / "dispatch-argv").read_text().splitlines()
        ]
        self.assertEqual(
            calls, [["dispatch", expression] for _, _, expression in cases]
        )
        actual = [
            json.loads(line)
            for line in (self.root / "dispatches").read_text().splitlines()
        ]
        self.assertEqual(actual, [[operation, value] for operation, value, _ in cases])

    def test_native_lua_string_data_cannot_become_dispatch_code(self):
        from tools.screensaver.hyprland import Hyprland

        self.native_boundary()
        adapter = Hyprland()
        values = [
            'quote " and backslash \\',
            "東京 🕷",
            "line\nreturn\rtab\t",
            "\x0099\x0199\x7f",
            '"); hl.dispatch(hl.dsp.workspace.toggle_special("INJECTED")); --',
        ]
        expected = []
        for value in values:
            for operation in (
                "focusmonitor",
                "togglespecialworkspace",
                "movetoworkspacesilent",
            ):
                argument = (
                    "special:" + value + ",address:0xbeef"
                    if operation == "movetoworkspacesilent"
                    else value
                )
                adapter.dispatch(operation, argument)
                expected.append([operation, argument])
        actual = [
            json.loads(line)
            for line in (self.root / "dispatches").read_text().splitlines()
        ]
        self.assertEqual(actual, expected)
        for operation, value in [
            ("exec", "anything"),
            ("focuswindow", 'address:0x1"});evil()'),
            ("movetoworkspacesilent", "special:x"),
            ("focusmonitor", None),
        ]:
            with self.assertRaises((ValueError, TypeError)):
                adapter.dispatch(operation, value)
        self.assertEqual(
            len((self.root / "dispatch-argv").read_text().splitlines()), len(expected)
        )

    def test_web_pointer_refreshes_shown_surfaces_and_settles_once_after_ready(self):
        self.write("behavior", "no-ready")
        history = self.root / "state/aranea/screensaver-last.json"
        history.parent.mkdir(parents=True)
        previous = {"version": 1, "lastId": "silk-chamber"}
        history.write_text(json.dumps(previous))
        process = self.start()
        wait_for(lambda: len(list(self.root.glob("child-*"))) == 2)
        refreshes = lambda: [
            json.loads(line)
            for line in (self.root / "pointer-refreshes").read_text().splitlines()
        ]
        wait_for(
            lambda: (self.root / "pointer-refreshes").exists() and len(refreshes()) == 2
        )
        children = {
            path.name.removeprefix("child-"): json.loads(path.read_text())["address"]
            for path in self.root.glob("child-*")
        }
        self.assertEqual(refreshes()[0]["addresses"], [children["DP-1"]])
        self.assertEqual(set(refreshes()[1]["addresses"]), set(children.values()))
        self.event("ready", "DP-1")
        time.sleep(0.1)
        self.assertFalse(self.api.session_status()["ready"])
        self.assertEqual(len(refreshes()), 2)
        self.event("ready", "HDMI-A-1")
        self.ready()
        records = [
            json.loads(line)
            for line in (self.root / "pointer-refreshes").read_text().splitlines()
        ]
        expected = {
            json.loads(path.read_text())["address"]
            for path in self.root.glob("child-*")
        }
        self.assertEqual(len(records), 3)
        self.assertEqual(set(records[-1]["addresses"]), expected)
        self.assertEqual(len(records[-1]["addresses"]), len(expected))
        self.assertTrue(all(record["history"] == previous for record in records))
        self.event("ready", "DP-1")
        self.event("ready", "HDMI-A-1")
        time.sleep(0.1)
        self.assertEqual(
            len((self.root / "pointer-refreshes").read_text().splitlines()), 3
        )
        self.event("dismiss")
        self.assert_closed(process)

    def test_pointer_refresh_failure_cleans_up_before_ready_or_history(self):
        (self.root / "refresh-failure").touch()
        process = self.start()
        wait_for(
            lambda: (
                self.api.session_status().get("ready") or (self.root / "error").exists()
            )
        )
        self.assertFalse(self.api.session_status()["ready"])
        self.assert_closed(process)
        self.assertIn("Pointer refresh unavailable", (self.root / "error").read_text())
        self.assertFalse((self.root / "state/aranea/screensaver-last.json").exists())
        self.assertTrue((self.root / "event-closed").exists())

    def test_final_pointer_settling_failure_also_preserves_unready_history(self):
        (self.root / "refresh-failure").write_text("3")
        process = self.start()
        wait_for(
            lambda: (
                self.api.session_status().get("ready") or (self.root / "error").exists()
            )
        )
        self.assertFalse(self.api.session_status()["ready"])
        self.assert_closed(process)
        self.assertIn("Pointer refresh unavailable", (self.root / "error").read_text())
        self.assertEqual(
            len((self.root / "pointer-refreshes").read_text().splitlines()), 3
        )
        self.assertFalse((self.root / "state/aranea/screensaver-last.json").exists())

    def test_native_pointer_refresh_guards_current_owned_fullscreen_surface(self):
        from tools.screensaver.hyprland import Hyprland

        self.native_boundary()
        adapter = Hyprland()
        cases = [
            ({}, True),
            ({"address": "0xcafe"}, False),
            ({"class": "foreign"}, False),
            ({"mapped": False}, False),
            ({"visible": False}, False),
            ({"hidden": True}, False),
            ({"fullscreen": 0}, False),
            ({"fullscreen": 1}, False),
            ({"ordinary_workspace": True}, False),
            ({"no_monitor": True}, False),
            ({"no_fullscreen": True}, False),
            ({"foreign_monitor": True}, False),
            ({"foreign_workspace": True}, False),
        ]
        moves = 0
        for fixture, refreshed in cases:
            with self.subTest(fixture=fixture):
                self.write("cursor-fixture", fixture)
                adapter.refresh_pointer(["0xbeef", "0xAB12"])
                moves += int(refreshed)
                actual = (self.root / "cursor-moves").read_text().splitlines()
                self.assertEqual(
                    [json.loads(line) for line in actual], [[123.75, -45.125]] * moves
                )
                self.assertEqual(
                    (self.root / "eval-results").read_text().splitlines()[-1],
                    "refreshed" if refreshed else "skipped",
                )
        calls = [
            json.loads(line)
            for line in (self.root / "eval-argv").read_text().splitlines()
        ]
        self.assertEqual(len(calls), len(cases))
        self.assertTrue(all(call[0] == "eval" and len(call) == 2 for call in calls))
        self.assertFalse((self.root / "dispatch-argv").exists())

    def test_native_pointer_refresh_accepts_one_and_sixty_four_addresses(self):
        from tools.screensaver.hyprland import Hyprland

        self.native_boundary()
        adapter = Hyprland()
        for addresses in (
            ["0xbeef"],
            ["0xbeef"] + [hex(index + 256) for index in range(63)],
        ):
            adapter.refresh_pointer(addresses)
        calls = [
            json.loads(line)
            for line in (self.root / "eval-argv").read_text().splitlines()
        ]
        self.assertEqual(len(calls), 2)
        moves = [
            json.loads(line)
            for line in (self.root / "cursor-moves").read_text().splitlines()
        ]
        self.assertEqual(moves, [[123.75, -45.125], [123.75, -45.125]])

    def test_native_pointer_addresses_reject_invalid_data_before_ipc(self):
        from tools.screensaver.hyprland import Hyprland

        self.native_boundary()
        adapter = Hyprland()
        invalid = [
            [],
            ["0xbeef"] * 65,
            "0xbeef",
            None,
            [None],
            [1],
            ["beef"],
            ["0x"],
            ["0xbeef\n"],
            ["0xbeef; print('INJECTED')"],
            ['0xbeef"}; hl.dispatch({}); --'],
        ]
        for addresses in invalid:
            with self.subTest(addresses=addresses):
                with self.assertRaises((ValueError, TypeError)):
                    adapter.refresh_pointer(addresses)
        self.assertFalse((self.root / "eval-argv").exists())

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

    def test_unavailable_collection_delegates_without_stock_picker_entry(self):
        scenes = [scene for scene in self.api.load_catalog(REPO) if scene.renderer == "web"]
        from dataclasses import replace

        scenes = [replace(scene, available=False, reason="Chromium missing") for scene in scenes]
        stock = self.root / "stock"
        stock.write_text('#!/bin/sh\ntouch "$FIXTURE_ROOT/stock-called"\n')
        stock.chmod(0o755)
        with (
            patch.object(self.api, "STOCK_LAUNCHER", str(stock)),
            patch.object(self.api, "load_catalog", return_value=scenes),
        ):
            process = self.start()
            process.join(3)
            self.assertFalse(process.is_alive())
            self.assertTrue((self.root / "stock-called").exists())

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
        self.assertFalse((self.root / "pointer-refreshes").exists())
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
