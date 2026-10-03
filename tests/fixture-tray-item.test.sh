#!/usr/bin/env bash
# Contract for tools/fixture-tray-item: its dbusmenu layout matches the
# brief (separators, a submenu, a checkbox, a disabled entry, a radio and
# "Quit fixture"), a click toggles state with a revision bump, and it exits
# cleanly on SIGTERM. Runs only on a private bus (dbus-run-session). Skips
# (exit 0; 1 with ARANEA_CHECK_REQUIRE_ALL=1) without dbus-run-session,
# gdbus or python3's dbus/gi modules.
# Usage: tests/fixture-tray-item.test.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# Keeps a stray tools/__pycache__ out of the repo's working tree.
export PYTHONDONTWRITEBYTECODE=1

require_all="$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)"

missing=""
command -v dbus-run-session >/dev/null || missing="dbus-run-session"
command -v gdbus >/dev/null || missing="${missing:+$missing, }gdbus"
python3 -c 'import dbus, dbus.service; from dbus.mainloop.glib import DBusGMainLoop; from gi.repository import GLib' >/dev/null 2>&1 ||
  missing="${missing:+$missing, }python3's dbus/gi modules"

if [[ -n "$missing" ]]; then
  echo "SKIP: fixture tray item test needs $missing"
  [[ "$require_all" == 1 ]] && exit 1
  exit 0
fi

## Compiles the fixture (a syntax/py_compile check), with the cache file
# kept out of the repo (py_compile always writes one, ignoring
# PYTHONDONTWRITEBYTECODE).
python3 - "$repo_root/tools/fixture-tray-item" <<'PYEOF2' || exit 1
"""Compiles argv[1] to a throwaway temp file, as a py_compile syntax check
that leaves nothing behind in the repository.
"""

import os
import py_compile
import sys
import tempfile

target = sys.argv[1]
with tempfile.TemporaryDirectory() as tmp_dir:
    py_compile.compile(target, cfile=os.path.join(tmp_dir, "out.pyc"), doraise=True)
PYEOF2

checker="$ARANEA_TEST_SANDBOX/check_fixture.py"
cat >"$checker" <<'PYEOF'
"""Fixture tray item test driver: asserts the dbusmenu layout, flags and
Event handling tools/fixture-tray-item exports. Called by
tests/fixture-tray-item.test.sh on a private bus.

Usage: check_fixture.py DEST OUTFILE
"""

import sys
import time

import dbus

NO_PROPS = dbus.Array([], signature="s")


def connect(dest, timeout):
    """Returns (bus, dbusmenu Interface) for DEST, retrying until TIMEOUT
    seconds while the fixture finishes registering.
    """
    bus = dbus.SessionBus()
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            menu = dbus.Interface(bus.get_object(dest, "/MenuBar"), "com.canonical.dbusmenu")
            menu.GetLayout(0, 0, NO_PROPS)
            return bus, menu
        except dbus.exceptions.DBusException as error:
            last_error = error
            time.sleep(0.1)
    raise SystemExit(f"fixture never came up on the bus: {last_error}")


def fail(message):
    """Prints MESSAGE and exits the checker with a non-zero status."""
    print(f"FAIL: {message}")
    raise SystemExit(1)


def expect(condition, message):
    """Fails with MESSAGE unless CONDITION is true."""
    if not condition:
        fail(message)


def by_label(children, label):
    """Returns the first (id, properties, children) struct in CHILDREN
    whose label is LABEL, failing if there is none.
    """
    for child in children:
        _id, props, _kids = child
        if props.get("label") == label:
            return child
    fail(f'no entry labelled "{label}"')
    return None


