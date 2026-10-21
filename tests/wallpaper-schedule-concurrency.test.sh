#!/usr/bin/env bash
# A failed schedule mutation cannot roll back a queued command's save.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/tests/lib/sandbox.sh"
ARANEA_TEST_REAL_FLOCK="$(command -v flock)"
export ARANEA_TEST_REAL_FLOCK
python3 - "$repo_root" <<'PYTHON'
import json
import os
from pathlib import Path
import subprocess
import sys
import time

repo = Path(sys.argv[1])
root = Path(os.environ["ARANEA_TEST_SANDBOX"])
bin_dir = root / "bin"
bin_dir.mkdir()
flock = bin_dir / "flock"
flock.write_text('''#!/usr/bin/env bash
if [[ ${SCHEDULE_ROLE:-} == B ]]; then
  if "$ARANEA_TEST_REAL_FLOCK" -n "$@"; then
    touch "$SCHEDULE_RACE/b-uncontended"
  fi
  touch "$SCHEDULE_RACE/b-lock"
fi
exec "$ARANEA_TEST_REAL_FLOCK" "$@"
''')
flock.chmod(0o755)
systemctl = bin_dir / "systemctl"
systemctl.write_text('''#!/usr/bin/env bash
if [[ ${SCHEDULE_ROLE:-} == B ]]; then touch "$SCHEDULE_RACE/b-runtime"; fi
case "$2" in
  is-enabled) echo enabled ;;
  is-active) echo active ;;
  daemon-reload)
    if [[ ${SCHEDULE_ROLE:-} == A && ! -e "$SCHEDULE_RACE/failed" ]]; then
      touch "$SCHEDULE_RACE/paused"
      while [[ ! -e "$SCHEDULE_RACE/release" ]]; do sleep 0.02; done
      touch "$SCHEDULE_RACE/failed"
      exit 1
    fi
    ;;
esac
''')
systemctl.chmod(0o755)
ctl = str(repo / "scripts/aranea-wallpaper")


def configure(hour):
    return ["configure", "--entries", json.dumps([{"time": hour, "wallpaper": "day"}])]


def wait_for(predicate, message):
    deadline = time.monotonic() + 10
    while not predicate():
        assert time.monotonic() < deadline, message
        time.sleep(0.02)


failures = []
for label, first, second, expected_time, expected_mode in [
    ("configure-configure", configure("07:00"), configure("08:00"), "08:00", "on"),
    # on must load the restored config after acquiring the lock, rather than
    # saving A's uncommitted 07:00 entries after A rolls them back.
    ("configure-on", configure("07:00"), ["on"], "06:00", "on"),
    ("configure-off", configure("07:00"), ["off"], "06:00", "off"),
    ("off-configure", ["off"], configure("08:00"), "08:00", "on"),
]:
    race = root / label
    race.mkdir()
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
               ARANEA_CONFIG_HOME=str(race / "config"),
               ARANEA_STATE_ROOT=str(race / "state"),
               ARANEA_SYSTEMD_USER_DIR=str(race / "units"),
               ARANEA_SYSTEMCTL=str(systemctl), SCHEDULE_RACE=str(race))
    config = race / "config/aranea/wallpaper-schedule.conf"
    timer = race / "units/aranea-wallpaper-day-night.timer"
    service = race / "units/aranea-wallpaper-day-night.service"
    subprocess.run([ctl, "schedule", *configure("06:00")], env=env, check=True,
                   capture_output=True)
    subprocess.run([ctl, "schedule", "on"], env=env, check=True, capture_output=True)
    a = subprocess.Popen([ctl, "schedule", *first], env=dict(env, SCHEDULE_ROLE="A"),
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    b = None
    try:
        wait_for(lambda: (race / "paused").exists(), f"{label}: A never paused")
        b = subprocess.Popen([ctl, "schedule", *second], env=dict(env, SCHEDULE_ROLE="B"),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        wait_for(lambda: (race / "b-lock").exists() or b.poll() is not None,
                 f"{label}: B never reached the mutation lock")
        # A remains paused here. Do not wait for B to finish before releasing A:
        # a correctly serialized B can only finish after A's rollback completes.
        assert b.poll() is None, f"{label}: B completed during A's transaction"
        assert not (race / "b-uncontended").exists(), f"{label}: B did not share A's lock"
        assert not (race / "b-runtime").exists(), f"{label}: B read runtime before locking"
        (race / "release").touch()
        a_out, a_error = a.communicate(timeout=10)
        b_out, b_error = b.communicate(timeout=10)
        assert a.returncode != 0, f"{label}: A unexpectedly succeeded: {a_out} {a_error}"
        assert b.returncode == 0, f"{label}: B failed: {b_out} {b_error}"
        assert json.loads(config.read_text())["entries"] == [
            {"time": expected_time, "wallpaper": "day"}
        ], f"{label}: committed schedule was overwritten or loaded before the lock"
        assert (race / "state/wallpaper-schedule").read_text() == expected_mode
        if expected_mode == "on":
            assert f"OnCalendar=*-*-* {expected_time}:00\n" in timer.read_text()
            assert service.is_file()
        else:
            assert not timer.exists() and not service.exists()
    except AssertionError as error:
        failures.append(str(error))
    finally:
        (race / "release").touch()
        for process in (a, b):
            if process is not None:
                try:
                    process.communicate(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate()

assert not failures, "\n".join(failures)
print("concurrent wallpaper schedule rollback contract passed")
PYTHON
