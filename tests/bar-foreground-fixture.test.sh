#!/usr/bin/env bash
# The actual bar fake command must isolate state and survive interrupted writers.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
python3 - "$repo_root" <<'PY'
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys

sandbox = Path(os.environ["ARANEA_TEST_SANDBOX"])
source = Path(sys.argv[1]) / "tests/qml/fixtures/bar-foreground-command.py"
bin_dir = sandbox / "bar-store-commands"
bin_dir.mkdir()
for name in ("bar-foreground-fixture", "omarchy-bar-text-color"):
    (bin_dir / name).symlink_to(source)

# Observe the real data file descriptor after open, without substituting the
# helper's state or persistence logic. The old final file and new temporary
# file are both eligible; the stable lock file is deliberately excluded.
launcher = sandbox / "pause-bar-data-open.py"
launcher.write_text('''import io, os, pathlib, runpy, signal, sys
real_open = io.open
report_fd = int(sys.argv[1])
def observed_open(file, mode="r", *args, **kwargs):
    stream = real_open(file, mode, *args, **kwargs)
    opened = pathlib.Path(os.readlink("/proc/self/fd/" + str(stream.fileno())))
    if "w" in mode and opened.parent.name == "bar-foreground-fixture" and (opened.name == "state.json" or opened.name.startswith(".state-")):
        os.write(report_fd, (str(opened) + "\\n").encode())
        signal.pause()
    return stream
io.open = observed_open
sys.argv = sys.argv[2:]
runpy.run_path(sys.argv[0], run_name="__main__")
''')


def environment(case, state_name="state-a"):
    root = sandbox / case
    state = root / state_name
    state.mkdir(parents=True, exist_ok=True)
    return dict(os.environ, ARANEA_TEST_SANDBOX=str(root), XDG_STATE_HOME=str(state))


def invoke(env, *args, command="bar-foreground-fixture", check=True):
    result = subprocess.run(
        [str(bin_dir / command), *args], env=env, text=True,
        capture_output=True, timeout=5, check=False,
    )
    if check:
        assert result.returncode == 0, result.stderr
    return result


def configure(env, response):
    return invoke(env, "configure", json.dumps({"response": response, "delay": 0}))


def published_state(env):
    # Discover the actual store rather than assuming the repaired layout. This
    # keeps interruption/read-only checks meaningful against the old helper.
    files = list(Path(env["ARANEA_TEST_SANDBOX"]).glob("**/bar-foreground-fixture/state.json"))
    assert len(files) == 1, files
    return files[0]


def isolation():
    first = environment("isolation")
    second = environment("isolation", "state-b")
    configure(first, "only fixture A")
    snapshot = json.loads(invoke(second, "snapshot").stdout)
    assert snapshot["response"] == "", "fixture B inherited fixture A's state"
    configure(second, "only fixture B")
    assert json.loads(invoke(first, "snapshot").stdout)["response"] == "only fixture A"
    assert not (Path(first["ARANEA_TEST_SANDBOX"]) / "bar-foreground-fixture").exists()


def snapshot_is_read_only():
    env = environment("snapshot")
    configure(env, "retained snapshot")
    state = published_state(env)
    os.utime(state, ns=(1_000_000_000, 1_000_000_000))
    before = (state.read_bytes(), state.stat().st_ino, state.stat().st_mtime_ns)
    result = json.loads(invoke(env, "snapshot").stdout)
    assert result["response"] == "retained snapshot"
    after = (state.read_bytes(), state.stat().st_ino, state.stat().st_mtime_ns)
    assert after == before, "snapshot rewrote the published state document"


def interrupted_mutation():
    env = environment("interruption")
    configure(env, "#abcdef")
    state = published_state(env)
    before = state.read_bytes()
    lock_inode = (state.parent / "lock").stat().st_ino
    read_fd, write_fd = os.pipe()
    child = None
    try:
        child = subprocess.Popen(
            [sys.executable, str(launcher), str(write_fd),
             str(bin_dir / "bar-foreground-fixture"), "configure", '{"response":"unpublished"}'],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            pass_fds=(write_fd,), text=True,
        )
        os.close(write_fd)
        write_fd = None
        ready, _, _ = select.select([read_fd], [], [], 5)
        assert ready, "mutating helper did not reach the real data-write open"
        opened = Path(os.read(read_fd, 4096).decode().strip())
        assert opened.parent == state.parent and opened != state.parent / "lock", opened
        assert opened.exists(), "observer did not report an actual opened data file"
        child.terminate()
        stdout, stderr = child.communicate(timeout=5)
        assert child.returncode == -signal.SIGTERM, (child.returncode, stderr)
        assert stdout == "", "writer completed before interruption"
    finally:
        os.close(read_fd)
        if write_fd is not None:
            os.close(write_fd)
        if child is not None and child.poll() is None:
            child.kill()
            child.communicate(timeout=5)
    assert state.read_bytes() == before, "interrupted writer truncated or replaced published JSON"
    assert json.loads(invoke(env, "snapshot").stdout)["response"] == "#abcdef"
    configure(env, "#123456")
    assert json.loads(invoke(env, "snapshot").stdout)["response"] == "#123456"
    assert (state.parent / "lock").stat().st_ino == lock_inode, "atomic updates replaced the coordination lock"
    probe = invoke(env, "top", "32", "#ffffff", "#000000", command="omarchy-bar-text-color")
    assert probe.stdout.strip() == "#123456"
    final = json.loads(invoke(env, "snapshot").stdout)
    assert (final["started"], final["finished"]) == (1, 1), final
    print("  interrupted actual data target:", opened.name)


def sandbox_context_required():
    env = environment("context")
    del env["ARANEA_TEST_SANDBOX"]
    result = invoke(env, "snapshot", check=False)
    assert result.returncode != 0 and result.stdout == "", "helper accepted missing test sandbox"
    assert not (Path(env["XDG_STATE_HOME"]) / "bar-foreground-fixture").exists()
    env = environment("missing-state-home")
    del env["XDG_STATE_HOME"]
    result = invoke(env, "snapshot", check=False)
    assert result.returncode != 0 and result.stdout == "", "helper accepted missing private state root"


failed = 0
for test in (isolation, snapshot_is_read_only, interrupted_mutation, sandbox_context_required):
    try:
        test()
        print("PASS:", test.__name__)
    except Exception as error:
        failed += 1
        print("FAIL:", test.__name__, str(error))
sys.exit(bool(failed))
PY
