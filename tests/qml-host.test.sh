#!/usr/bin/env bash
# Native acceptance preflight skips unavailable hosts unless strict mode requires them.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
# Exercise the shared preflight in its own subshell without starting any QML host.
probe() {
  (
    sandbox_inherited[ARANEA_QML_SHELL_DIR]=$1
    sandbox_inherited[ARANEA_CHECK_REQUIRE_ALL]=$2
    source "$repo_root/tests/lib/qml-host.sh"
    require_qml_host
    printf 'HOST:%s\nSHELL:%s\n' "$quickshell_bin" "$qml_shell_dir"
  )
}
probe "$TMPDIR/missing shell" '' >"$TMPDIR/optional"
grep -q '^SKIP:' "$TMPDIR/optional"
if grep -q '^HOST:' "$TMPDIR/optional"; then
  echo 'FAIL missing QML host continued into native execution'
  exit 1
fi
if probe "$TMPDIR/missing shell" 1 >"$TMPDIR/required"; then
  echo 'FAIL strict preflight accepted a missing QML host'
  exit 1
fi
grep -q '^SKIP:' "$TMPDIR/required"
mkdir -p "$TMPDIR/bin" "$TMPDIR/pinned shell/Commons" "$TMPDIR/pinned shell/Ui"
ln -s /bin/false "$TMPDIR/bin/quickshell"
touch "$TMPDIR/pinned shell/Commons/qmldir" "$TMPDIR/pinned shell/Ui/qmldir"
export PATH="$repo_root/tests/guard-bin:$TMPDIR/bin:$PATH"
probe "$TMPDIR/pinned shell" 1 >"$TMPDIR/present"
grep -Fxq "HOST:$TMPDIR/bin/quickshell" "$TMPDIR/present"
grep -Fxq "SHELL:$TMPDIR/pinned shell" "$TMPDIR/present"
echo 'PASS optional skip, strict refusal and literal pinned host resolution'
