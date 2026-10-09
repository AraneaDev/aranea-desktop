#!/usr/bin/env bash
# Resume argv and executable lookup exercise only trapped sandbox executables.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
launcher="$repo_root/scripts/aranea-agent-launch"
[[ -x "$launcher" ]] || {
  echo 'Missing fixed agent resume launcher'
  exit 1
}
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/checkout"
checkout="$ARANEA_TEST_SANDBOX/checkout"
cat >"$ARANEA_TEST_SANDBOX/bin/kitty" <<'APP'
#!/bin/bash
printf '%s\n' "$@" > "$ARANEA_TEST_SANDBOX/argv"
exec /usr/bin/sleep 10
APP
cp "$ARANEA_TEST_SANDBOX/bin/kitty" "$checkout/claude"
cp "$ARANEA_TEST_SANDBOX/bin/kitty" "$ARANEA_TEST_SANDBOX/bin/claude"
chmod +x "$ARANEA_TEST_SANDBOX/bin/kitty" "$ARANEA_TEST_SANDBOX/bin/claude" "$checkout/claude"
export PATH="$checkout:$ARANEA_TEST_SANDBOX/bin:$PATH"
request=$(jq -cn --arg cwd "$checkout" '{cwd:$cwd,provider:"claude",providerSessionId:"12345678-1234-1234-1234-123456789abc",terminalId:"kitty",token:"dev.aranea.activity.fixture"}')
result=$("$launcher" <<<"$request")
pid=$(jq -r .identity.pid <<<"$result")
sandbox_on_exit "kill -- -$pid 2>/dev/null || true"
jq -e '.ok and .status=="accepted"' <<<"$result" >/dev/null
for ((i = 0; i < 50; i++)); do
  [[ ! -f "$ARANEA_TEST_SANDBOX/argv" ]] || break
  sleep .02
done
[[ $(sed -n '5p' "$ARANEA_TEST_SANDBOX/argv") == "$ARANEA_TEST_SANDBOX/bin/claude" ]]
[[ $(sed -n '6p' "$ARANEA_TEST_SANDBOX/argv") == --resume ]]
for id in --help 'x;touch nope' named-session; do
  if result=$(jq --arg id "$id" '.providerSessionId=$id' <<<"$request" | "$launcher"); then exit 1; fi
  jq -e '.code=="RESUME_UNAVAILABLE"' <<<"$result" >/dev/null
done
if jq '.provider="codex"' <<<"$request" | "$launcher" >/dev/null; then exit 1; fi
rm "$ARANEA_TEST_SANDBOX/bin/claude"
ln -s "$checkout/claude" "$ARANEA_TEST_SANDBOX/bin/claude"
if result=$("$launcher" <<<"$request"); then exit 1; fi
jq -e '.code=="TOOL_MISSING"' <<<"$result" >/dev/null
echo 'PASS fixed resume argv, option rejection, detached acceptance and checkout executable exclusion'
