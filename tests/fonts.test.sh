#!/usr/bin/env bash
# Real font preference owner: validation, atomic persistence and safe fallback.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
ctl="$repo_root/scripts/aranea-fonts"
cat >"$ARANEA_TEST_SANDBOX/fc-list" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *spacing=100* ]]; then
  printf '%s\n' 'Example Mono' 'Second Mono'
else
  printf '%s\n' 'Example Sans' 'Example Mono' 'Second Mono' 'Example Sans'
fi
STUB
chmod +x "$ARANEA_TEST_SANDBOX/fc-list"
export PATH="$ARANEA_TEST_SANDBOX:$PATH"
config="$XDG_CONFIG_HOME/aranea/fonts.json"
"$ctl" status --json | jq -e '.availability == "available" and .uiFamily == "" and .technicalFamily == "" and (.families | length == 3)' >/dev/null
test ! -e "$config"
"$ctl" configure 'Example Sans' 'Example Mono'
"$ctl" status --json | jq -e '.uiFamily == "Example Sans" and .technicalFamily == "Example Mono"' >/dev/null
cp "$config" "$ARANEA_TEST_SANDBOX/before"
if "$ctl" configure 'Unknown Family' 'Example Mono'; then exit 1; fi
cmp "$config" "$ARANEA_TEST_SANDBOX/before"
if "$ctl" configure 'Example Sans' 'Example Sans'; then exit 1; fi
cmp "$config" "$ARANEA_TEST_SANDBOX/before"
if "$ctl" configure 'Example Sans' 'Example Mono' extra; then exit 1; fi
cmp "$config" "$ARANEA_TEST_SANDBOX/before"
"$ctl" configure '' ''
"$ctl" status --json | jq -e '.uiFamily == "" and .technicalFamily == ""' >/dev/null
printf '{"uiFamily":42}' >"$config"
if "$ctl" status --json >"$ARANEA_TEST_SANDBOX/bad.json"; then exit 1; fi
jq -e '.availability == "unavailable" and .uiFamily == "" and .technicalFamily == ""' "$ARANEA_TEST_SANDBOX/bad.json" >/dev/null
# Explicit reset repairs a damaged preference without touching other config.
printf untouched >"$XDG_CONFIG_HOME/aranea/other"
"$ctl" configure '' ''
[[ "$(cat "$XDG_CONFIG_HOME/aranea/other")" == untouched ]]
"$ctl" status --json | jq -e '.availability == "available"' >/dev/null
