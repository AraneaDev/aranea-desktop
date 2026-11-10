#!/usr/bin/env bash
# A guard-only keyboard tool and failed compositor must never pass strict CI.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
mkdir -p "$TMPDIR/bin" "$TMPDIR/shell/Commons" "$TMPDIR/shell/Ui"
touch "$TMPDIR/shell/Commons/qmldir" "$TMPDIR/shell/Ui/qmldir"
# Minimal executable search path deliberately excludes the real wtype.
for dep in bash dirname mktemp grep mkdir chmod cp rm cat find sleep python3; do
  ln -s "$(command -v "$dep")" "$TMPDIR/bin/$dep"
done
for dep in quickshell sway swaymsg setpriv dbus-run-session; do
  ln -s /bin/false "$TMPDIR/bin/$dep"
done
# Execute the complete runner with controlled host and executable availability.
probe() {
  PATH="$TMPDIR/bin" ARANEA_QML_SHELL_DIR="$TMPDIR/shell" ARANEA_CHECK_REQUIRE_ALL="$1" \
    bash "$repo_root/tests/native-notifications.test.sh"
}
probe '' >"$TMPDIR/optional.log" 2>&1
grep -q 'SKIP: native notifications needs real wtype' "$TMPDIR/optional.log"
if probe 1 >"$TMPDIR/strict.log" 2>&1; then
  echo 'FAIL: strict native acceptance accepted guard-only wtype'
  exit 1
fi
grep -q 'SKIP: native notifications needs real wtype' "$TMPDIR/strict.log"
# Once preflight is satisfied, a failed backend must fail, never report a skip.
ln -s /bin/false "$TMPDIR/bin/wtype"
ln -s "$(command -v sed)" "$TMPDIR/bin/sed"
ln -s "$(command -v ln)" "$TMPDIR/bin/ln"
ln -s "$(command -v setsid)" "$TMPDIR/bin/setsid"
if probe 1 >"$TMPDIR/backend.log" 2>&1; then
  echo 'FAIL: strict native acceptance accepted a failed compositor'
  exit 1
fi
if grep -q 'SKIP:' "$TMPDIR/backend.log"; then
  cat "$TMPDIR/backend.log"
  exit 1
fi
grep -q 'FAIL: private compositor did not expose a Wayland socket' "$TMPDIR/backend.log"
echo 'PASS: guard-only wtype skips normally, fails strict; backend failure fails strict'
