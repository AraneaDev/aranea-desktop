"""Capture orchestration replaces only owner/compositor/grim boundaries."""

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "capture_screensaver", REPO / "tools/capture-screensaver.py"
)
try:
    capture_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(capture_module)
except FileNotFoundError:
    capture_module = None


class Desktop:
    def __init__(self):
        self.is_locked = False
        self.focus = "user-window"
        self.workspace = 7
        self.fullscreen = 2
        self.owned = True
        self.grabs = 0

    def locked(self):
        return self.is_locked

    def monitors(self):
        return [{"name": "DP-1", "id": 4, "focused": True}]

    def clients(self):
        return (
            [
                {
                    "class": "org.omarchy.screensaver",
                    "mapped": True,
                    "monitor": 4,
                    "fullscreen": self.fullscreen,
                    "pid": 123,
                }
            ]
            if self.focus == "preview"
            else []
        )


class Owner:
    def __init__(self, desktop):
        self.desktop = desktop
        self.session = {"running": False}
        self.ready = True
        self.started = 0
        self.stopped = []
        self.prefs = b'{"selectedId":"silk-journey","mode":"shuffle"}\n'
        self.idle = b"lock_timeout=600\nscreensaver_timeout=120\n"
        self.previous = None

    def status(self):
        return {
            "selectedId": "silk-journey",
            "mode": "shuffle",
            "idle": {"lock": 600},
            "session": self.session.copy(),
        }

    def preview(self, scene):
        self.started += 1
        self.previous = self.desktop.focus, self.desktop.workspace
        self.desktop.focus, self.desktop.workspace = "preview", 7
        self.session = {
            "running": True,
            "ready": self.ready,
            "preview": True,
            "sceneId": scene,
            "sessionId": "ours",
        }
        return {"accepted": True, "sessionId": "ours"}

    def owns_client(self, pid, token):
        return self.desktop.owned and token == self.session.get("sessionId")

    def stop_own(self, token):
        if self.session.get("sessionId") != token and not (
            token is None and self.started
        ):
            return
        self.stopped.append(self.session["sessionId"])
        self.session["running"] = False
        self.desktop.focus, self.desktop.workspace = self.previous


