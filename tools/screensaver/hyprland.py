"""Bounded Hyprland IPC, fixed typed Lua dispatch and an owned event stream."""

import json
import os
import re
import socket
import subprocess
import time
from pathlib import Path

APP_ID = "org.omarchy.screensaver"


def lua_string(value):
    """Encode UTF-8 data as one Lua literal, including quotes and control bytes."""
    if not isinstance(value, str):
        raise TypeError("Compositor dispatch data must be a string")
    # Lua uses decimal byte escapes, not JSON's Unicode escape syntax. Always
    # emit three digits so a following digit cannot extend an escaped byte.
    return (
        '"'
        + "".join(
            chr(byte) if 32 <= byte <= 126 and byte not in (34, 92) else f"\\{byte:03d}"
            for byte in value.encode("utf-8")
        )
        + '"'
    )


class Hyprland:
    def __init__(self):
        self.deadline = None
        self.stream = None
        self.pending = b""

    def command(self, argv):
        timeout = min(0.4, self.deadline - time.monotonic()) if self.deadline else 0.4
        if timeout <= 0:
            raise ValueError("Renderer mapping deadline exceeded")
        try:
            result = subprocess.run(
                argv, capture_output=True, text=True, timeout=timeout, check=False
            )
        except subprocess.TimeoutExpired as error:
            raise ValueError("Compositor/lock observation timed out") from error
        if result.returncode or len(result.stdout) > 2 * 1024 * 1024:
            raise ValueError("Compositor/lock observation unavailable")
        return result.stdout.strip()

    def locked(self):
        value = self.command(["omarchy-shell", "lock", "isLocked"])
        if value not in ("true", "false"):
            raise ValueError("Lock state unavailable")
        return value == "true"

    def query(self, name):
        try:
            return json.loads(self.command(["hyprctl", name, "-j"]))
        except ValueError as error:
            raise ValueError("Invalid compositor observation") from error

    def monitors(self):
        values = self.query("monitors")
        if not isinstance(values, list) or len(values) > 64:
            raise ValueError("Invalid monitor observation")
        for monitor in values:
            if (
                not isinstance(monitor, dict)
                or type(monitor.get("id")) is not int
                or not isinstance(monitor.get("name"), str)
                or not re.fullmatch(r"[A-Za-z0-9_.:-]{1,128}", monitor["name"])
                or any(
                    not isinstance(monitor.get(key), dict)
                    for key in ("activeWorkspace", "specialWorkspace")
                )
            ):
                raise ValueError("Invalid monitor identity")
        return values

    def clients(self):
        values = self.query("clients")
        if not isinstance(values, list) or not all(
            isinstance(item, dict) for item in values
        ):
            raise ValueError("Invalid client observation")
        return values

    def active_window(self):
        value = self.query("activewindow")
        if not isinstance(value, dict):
            raise TypeError("Invalid focus observation")
        return value

    def dispatch(self, name, value):
        if name not in (
            "focusmonitor",
            "focuswindow",
            "movetoworkspacesilent",
            "togglespecialworkspace",
        ):
            raise ValueError("Unsupported compositor dispatch")
        literal = lua_string(value)
        if name == "focusmonitor":
            expression = "hl.dsp.focus({ monitor = " + literal + " })"
        elif name == "focuswindow":
            if not re.fullmatch(r"address:0x[0-9a-fA-F]+", value):
                raise ValueError("Invalid owned window address")
            expression = "hl.dsp.focus({ window = " + literal + " })"
        elif name == "movetoworkspacesilent":
            parts = value.rsplit(",address:", 1)
            if (
                len(parts) != 2
                or not parts[0]
                or not re.fullmatch(r"0x[0-9a-fA-F]+", parts[1])
            ):
                raise ValueError("Invalid owned workspace move")
            expression = (
                "hl.dsp.window.move({ workspace = "
                + lua_string(parts[0])
                + ", follow = false, window = "
                + lua_string("address:" + parts[1])
                + " })"
            )
        else:
            expression = "hl.dsp.workspace.toggle_special(" + literal + ")"
        self.command(["hyprctl", "dispatch", expression])

    def refresh_pointer(self, addresses):
        """Retarget an owned fullscreen surface without moving or globally hiding the pointer."""
        if (
            not isinstance(addresses, (list, tuple))
            or not 1 <= len(addresses) <= 64
            or any(
                not isinstance(address, str)
                or not re.fullmatch(r"0x[0-9a-fA-F]+", address)
                for address in addresses
            )
        ):
            raise ValueError("Invalid owned window addresses")
        owned = ", ".join("[" + lua_string(address) + "] = true" for address in addresses)
        expression = (
            "local owned = { " + owned + " }; "
            "local p = hl.get_cursor_pos(); "
            "local m = p and hl.get_monitor_at(p); "
            "local ws = m and m.active_special_workspace; "
            "local w = ws and ws.fullscreen_window; "
            "if w and owned[w.address] and w.class == " + lua_string(APP_ID) + " "
            "and w.mapped and w.visible and not w.hidden and w.fullscreen == 2 "
            "and w.monitor == m and w.workspace == ws then "
            "hl.dispatch(hl.dsp.cursor.move({ x = p.x, y = p.y })) end"
        )
        if self.command(["hyprctl", "eval", expression]) != "ok":
            raise ValueError("Pointer targeting refresh unavailable")

    def subscribe(self):
        signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        if not signature or "/" in signature or signature in (".", ".."):
            raise ValueError("Hyprland session unavailable")
        path = (
            Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / signature / ".socket2.sock"
        )
        self.stream = socket.socket(socket.AF_UNIX)
        self.stream.settimeout(0.4)
        try:
            self.stream.connect(str(path))
            self.stream.setblocking(False)
        except OSError:
            self.close()
            raise

    def events(self):
        try:
            chunk = self.stream.recv(65536)
        except BlockingIOError:
            return []
        if not chunk:
            raise ValueError("Compositor event stream closed")
        self.pending += chunk
        if len(self.pending) > 131072:
            raise ValueError("Compositor event stream overflow")
        lines = self.pending.split(b"\n")
        self.pending = lines.pop()
        return [line.decode("utf-8", errors="replace") for line in lines]

    def close(self):
        if self.stream is not None:
            self.stream.close()
            self.stream = None
