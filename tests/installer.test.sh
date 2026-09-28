#!/usr/bin/env bash
# Contract for the root installer TUI and its JSON-backed operation routing.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

"$repo_root/installer" --help | grep -Fq 'Aranea Installer'

fake_bin="$ARANEA_TEST_SANDBOX/fake-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/gum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  choose)
    count_file="${ARANEA_TEST_SANDBOX}/gum-choose-count"
    count=0
    [[ -f "$count_file" ]] && count="$(<"$count_file")"
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    if ((count == 2)); then
      printf '%s\n' 'minimal Core and GTK experience only'
    else
      printf '%s\n' 'install Install or update Aranea'
    fi
    ;;
  confirm) exit 0 ;;
  style) shift; printf '%s\n' "$*" ;;
  input) printf '%s\n' 'Adwaita' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$fake_bin/gum"

PATH="$fake_bin:$PATH" OMARCHY_INSTALLER_TEST=1 \
  "$repo_root/installer" --dry-run >"$ARANEA_TEST_SANDBOX/tui-output"
grep -Fq 'dry-run completed' "$ARANEA_TEST_SANDBOX/tui-output"
grep -Fq 'profile: minimal' "$ARANEA_TEST_SANDBOX/tui-output"

missing_status=0
missing_bin="$ARANEA_TEST_SANDBOX/missing-bin"
mkdir -p "$missing_bin"
ln -s /usr/bin/jq "$missing_bin/jq"
ARANEA_INSTALLER_GUM_BIN=aranea-missing-gum \
  PATH="$missing_bin:/usr/bin:/bin" /bin/bash "$repo_root/installer" >/dev/null \
  2>"$ARANEA_TEST_SANDBOX/missing-gum" || missing_status=$?
[[ "$missing_status" == 4 ]]
grep -Fq 'gum is required' "$ARANEA_TEST_SANDBOX/missing-gum"

echo "installer tui contract passed"
