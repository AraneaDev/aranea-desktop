#!/usr/bin/env bash
# Real inert command processes must preserve fixture state when a writer fails.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
python3 - "$repo_root" <<'PY'
import json
import os
from pathlib import Path
import resource
import subprocess
import sys

root = Path(os.environ["ARANEA_TEST_SANDBOX"])
command = root / "network-fixture-command" / "network-fixture"
command.parent.mkdir()
command.symlink_to(Path(sys.argv[1]) / "tests/qml/fixtures/network-command.py")
state_path = root / "network-fixture/state.json"


def run(*args, limit=None):
    def restrict_writes():
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        resource.setrlimit(resource.RLIMIT_FSIZE, (limit, limit))
    return subprocess.run(
        [str(command), *args], text=True, capture_output=True,
        preexec_fn=restrict_writes if limit is not None else None,
        check=False,
    )


initial = run("configure", json.dumps({"response": "retained result"}))
assert initial.returncode == 0, initial.stderr
before = state_path.read_bytes()
failed = run("configure", json.dumps({"response": "incomplete result"}), limit=1)
assert failed.returncode != 0, "write limit did not interrupt the writer"
assert state_path.read_bytes() == before, "interrupted fixture write corrupted committed state"
assert not list(state_path.parent.glob(".state-*")), "failed writer left unpublished state behind"
print("PASS interrupted network fixture writes preserve the last complete snapshot")

snapshot = run("snapshot", limit=0)
assert snapshot.returncode == 0, snapshot.stderr
assert json.loads(snapshot.stdout)["response"] == "retained result"
assert state_path.read_bytes() == before
print("PASS network fixture snapshots require no state write")
PY
