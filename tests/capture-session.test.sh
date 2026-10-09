#!/usr/bin/env bash
# A private capture bus must not share document/accessibility runtime paths.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export CAPTURE_SESSION_HELPER="$repo_root/tools/with-capture-session"
python3 - <<'PY'
import os
from pathlib import Path
import socket
import subprocess
import signal

live = Path(os.environ['XDG_RUNTIME_DIR'])
(live / 'doc').mkdir()
(live / 'doc' / 'sentinel').write_text('live documents')
(live / 'at-spi').mkdir()
display = socket.socket(socket.AF_UNIX)
display.bind(str(live / 'wayland-test'))
accessibility = socket.socket(socket.AF_UNIX)
accessibility.bind(str(live / 'at-spi' / 'bus_0'))
env = dict(os.environ, WAYLAND_DISPLAY='wayland-test',
           LIVE_CAPTURE_RUNTIME=str(live))
probe = '''
import os
from pathlib import Path
import socket
import subprocess
runtime = Path(os.environ['XDG_RUNTIME_DIR'])
assert runtime != Path(os.environ['LIVE_CAPTURE_RUNTIME']), 'capture shares live runtime'
assert runtime.stat().st_mode & 0o777 == 0o700
assert not (runtime / 'doc').exists(), 'capture sees live documents'
assert not (runtime / 'at-spi').exists(), 'capture sees live accessibility socket'
assert 'DBUS_SESSION_BUS_ADDRESS' in os.environ
client = socket.socket(socket.AF_UNIX)
client.connect(str(runtime / os.environ['WAYLAND_DISPLAY']))
client.close()
(runtime / 'doc').mkdir()
(runtime / 'doc' / 'fixture').write_text('capture document')
(runtime / 'at-spi').mkdir()
child = subprocess.Popen(['sleep', '30'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
Path(os.environ['CAPTURE_CHILD_PID_FILE']).write_text(str(child.pid))
print(runtime)
raise SystemExit(int(os.environ.get('PROBE_EXIT', '0')))
'''
display.listen()
for wayland in ('wayland-test', str(live / 'wayland-test')):
    for status in (0, 7):
        pid_file = Path(os.environ['TMPDIR']) / 'capture-child.pid'
        result = subprocess.run([os.environ['CAPTURE_SESSION_HELPER'], 'python3', '-c', probe],
                                env=dict(env, WAYLAND_DISPLAY=wayland, PROBE_EXIT=str(status),
                                         CAPTURE_CHILD_PID_FILE=str(pid_file)),
                                text=True, capture_output=True)
        assert result.returncode == status, result.stderr
        child_pid = int(pid_file.read_text())
        try:
            child_stat = Path(f'/proc/{child_pid}/stat')
            assert not child_stat.exists() or child_stat.read_text().split()[2] == 'Z', 'capture child still running after exit'
        finally:
            try:
                os.kill(child_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        private = Path(result.stdout.strip())
        assert not private.exists(), 'private runtime leaked after capture'
        assert (live / 'doc' / 'sentinel').read_text() == 'live documents'
        assert not (live / 'doc' / 'fixture').exists()
        assert (live / 'at-spi' / 'bus_0').is_socket()
        connection, _ = display.accept()
        connection.close()
print('capture runtime isolation, display access, exit status and cleanup passed')
PY
