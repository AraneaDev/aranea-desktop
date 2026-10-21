"""Fixed renderer argv and cleanup of sessions launched by this owner only."""

import json
import os
import signal
import socket
import subprocess
import time
from dataclasses import dataclass


@dataclass
class OwnedProcess:
    """Retain the owned process group even when its original leader exits."""

    process: subprocess.Popen
    pgid: int
    closed: bool = False


def launch_web(
    url, profile_dir, app_id, *, popen=subprocess.Popen, browser="chromium", kiosk=False
):
    """Use kiosk for exact Wayland identity; retain app mode for legacy preview."""
    process = popen(
        [
            browser,
            f"--user-data-dir={profile_dir}",
            *(["--kiosk", url] if kiosk else [f"--app={url}"]),
            "--start-fullscreen",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-background-networking",
            "--disable-component-update",
            "--disable-sync",
            "--disable-extensions",
            "--disable-features=MediaRouter",
            f"--class={app_id}",
        ],
        start_new_session=True,
    )
    return OwnedProcess(process, process.pid)


def launch_video(asset, ipc_path, app_id, lua_path, *, popen=subprocess.Popen):
    """Launch local mpv with only the owned input script and readiness socket."""
    process = popen(
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
            f"--wayland-app-id={app_id}",
            f"--x11-name={app_id}",
            f"--input-ipc-server={ipc_path}",
            f"--script={lua_path}",
            "--",
            str(asset),
        ],
        start_new_session=True,
    )
    return OwnedProcess(process, process.pid)


def terminate_group(owned, *, grace=1.0, kill_timeout=1.0):
    """Terminate the owned session, including descendants of an exited leader."""
    if owned.closed:
        return
    if owned.pgid != owned.process.pid or owned.pgid <= 1 or owned.pgid == os.getpgrp():
        raise ValueError("Refusing to signal an unowned process group")

    def send(sig):
        try:
            os.killpg(owned.pgid, sig)
            return True
        except ProcessLookupError:
            return False

    owned.closed = True
    if send(signal.SIGTERM):
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            owned.process.poll()
            if not send(0):
                break
            time.sleep(min(0.02, max(0, deadline - time.monotonic())))
        else:
            send(signal.SIGKILL)
    try:
        owned.process.wait(timeout=kill_timeout)
    except subprocess.TimeoutExpired:
        send(signal.SIGKILL)
        owned.process.wait(timeout=kill_timeout)


def video_ready(ipc_path, *, timeout=0.2):
    """Require a configured video output and a displayed frame via bounded IPC."""
    deadline = time.monotonic() + timeout
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(max(0.001, timeout))
            client.connect(str(ipc_path))
            pending = b""
            budget = 8192
            for request_id, name in enumerate(
                ["vo-configured", "estimated-frame-number"], 1
            ):
                client.sendall(
                    json.dumps(
                        {"command": ["get_property", name], "request_id": request_id}
                    ).encode()
                    + b"\n"
                )
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        return False
                    client.settimeout(remaining)
                    while b"\n" not in pending:
                        remaining = deadline - time.monotonic()
                        if remaining <= 0:
                            return False
                        client.settimeout(remaining)
                        chunk = client.recv(min(4096, budget + 1))
                        budget -= len(chunk)
                        if not chunk or budget < 0:
                            return False
                        pending += chunk
                    line, pending = pending.split(b"\n", 1)
                    result = json.loads(line)
                    if not isinstance(result, dict):
                        return False
                    if result.get("request_id") != request_id:
                        continue
                    if result.get("error") != "success":
                        return False
                    value = result.get("data")
                    if name == "vo-configured" and value is not True:
                        return False
                    if name == "estimated-frame-number" and (
                        type(value) not in (int, float) or not value > 0
                    ):
                        return False
                    break
        return True
    except (OSError, ValueError):
        return False