class ScreensaverCapture(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(
            capture_module, "native screensaver capture helper is implemented"
        )
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.output = Path(self.tmp.name) / "screensaver-neon-weaver.png"
        self.output.write_bytes(b"old image")
        self.desktop = Desktop()
        self.owner = Owner(self.desktop)
        self.clock_value = 0

    def clock(self):
        self.clock_value += 1
        return self.clock_value

    def grab(self, monitor, output):
        self.desktop.grabs += 1
        self.assertEqual(monitor, "DP-1")
        Path(output).write_bytes(b"new image")

    def run_capture(self, grab=None):
        capture_module.capture(
            "neon-weaver",
            self.output,
            self.owner,
            self.desktop,
            grab or self.grab,
            clock=self.clock,
            wait=lambda _: None,
        )

    def test_success_publishes_after_own_cleanup_and_preserves_selection_timers_focus(
        self,
    ):
        before = self.owner.prefs, self.owner.idle
        self.run_capture()
        self.assertEqual(self.output.read_bytes(), b"new image")
        self.assertEqual(
            (self.desktop.focus, self.desktop.workspace), ("user-window", 7)
        )
        self.assertEqual(self.owner.stopped, ["ours"])
        self.assertEqual((self.owner.prefs, self.owner.idle), before)

    def test_preexisting_session_is_never_started_or_stopped(self):
        self.owner.session = {"running": True, "sessionId": "user"}
        with self.assertRaises(ValueError):
            self.run_capture()
        self.assertEqual(
            (self.owner.started, self.owner.stopped, self.desktop.grabs), (0, [], 0)
        )

    def test_reused_acceptance_identity_is_refused_but_own_child_is_cleaned(self):
        self.owner.session = {"running": False, "sessionId": "ours"}
        with self.assertRaises(ValueError):
            self.run_capture()
        self.assertEqual(self.owner.stopped, ["ours"])
        self.assertEqual(self.desktop.grabs, 0)

    def test_locked_desktop_never_starts(self):
        self.desktop.is_locked = True
        with self.assertRaises(ValueError):
            self.run_capture()
        self.assertEqual((self.owner.started, self.desktop.grabs), (0, 0))

    def test_capture_failure_restores_own_preview_and_preserves_existing_image(self):
        def fail(*_):
            raise OSError("grim failed")

        with self.assertRaises(OSError):
            self.run_capture(fail)
        self.assertEqual(self.owner.stopped, ["ours"])
        self.assertEqual(self.output.read_bytes(), b"old image")
        self.assertEqual(self.desktop.focus, "user-window")

    def test_lock_during_capture_refuses_to_publish(self):
        def lock(monitor, path):
            self.grab(monitor, path)
            self.desktop.is_locked = True

        with self.assertRaises(ValueError):
            self.run_capture(lock)
        self.assertEqual(self.output.read_bytes(), b"old image")
        self.assertEqual(self.owner.stopped, ["ours"])

    def test_replacement_session_is_not_stopped_or_published(self):
        def replace(monitor, path):
            self.grab(monitor, path)
            self.owner.session["sessionId"] = "replacement"

        with self.assertRaises(ValueError):
            self.run_capture(replace)
        self.assertEqual(self.owner.stopped, [])
        self.assertEqual(self.output.read_bytes(), b"old image")

    def test_non_fullscreen_or_unowned_windows_never_reach_grim(self):
        for attribute, value in [("fullscreen", 0), ("owned", False)]:
            setattr(self.desktop, attribute, value)
            with self.assertRaises(ValueError):
                self.run_capture()
            self.assertEqual(self.desktop.grabs, 0)
            setattr(self.desktop, attribute, 2 if attribute == "fullscreen" else True)

    def test_interrupted_acceptance_cleans_up_the_started_preview(self):
        preview = self.owner.preview

        def interrupted(scene):
            preview(scene)
            raise InterruptedError("interrupted while waiting for acceptance")

        self.owner.preview = interrupted
        with self.assertRaises(InterruptedError):
            self.run_capture()
        self.assertEqual(self.owner.stopped, ["ours"])
        self.assertEqual(self.desktop.focus, "user-window")
        self.assertEqual(self.output.read_bytes(), b"old image")

    def test_wrong_ready_scene_is_refused(self):
        preview = self.owner.preview

        def wrong_scene(scene):
            accepted = preview(scene)
            self.owner.session["sceneId"] = "spiderfall"
            return accepted

        self.owner.preview = wrong_scene
        with self.assertRaises(ValueError):
            self.run_capture()
        self.assertEqual(self.desktop.grabs, 0)
        self.assertEqual(self.output.read_bytes(), b"old image")

    def test_unready_preview_is_cleaned_up_without_capture(self):
        self.owner.ready = False
        with self.assertRaises(ValueError):
            self.run_capture()
        self.assertEqual(self.desktop.grabs, 0)
        self.assertEqual(self.owner.stopped, ["ours"])


class SupervisorCompletion(unittest.TestCase):
    def worker(self, acknowledgment=b'{"accepted":true,"sessionId":"ours"}\n'):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        worker = root / "tools/screensaver/cli.py"
        worker.parent.mkdir(parents=True)
        restored = root / "restored"
        worker.write_text(
            "import os,sys,signal\n"
            "from pathlib import Path\n"
            f"def done(*_): Path({str(restored)!r}).write_text('restored');sys.exit(0)\n"
            "signal.signal(signal.SIGTERM,done)\n"
            f"os.write(int(sys.argv[3]),{acknowledgment!r})\n"
            "while True: signal.pause()\n"
        )
        owner = capture_module.Owner()

        def clean():
            if owner.process is not None:
                if owner.process.poll() is None:
                    owner.process.kill()
                owner.process.wait()

        self.addCleanup(clean)
        return root, restored, owner

    def test_retained_worker_acceptance_and_cleanup_use_existing_handshake(self):
        root, restored, owner = self.worker()
        with patch.object(capture_module, "REPO", root):
            accepted = owner.preview("neon-weaver")
            self.assertEqual(accepted["sessionId"], "ours")
            self.assertTrue(owner.owns_client(owner.process.pid, "ours"))
            owner.stop_own("ours")
        self.assertEqual(restored.read_text(), "restored")

    def test_actual_worker_is_restored_when_acceptance_wait_is_interrupted(self):
        root, restored, owner = self.worker()
        owner.status = lambda: {"session": {"running": False}}
        select = capture_module.select.select

        def interrupted(*args):
            self.assertTrue(select(*args)[0], "worker reached acceptance")
            raise InterruptedError("acceptance wait interrupted")

        with (
            patch.object(capture_module, "REPO", root),
            patch.object(capture_module.select, "select", interrupted),
        ):
            with self.assertRaises(InterruptedError):
                capture_module.capture(
                    "neon-weaver", root / "image.png", owner, Desktop(), lambda *_: None
                )
        self.assertIsNotNone(owner.process.poll())
        self.assertEqual(restored.read_text(), "restored")
        self.assertFalse((root / "image.png").exists())

    def test_malformed_acceptance_restores_actual_worker(self):
        root, restored, owner = self.worker(b"invalid-json\n")
        owner.status = lambda: {"session": {"running": False}}
        with patch.object(capture_module, "REPO", root):
            with self.assertRaises(ValueError):
                capture_module.capture(
                    "neon-weaver", root / "image.png", owner, Desktop(), lambda *_: None
                )
        self.assertIsNotNone(owner.process.poll())
        self.assertEqual(restored.read_text(), "restored")
        self.assertFalse((root / "image.png").exists())

    def test_empty_status_is_not_treated_as_completed_owned_cleanup(self):
        child = subprocess.Popen(
            [
                sys.executable,
                "-u",
                "-c",
                "import signal,time,sys;signal.signal(signal.SIGTERM,lambda *_:sys.exit(0));print('ready');time.sleep(60)",
            ],
            stdout=subprocess.PIPE,
            text=True,
        )

        def clean():
            if child.poll() is None:
                child.kill()
            child.wait()
            child.stdout.close()

        self.addCleanup(clean)
        self.assertEqual(child.stdout.readline().strip(), "ready")
        owner = capture_module.Owner()
        owner.process = child
        owner.token = "ours"
        owner.status = lambda: {"session": {"running": False}}
        owner.stop_own("ours")
        self.assertIsNotNone(
            child.poll(), "owned supervisor must exit before cleanup is complete"
        )


if __name__ == "__main__":
    unittest.main()
