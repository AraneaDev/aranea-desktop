#!/usr/bin/env python3
"""Capture one ready native preview, publishing only after its own cleanup."""

import argparse
import json
import os
from pathlib import Path
import signal
import select
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))
from tools.screensaver.hyprland import APP_ID, Hyprland

SCENES = (
    "silk-journey",
    "neon-weaver",
    "spiderfall",
    "kanji-drift",
    "silken-flow",
    "neon-depths",
    "orbital-loom",
    "blackglass-foundry",
    "crystal-bloom",
)


class Owner:
    """Own the same accepted-FD supervisor worker used by preview-scene."""

    def __init__(self):
        self.process = None
        self.token = None

    def status(self):
        result = subprocess.run(
            [str(REPO / "scripts/aranea-screensaver"), "status", "--json"],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        return json.loads(result.stdout)

    def preview(self, scene):
        reader, writer = os.pipe()
        try:
            # Pending interrupts are delivered only after the exact child handle
            # is retained, so launch is always covered by capture's finally.
            pending = []

            def defer(signum, _frame):
                pending.append(signum)

            previous = {
                sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)
            }
            try:
                for sig in previous:
                    signal.signal(sig, defer)
                self.process = subprocess.Popen(
                    [
                        sys.executable,
                        str(REPO / "tools/screensaver/cli.py"),
                        "_preview",
                        scene,
                        str(writer),
                    ],
                    pass_fds=(writer,),
                    start_new_session=True,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
            if pending:
                raise InterruptedError("Screensaver capture interrupted during launch")
            os.close(writer)
            writer = None
            if not select.select([reader], [], [], 4)[0]:
                raise ValueError("Preview acceptance timed out")
            result = json.loads(os.read(reader, 8192))
            if not isinstance(result, dict) or not result.get("accepted"):
                raise ValueError("Native preview was not accepted")
            self.token = result.get("sessionId")
            return result
        finally:
            os.close(reader)
            if writer is not None:
                os.close(writer)

    def owns_client(self, pid, token):
        if (
            self.process is None
            or self.process.poll() is not None
            or token != self.token
        ):
            return False
        for _ in range(128):
            if pid == self.process.pid:
                return True
            if type(pid) is not int or pid <= 1:
                return False
            fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
            pid = int(fields[1])
        return False

    def stop_own(self, _token):
        if self.process is None:
            return
        # This unreaped direct child cannot be replaced by another session/PID.
        # SIGTERM requests the supervisor's existing restore-and-exit handler.
        if self.process.poll() is None:
            self.process.terminate()
        code = self.process.wait(timeout=5)
        if code != 0 and self.token is not None:
            raise ValueError("Owned preview exited without successful cleanup")


def capture(scene, output, owner, hypr, grab, *, clock=time.monotonic, wait=time.sleep):
    """Refuse foreign sessions and locks; leave saved settings and timers alone."""
    if scene not in SCENES:
        raise ValueError("Unknown screensaver capture scene")
    before = owner.status()
    if before["session"].get("running"):
        raise ValueError("Refusing capture while a screensaver session already exists")
    if hypr.locked():
        raise ValueError("Refusing screensaver capture while desktop is locked")
    if any(c.get("class") == APP_ID and c.get("mapped") for c in hypr.clients()):
        raise ValueError("Refusing capture with an existing screensaver window")
    monitors = [monitor for monitor in hypr.monitors() if monitor.get("focused")]
    if len(monitors) != 1:
        raise ValueError("Cannot identify the focused capture monitor")
    monitor = monitors[0]
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(
        prefix=".screensaver-", suffix=".png", dir=output.parent
    )
    os.close(descriptor)
    staged = Path(name)
    token = None
    try:
        try:
            accepted = owner.preview(scene)
            if (
                not accepted.get("accepted")
                or not isinstance(accepted.get("sessionId"), str)
                or not accepted.get("sessionId")
                or accepted.get("sessionId") == before["session"].get("sessionId")
            ):
                raise ValueError("Native preview was not accepted")
            token = accepted["sessionId"]
            deadline = clock() + 24
            while clock() < deadline:
                if hypr.locked():
                    raise ValueError("Desktop locked during screensaver capture")
                session = owner.status()["session"]
                if (
                    session.get("sessionId") != token
                    or session.get("sceneId") != scene
                    or not session.get("running")
                    or not session.get("preview")
                ):
                    raise ValueError("Owned preview ended or was replaced")
                if session.get("ready"):
                    break
                wait(0.1)
            else:
                raise ValueError("Native preview did not become ready")
            clients = [
                client
                for client in hypr.clients()
                if client.get("class") == APP_ID
                and client.get("mapped")
                and client.get("monitor") == monitor["id"]
                and client.get("fullscreen") == 2
                and owner.owns_client(client.get("pid"), token)
            ]
            if len(clients) != 1:
                raise ValueError(
                    "Ready preview has no unique owned fullscreen capture window"
                )
            if hypr.locked():
                raise ValueError("Desktop locked before screenshot")
            grab(monitor["name"], staged)
            if hypr.locked():
                raise ValueError("Desktop locked during screenshot")
            session = owner.status()["session"]
            if (
                session.get("sessionId") != token
                or session.get("sceneId") != scene
                or not session.get("ready")
                or not session.get("running")
            ):
                raise ValueError("Preview changed during screenshot")
            if not staged.stat().st_size:
                raise ValueError("Screenshot command produced an empty frame")
        finally:
            owner.stop_own(token)
        after = owner.status()
        if any(
            after.get(key) != before.get(key) for key in ("selectedId", "mode", "idle")
        ):
            raise ValueError(
                "Saved scene selection or idle settings changed during capture"
            )
        staged.replace(output)
    finally:
        staged.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene", choices=SCENES, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    def interrupted(_signal, _frame):
        raise InterruptedError("Screensaver capture interrupted")

    signal.signal(signal.SIGTERM, interrupted)

    def grab(monitor, output):
        subprocess.run(["grim", "-o", monitor, str(output)], check=True, timeout=10)

    try:
        capture(args.scene, args.output, Owner(), Hyprland(), grab)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Screensaver capture failed: {error}", file=sys.stderr)
        return 3
    print(f"captured: {args.output} (owned native screensaver preview)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
