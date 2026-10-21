"""HTTP isolation and owned renderer processes at their real OS boundaries."""

import importlib
import json
import os
import select
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlsplit
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


class RendererTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert (ROOT / "tools/screensaver/http_server.py").is_file(), (
            "shared scene server is missing"
        )
        cls.http = importlib.import_module("tools.screensaver.http_server")
        cls.renderers = importlib.import_module("tools.screensaver.renderers")
        cls.Scene = importlib.import_module("tools.screensaver.catalog").Scene

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "live").mkdir()
        (self.root / "live/index.html").write_text("scene")
        (self.root / "live/scene.mjs").write_text("module")
        (self.root / "model.glb").write_bytes(b"model")
        (self.root / "secret").write_text("private")
        self.scene = self.Scene(
            "test",
            "Test",
            "Scene",
            "web",
            None,
            True,
            None,
            True,
            self.root,
            self.root / "live/index.html",
            (self.root / "live", self.root / "model.glb"),
        )

    def request(self, server, path, *, token="token", body=None, status=204, raw=None):
        data = (
            raw
            if raw is not None
            else json.dumps(body or {"screenId": "DP-1"}).encode()
        )
        request = Request(
            server.url("DP-1").split("/live/")[0] + path,
            data=data,
            headers={"X-Aranea-Session": token},
            method="POST",
        )
        try:
            with urlopen(request, timeout=2) as response:
                self.assertEqual(response.status, status)
        except HTTPError as error:
            self.assertEqual(error.code, status)
            error.close()

    def test_assets_allowlist_and_containment(self):
        (self.root / "live/escape").symlink_to(self.root / "secret")
        (self.root / "live/outside").symlink_to("/etc/passwd")
        (self.root / "live/huge").touch()
        with (self.root / "live/huge").open("wb") as file:
            file.truncate(32 * 1024 * 1024 + 1)
        with self.http.SceneServer(self.scene, "token", ["DP-1"]) as server:
            url = server.url("DP-1")
            self.assertEqual(
                parse_qs(urlsplit(url).query),
                {"session": ["token"], "screen": ["DP-1"]},
            )
            base = url.split("/live/")[0]
            for path, data in [
                ("/live/", b"scene"),
                ("/live/scene.mjs", b"module"),
                ("/model.glb", b"model"),
            ]:
                with urlopen(base + path) as response:
                    self.assertEqual(response.read(), data)
                    self.assertEqual(
                        response.headers["X-Content-Type-Options"], "nosniff"
                    )
            for path in [
                "/secret",
                "/live",
                "/live/../secret",
                "/live/%2e%2e/secret",
                "/live/%252e%252e/secret",
                "/live/%5c../secret",
                "/live/%00",
                "/live/escape",
                "/live/outside",
                "/live/huge",
                "/",
            ]:
                with self.assertRaises(HTTPError, msg=path) as caught:
                    urlopen(base + path)
                self.assertIn(caught.exception.code, (404, 413))
                caught.exception.close()
            with self.assertRaises(ValueError):
                server.url("unknown")
            with self.assertRaises(HTTPError) as caught:
                urlopen(base + "/live/" + "x" * 9000)
            self.assertEqual(caught.exception.code, 414)
            caught.exception.close()
        with self.assertRaises(OSError):
            socket.create_connection(("127.0.0.1", urlsplit(url).port), timeout=0.2)

    def test_authenticated_bounded_screen_events_and_deduplication(self):
        with self.http.SceneServer(self.scene, "token", ["DP-1", "HDMI-A-1"]) as server:
            self.request(server, "/__ready", token="wrong", status=403)
            self.request(server, "/__ready", body={"screenId": "unknown"}, status=403)
            self.request(server, "/__ready", raw=b"[]", status=400)
            self.request(server, "/__ready", raw=b"invalid", status=400)
            self.request(server, "/__ready", raw=b"[" * 1100 + b"]" * 1100, status=400)
            self.request(server, "/__ready", raw=b"x" * 8193, status=413)
            self.request(server, "/__ready", raw=b"", status=400)
            self.request(server, "/__bogus", status=403)
            self.assertEqual(server.drain_events(), [])
            for _ in range(2):
                self.request(server, "/__ready")
            self.request(server, "/__ready", body={"screenId": "HDMI-A-1"})
            self.request(
                server, "/__failed", body={"screenId": "DP-1", "message": "failed"}
            )
            self.request(server, "/__dismiss")
            self.assertEqual(
                server.drain_events(),
                [
                    {"kind": "ready", "screenId": "DP-1", "message": ""},
                    {"kind": "ready", "screenId": "HDMI-A-1", "message": ""},
                    {"kind": "failed", "screenId": "DP-1", "message": "failed"},
                    {"kind": "dismiss", "screenId": "DP-1", "message": ""},
                ],
            )
            self.request(
                server,
                "/__failed",
                body={"screenId": "HDMI-A-1", "message": "x" * 513},
                status=400,
            )
            self.assertEqual(server.drain_events(), [])

    def test_incomplete_event_body_is_bounded(self):
        with self.http.SceneServer(self.scene, "token", ["DP-1"]) as server:
            with socket.create_connection(
                ("127.0.0.1", urlsplit(server.url("DP-1")).port)
            ) as client:
                client.settimeout(2)
                client.sendall(
                    b"POST /__ready HTTP/1.0\r\nX-Aranea-Session: token\r\nContent-Length: 8192\r\n\r\n{"
                )
                self.assertIn(b"408", client.recv(4096))
            self.assertEqual(server.drain_events(), [])

    def test_trickled_event_body_has_an_absolute_deadline(self):
        with (
            self.http.SceneServer(self.scene, "token", ["DP-1"]) as server,
            socket.create_connection(
                ("127.0.0.1", urlsplit(server.url("DP-1")).port)
            ) as client,
        ):
            client.settimeout(2)
            client.sendall(
                b"POST /__ready HTTP/1.0\r\nX-Aranea-Session: token\r\nContent-Length: 8192\r\n\r\n"
            )
            started = time.monotonic()
            while time.monotonic() - started < 1.2:
                client.sendall(b"x")
                if select.select([client], [], [], 0.1)[0]:
                    break
            self.assertIn(b"408", client.recv(4096))
            self.assertLess(time.monotonic() - started, 0.9)

    def test_fixed_renderer_argv_and_owned_sessions(self):
        records = []

        def spawn(argv, **kwargs):
            record = self.root / f"argv-{len(records)}.json"
            code = (
                "import json,sys;open(sys.argv[1],'w').write(json.dumps(sys.argv[2:]))"
            )
            child = subprocess.Popen(
                [sys.executable, "-c", code, str(record), *argv], **kwargs
            )
            self.addCleanup(child.wait, timeout=2)
            records.append(record)
            return child

        web = self.renderers.launch_web(
            "http://127.0.0.1:123/live/?session=token",
            self.root / "profile",
            "org.omarchy.screensaver",
            popen=spawn,
        )
        kiosk = self.renderers.launch_web(
            "http://127.0.0.1:123/live/?session=token",
            self.root / "profile-kiosk",
            "org.omarchy.screensaver",
            popen=spawn,
            kiosk=True,
        )
        video = self.renderers.launch_video(
            self.root / "model.glb",
            self.root / "ipc",
            "org.omarchy.screensaver",
            ROOT / "branding/3d/preview.lua",
            popen=spawn,
        )
        for owned in [web, kiosk, video]:
            self.assertEqual(os.getpgid(owned.process.pid), owned.pgid)
            self.assertEqual(owned.pgid, owned.process.pid)
            self.assertEqual(owned.process.wait(timeout=2), 0)
        webargs, kioskargs, videoargs = [
            json.loads(record.read_text()) for record in records
        ]
        self.assertEqual(
            webargs,
            [
                "chromium",
                f"--user-data-dir={self.root / 'profile'}",
                "--app=http://127.0.0.1:123/live/?session=token",
                "--start-fullscreen",
                "--no-first-run",
                "--no-default-browser-check",
                "--disable-background-networking",
                "--disable-component-update",
                "--disable-sync",
                "--disable-extensions",
                "--disable-features=MediaRouter",
                "--class=org.omarchy.screensaver",
            ],
        )
        self.assertEqual(
            kioskargs,
            [
                "chromium",
                f"--user-data-dir={self.root / 'profile-kiosk'}",
                "--kiosk",
                "http://127.0.0.1:123/live/?session=token",
                "--start-fullscreen",
                "--no-first-run",
                "--no-default-browser-check",
                "--disable-background-networking",
                "--disable-component-update",
                "--disable-sync",
                "--disable-extensions",
                "--disable-features=MediaRouter",
                "--class=org.omarchy.screensaver",
            ],
        )
        self.assertEqual(
            videoargs,
            [
                "mpv",
                "--no-config",
                "--load-scripts=no",
                "--ytdl=no",
                "--no-audio",
                "--no-osc",
                "--input-default-bindings=no",
                "--input-conf=/dev/null",
                "--input-terminal=no",
                "--no-resume-playback",
                "--save-position-on-quit=no",
                "--stop-screensaver=no",
                "--fullscreen",
                "--loop-file=inf",
                "--cursor-autohide=always",
                "--title=Aranea Screensaver",
                "--wayland-app-id=org.omarchy.screensaver",
                "--x11-name=org.omarchy.screensaver",
                f"--input-ipc-server={self.root / 'ipc'}",
                f"--script={ROOT / 'branding/3d/preview.lua'}",
                "--",
                str(self.root / "model.glb"),
            ],
        )

    def test_stubborn_owned_descendant_cleanup_after_leader_exit(self):
        marker = self.root / "child"
        code = "import os,signal,sys,time; pid=os.fork();\nif pid: sys.exit(0)\nsignal.signal(signal.SIGTERM,signal.SIG_IGN);open(sys.argv[1],'w').write(str(os.getpid()));time.sleep(30)"

        def spawn(_argv, **kwargs):
            return subprocess.Popen([sys.executable, "-c", code, str(marker)], **kwargs)

        owned = self.renderers.launch_web(
            "http://127.0.0.1/",
            self.root / "profile",
            "org.omarchy.screensaver",
            popen=spawn,
        )
        self.addCleanup(self.renderers.terminate_group, owned, grace=0.1)
        self.assertEqual(owned.process.wait(timeout=2), 0)
        deadline = time.monotonic() + 2
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        pid = int(marker.read_text())
        unrelated = subprocess.Popen(
            [sys.executable, "-c", "import time;time.sleep(30)"]
        )
        try:
            self.renderers.terminate_group(owned, grace=0.1)
            deadline = time.monotonic() + 2
            while (
                Path(f"/proc/{pid}/stat").exists()
                and Path(f"/proc/{pid}/stat").read_text().split()[2] != "Z"
                and time.monotonic() < deadline
            ):
                time.sleep(0.01)
            self.assertTrue(
                not Path(f"/proc/{pid}/stat").exists()
                or Path(f"/proc/{pid}/stat").read_text().split()[2] == "Z"
            )
            self.assertIsNone(unrelated.poll())
        finally:
            unrelated.terminate()
            unrelated.wait(timeout=2)

    def test_repeated_cleanup_does_not_signal_a_reused_group(self):
        def spawn(_argv, **kwargs):
            return subprocess.Popen(
                [sys.executable, "-c", "import time;time.sleep(30)"], **kwargs
            )

        owned = self.renderers.launch_web(
            "http://127.0.0.1/",
            self.root / "profile",
            "org.omarchy.screensaver",
            popen=spawn,
        )
        self.renderers.terminate_group(owned, grace=0.1)
        self.assertIsNotNone(owned.process.poll())
        with patch.object(
            self.renderers.os,
            "killpg",
            side_effect=AssertionError("already cleaned group was signalled"),
        ):
            self.renderers.terminate_group(owned, grace=0.1)

    def test_malformed_event_headers_are_rejected_without_handler_failure(self):
        with self.http.SceneServer(self.scene, "token", ["DP-1"]) as server:
            port = urlsplit(server.url("DP-1")).port
            for headers, status in [
                (b"X-Aranea-Session: \xff\r\nContent-Length: 0\r\n", b"403"),
                (b"X-Aranea-Session: token\r\nContent-Length: -1\r\n", b"400"),
                (
                    b"X-Aranea-Session: token\r\nContent-Length: 2\r\nContent-Length: 3\r\n",
                    b"400",
                ),
                (b"X-Aranea-Session: token\r\nTransfer-Encoding: chunked\r\n", b"400"),
            ]:
                with (
                    self.subTest(headers=headers),
                    socket.create_connection(("127.0.0.1", port)) as client,
                ):
                    client.settimeout(2)
                    client.sendall(b"POST /__ready HTTP/1.0\r\n" + headers + b"\r\n")
                    self.assertIn(status, client.recv(4096))
            self.assertEqual(server.drain_events(), [])

    def test_video_readiness_requires_rendered_frame_and_bounds_ipc(self):
        for mode in [
            "ready",
            "not-ready",
            "oversized",
            "invalid",
            "nested",
            "timeout",
            "trickle",
        ]:
            with self.subTest(mode=mode):
                path = self.root / f"{mode}.sock"
                listener = socket.socket(socket.AF_UNIX)
                listener.bind(str(path))
                listener.listen(1)

                def serve(mode=mode, listener=listener):
                    with listener, listener.accept()[0] as client:
                        try:
                            if mode == "timeout":
                                time.sleep(0.3)
                                return
                            if mode == "trickle":
                                for _ in range(10):
                                    client.sendall(b"x")
                                    time.sleep(0.05)
                                return
                            if mode == "nested":
                                client.sendall(b"[" * 1100 + b"]" * 1100 + b"\n")
                                return
                            stream = client.makefile("rb")
                            for value in [True, 2 if mode == "ready" else 0]:
                                request = json.loads(stream.readline())
                                if mode == "oversized":
                                    client.sendall(b"x" * 8193)
                                    return
                                if mode == "invalid":
                                    client.sendall(b"[]\n")
                                    return
                                self.assertIn(
                                    request["command"][1],
                                    ["vo-configured", "estimated-frame-number"],
                                )
                                client.sendall(
                                    json.dumps(
                                        {
                                            "request_id": request["request_id"],
                                            "error": "success",
                                            "data": value,
                                        }
                                    ).encode()
                                    + b"\n"
                                )
                        except (BrokenPipeError, ConnectionResetError):
                            pass

                worker = threading.Thread(target=serve)
                worker.start()
                try:
                    started = time.monotonic()
                    self.assertEqual(
                        self.renderers.video_ready(path, timeout=0.15), mode == "ready"
                    )
                    self.assertLess(time.monotonic() - started, 0.3)
                finally:
                    worker.join(timeout=2)
        self.assertFalse(self.renderers.video_ready(self.root / "absent"))


if __name__ == "__main__":
    unittest.main()
