#!/usr/bin/env bash
# Managed launcher uses stable installed ownership and never retries failed owners.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export PYTHONDONTWRITEBYTECODE=1
[[ -x "$repo_root/integrations/session/bin/omarchy-launch-screensaver" ]] || {
  echo 'managed screensaver shim is missing'
  exit 1
}
stable="$HOME/.config/omarchy/themes/aranea"
mkdir -p "$stable" "$HOME/.local/bin" "$HOME/.local/state/omarchy/current" "$ARANEA_TEST_SANDBOX/stock/bin"
cp -a "$repo_root/scripts" "$repo_root/integrations" "$repo_root/tools" "$repo_root/branding" "$repo_root/theme-manifest.toml" "$stable/"
export OMARCHY_PATH="$ARANEA_TEST_SANDBOX/stock"
cat >"$OMARCHY_PATH/bin/omarchy-launch-screensaver" <<'STUB'
#!/bin/sh
printf 'stock:%s\n' "$*" >> "$ARANEA_TEST_SANDBOX/dispatch"
STUB
chmod +x "$OMARCHY_PATH/bin/omarchy-launch-screensaver"
owner="$stable/scripts/aranea-screensaver"
mv "$owner" "$owner.real"
cat >"$owner" <<'STUB'
#!/bin/sh
printf 'owner:%s\n' "$*" >> "$ARANEA_TEST_SANDBOX/dispatch"
exit "${OWNER_RC:-0}"
STUB
chmod +x "$owner"
printf 'mine\n' >"$HOME/.local/bin/omarchy-launch-screensaver"
"$stable/scripts/install-integration" session --yes >/dev/null
shim="$HOME/.local/bin/omarchy-launch-screensaver"
[[ "$(readlink "$shim")" == "$stable/integrations/session/bin/omarchy-launch-screensaver" ]]
grep -Fqx "$shim" "$XDG_STATE_HOME/aranea/managed-files"
printf 'aranea\n' >"$HOME/.local/state/omarchy/current/theme.name"
"$shim"
"$shim" force
[[ "$(cat "$ARANEA_TEST_SANDBOX/dispatch")" == $'owner:start\nowner:start force' ]]
# Locked, busy and runtime failures preserve the owner error with no stock retry.
for code in 1 7 23; do
  rc=0
  OWNER_RC="$code" "$shim" || rc=$?
  [[ "$rc" == "$code" ]]
done
if grep -q stock "$ARANEA_TEST_SANDBOX/dispatch"; then
  echo 'failed owner unexpectedly retried stock' >&2
  exit 1
fi
# Inactive/classic and absent owner have fixed packaged fallback.
printf 'tokyo-night\n' >"$HOME/.local/state/omarchy/current/theme.name"
"$shim" force
printf 'aranea\n' >"$HOME/.local/state/omarchy/current/theme.name"
chmod -x "$owner"
"$shim"
[[ "$(tail -2 "$ARANEA_TEST_SANDBOX/dispatch")" == $'stock:force\nstock:' ]]
chmod +x "$owner"
# A recursive packaged path is rejected instead of executing this shim again.
ln -sf "$shim" "$OMARCHY_PATH/bin/omarchy-launch-screensaver"
printf 'other\n' >"$HOME/.local/state/omarchy/current/theme.name"
if "$shim" >/dev/null 2>&1; then
  echo 'recursive stock path accepted'
  exit 1
fi
# Ownership restoration and edited user targets use the existing ledger lifecycle.
"$stable/scripts/aranea-integrations" deactivate session >/dev/null
[[ ! -L "$shim" && "$(cat "$shim")" == mine ]]
"$stable/scripts/aranea-integrations" activate session --yes >/dev/null
rm "$shim"
printf 'customized\n' >"$shim"
"$stable/scripts/aranea-integrations" activate session --yes >/dev/null
[[ ! -L "$shim" && "$(cat "$shim")" == customized ]]
"$stable/scripts/aranea-integrations" deactivate session >/dev/null
[[ "$(cat "$shim")" == customized ]]
# Real status executes the same bash -lc resolver as upstream idle without PATH edits.
rm "$shim"
"$stable/scripts/install-integration" session --yes >/dev/null
mv "$owner.real" "$owner"
printf 'export PATH="%s:%s"\n' "$HOME/.local/bin" "$PATH" >"$HOME/.bash_profile"
"$owner" status --json >"$TMPDIR/status.json"
jq -e '.integration.installed and .integration.reachable and (.integration.resolvedCommand|endswith("/.local/bin/omarchy-launch-screensaver"))' "$TMPDIR/status.json" >/dev/null
printf 'export PATH=/usr/bin:/bin\n' >"$HOME/.bash_profile"
"$owner" status --json >"$TMPDIR/unreachable.json"
jq -e '.integration.installed and (.integration.reachable|not) and (.integration.error|type=="string")' "$TMPDIR/unreachable.json" >/dev/null
# Uninstall the owned shim and keep restored predecessor semantics.
"$stable/scripts/uninstall.sh" --yes --scope integration >/dev/null
[[ ! -L "$shim" ]]
echo 'managed automatic activation contracts passed'