def main():
    """Runs the fixture's dbusmenu contract against DEST (argv[1]), reading
    its captured stdout from OUTFILE (argv[2]).
    """
    dest, outfile = sys.argv[1], sys.argv[2]
    bus, menu = connect(dest, timeout=5)

    item = dbus.Interface(bus.get_object(dest, "/StatusNotifierItem"), "org.freedesktop.DBus.Properties")
    expect(bool(item.Get("org.kde.StatusNotifierItem", "ItemIsMenu")), "ItemIsMenu must be true (left click opens the menu)")

    revision, (root_id, _root_props, children) = menu.GetLayout(0, -1, NO_PROPS)
    expect(root_id == 0, "the root id must be 0")
    expect(len(children) == 7, f"expected 7 root entries, got {len(children)}")
    expect(children[0][1].get("type") == "separator", "the leading entry must be a separator")
    expect(children[-2][1].get("type") == "separator", "entry 6 must be a separator")
    sep_count = sum(1 for (_id, props, _kids) in children if props.get("type") == "separator")
    expect(sep_count == 2, f"expected 2 separators, got {sep_count}")

    open_item = by_label(children, "Open Courier")
    expect(bool(open_item[1].get("enabled", True)), "Open Courier must be enabled")

    send_file = by_label(children, "Send a file")
    expect(send_file[1].get("children-display") == "submenu", "Send a file must be a submenu")
    sub_children = send_file[2]
    expect(len(sub_children) == 3, f"expected 3 children under Send a file, got {len(sub_children)}")
    by_label(sub_children, "To nearby device…")
    by_label(sub_children, "Share a link…")
    fast_mode = by_label(sub_children, "Fast mode")
    expect(fast_mode[1].get("toggle-type") == "radio", "Fast mode must be a radio entry")
    expect(int(fast_mode[1].get("toggle-state")) == 1, "Fast mode must start on")

    checkbox = by_label(children, "_Start minimised")
    expect(checkbox[1].get("toggle-type") == "checkmark", "_Start minimised must be a checkbox")
    expect(int(checkbox[1].get("toggle-state")) == 0, "_Start minimised must start off")

    receive = by_label(children, "Receive")
    expect(not bool(receive[1].get("enabled", True)), "Receive must be disabled")

    quit_item = by_label(children, "Quit fixture")

    expect(not bool(menu.AboutToShow(0)), "AboutToShow must report no update needed")

    checkbox_id = int(checkbox[0])
    menu.Event(checkbox_id, "clicked", dbus.Int32(0, variant_level=1), dbus.UInt32(0))
    time.sleep(0.2)

    new_revision, (_rid, _rprops, new_children) = menu.GetLayout(0, -1, NO_PROPS)
    expect(new_revision > revision, "the revision must bump after a toggle")
    new_checkbox = by_label(new_children, "_Start minimised")
    expect(int(new_checkbox[1].get("toggle-state")) == 1, "the checkbox must have toggled on")

    with open(outfile, encoding="utf-8") as handle:
        printed = handle.read()
    expect("fixture: clicked _Start minimised" in printed, 'the click must print "fixture: clicked _Start minimised"')

    group = menu.GetGroupProperties(dbus.Array([checkbox_id], signature="i"), NO_PROPS)
    expect(len(group) == 1 and int(group[0][0]) == checkbox_id, "GetGroupProperties must return the checkbox")
    expect(int(group[0][1].get("toggle-state")) == 1, "GetGroupProperties must reflect the toggled state")

    quit_id = int(quit_item[0])
    menu.Event(quit_id, "clicked", dbus.Int32(0, variant_level=1), dbus.UInt32(0))

    print("fixture dbusmenu contract passed")


if __name__ == "__main__":
    main()
PYEOF

out="$ARANEA_TEST_SANDBOX/fixture.out"
export ARANEA_FIXTURE_BIN="$repo_root/tools/fixture-tray-item"
export ARANEA_FIXTURE_OUT="$out"
export ARANEA_FIXTURE_CHECKER="$checker"

# shellcheck disable=SC2016 # expanded by the inner bash's own environment, not here
dbus-run-session -- bash -c '
  set -uo pipefail
  "$ARANEA_FIXTURE_BIN" --name Courier --icon mail-send >"$ARANEA_FIXTURE_OUT" 2>"$ARANEA_FIXTURE_OUT.err" &
  pid=$!
  dest="org.kde.StatusNotifierItem-$pid-1"
  status=0
  python3 "$ARANEA_FIXTURE_CHECKER" "$dest" "$ARANEA_FIXTURE_OUT" || status=1
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  exit "$status"
'
main_status=$?

if ((main_status != 0)); then
  echo "--- fixture stdout ---" >&2
  cat "$out" >&2 2>/dev/null
  echo "--- fixture stderr ---" >&2
  cat "$out.err" >&2 2>/dev/null
  exit 1
fi

# "Quit fixture" must have stopped the process cleanly (no menu/property
# calls were refused once the Event handler scheduled the quit).
grep -Fq "fixture: clicked Quit fixture" "$out" || {
  echo "Quit fixture did not print its clicked line" >&2
  exit 1
}

# --- SIGTERM also shuts the fixture down cleanly, not just "Quit fixture" ---
# shellcheck disable=SC2016 # expanded by the inner bash's own environment, not here
dbus-run-session -- bash -c '
  set -uo pipefail
  "$ARANEA_FIXTURE_BIN" --name Syncbox >/dev/null 2>&1 &
  pid=$!
  sleep 0.5
  kill -TERM "$pid"
  wait "$pid"
'
sigterm_status=$?
if ((sigterm_status != 0)); then
  echo "fixture did not exit cleanly on SIGTERM (status $sigterm_status)" >&2
  exit 1
fi

echo "fixture tray item contract passed"
