"""Send a pointer move/click only to the native fixture private compositor.
Protocol: https://github.com/swaywm/wlr-protocols/blob/master/unstable/wlr-virtual-pointer-unstable-v1.xml
"""

import os
import pathlib
import socket
import stat
import struct
import time
import sys
import signal

signal.alarm(8)


def require(condition, message="not a private native fixture socket"):
    if not condition:
        raise RuntimeError(message)


runtime = pathlib.Path(os.environ["XDG_RUNTIME_DIR"]).resolve()
require(
    runtime.parent.parent == pathlib.Path("/tmp")
    and runtime.parent.name.startswith("aranea-native.")
)
require(runtime.name == "runtime" and runtime.stat().st_uid == os.getuid())
require(stat.S_IMODE(runtime.stat().st_mode) == 0o700)
require((runtime.parent / "private-native-fixture").read_text() == str(os.getuid()))
name = os.environ["WAYLAND_DISPLAY"]
require("/" not in name and name.startswith("wayland-"))
x, y = map(int, sys.argv[1:3])
require(0 <= x < 800 and 0 <= y < 600)
click = len(sys.argv) == 4 and sys.argv[3] == "click"
path = (runtime / name).resolve()
require(
    path.parent == runtime
    and stat.S_ISSOCK(path.stat().st_mode)
    and path.stat().st_uid == os.getuid()
)
conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
conn.settimeout(3)
conn.connect(str(path))
buffer = b""
globals_ = {}


def uints(*values):
    return struct.pack("=" + "I" * len(values), *values)


def text(value):
    value = value.encode() + b"\0"
    return uints(len(value)) + value + b"\0" * ((-len(value)) % 4)


def send(obj, opcode, payload=b""):
    conn.sendall(uints(obj, ((len(payload) + 8) << 16) | opcode) + payload)


def receive():
    global buffer
    while len(buffer) < 8:
        chunk = conn.recv(65536)
        if not chunk:
            raise RuntimeError("display closed")
        buffer += chunk
    obj, header = struct.unpack("=II", buffer[:8])
    size = header >> 16
    require(8 <= size <= 65535 and size % 4 == 0)
    while len(buffer) < size:
        chunk = conn.recv(65536)
        if not chunk:
            raise RuntimeError("truncated display event")
        buffer += chunk
    payload = buffer[8:size]
    buffer = buffer[size:]
    return obj, header & 65535, payload


def sync(callback):
    send(1, 0, uints(callback))
    for _ in range(500):
        obj, opcode, payload = receive()
        if obj == 1 and opcode == 0:
            raise RuntimeError(repr(payload))
        if obj == 2 and opcode == 0:
            global_name, length = struct.unpack("=II", payload[:8])
            interface = payload[8 : 8 + length - 1].decode()
            version = struct.unpack(
                "=I",
                payload[8 + ((length + 3) // 4) * 4 : 12 + ((length + 3) // 4) * 4],
            )[0]
            globals_[interface] = (global_name, version)
        if obj == callback and opcode == 0:
            return
    raise RuntimeError("display roundtrip did not finish")


send(1, 1, uints(2))
sync(3)
manager_name, _ = globals_["zwlr_virtual_pointer_manager_v1"]
send(2, 0, uints(manager_name) + text("zwlr_virtual_pointer_manager_v1") + uints(1, 4))
send(4, 0, uints(0, 5))
sync(6)
now = lambda: int(time.monotonic() * 1000) & 0xFFFFFFFF
send(5, 1, uints(now(), x, y, 800, 600))
send(5, 4)
sync(7)
time.sleep(0.1)
if click:
    send(5, 2, uints(now(), 272, 1))
    send(5, 4)
    sync(8)
    time.sleep(0.1)
    send(5, 2, uints(now(), 272, 0))
    send(5, 4)
    sync(9)
    time.sleep(0.1)
if not click:
    time.sleep(0.8)
send(5, 8)
send(4, 1)
sync(10 if click else 8)
conn.close()
print("private virtual-pointer dispatched; fixture must independently verify delivery")
