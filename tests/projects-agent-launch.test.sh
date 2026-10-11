#!/usr/bin/env bash
# Fixed argv, canonical provider lookup and refusals exercise the real project guard.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
launcher="$repo_root/scripts/aranea-project-launch"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/checkout/nested"
checkout="$ARANEA_TEST_SANDBOX/checkout"
tool_bin="$ARANEA_TEST_SANDBOX/bin"
token=dev.aranea.project_fixture_agent
session_id=12345678-1234-1234-1234-123456789abc
# Launcher PATH never inherits host provider installs. Only bash is needed for
# its env shebang; bootstrap utilities and the sleeping stub use absolute paths.
ln -s /bin/bash "$tool_bin/bash"
cat >"$tool_bin/kitty" <<'APP'
#!/bin/bash
printf '%s\n' "$@" > "$ARANEA_TEST_SANDBOX/argv"
printf '%s\n' "$PWD" > "$ARANEA_TEST_SANDBOX/cwd"
exec /usr/bin/sleep 10
APP
chmod +x "$tool_bin/kitty"
for tool in alacritty foot ghostty claude codex nvim; do
  cp "$tool_bin/kitty" "$tool_bin/$tool"
done
launch_path="$tool_bin"
accepted=0
refused=0

# These hand-written fixtures pin terminal option names and execute separators.
terminal_base() {
  case "$1" in
    kitty) jq -cn --arg cwd "$checkout" --arg token "$token" '["kitty","--class",$token,"--directory",$cwd]' ;;
    alacritty) jq -cn --arg cwd "$checkout" --arg token "$token" '["alacritty","--class",$token,"--working-directory",$cwd,"--command"]' ;;
    foot) jq -cn --arg cwd "$checkout" --arg token "$token" '["foot","--app-id",$token,"--working-directory",$cwd]' ;;
    ghostty) jq -cn --arg cwd "$checkout" --arg token "$token" '["ghostty","--class="+$token,"--gtk-single-instance=false","--working-directory="+$cwd,"-e"]' ;;
  esac
}

# Assert detached acceptance and the complete argv delivered to the terminal.
launch() {
  local argv=$1 expected=$2 result pid actual
  rm -f "$ARANEA_TEST_SANDBOX/argv" "$ARANEA_TEST_SANDBOX/cwd"
  result=$(jq -cn --arg cwd "$checkout" --argjson argv "$argv" '{argv:$argv,cwd:$cwd}' | PATH="$launch_path" "$launcher") || {
    echo "Expected acceptance for $argv, got: $result"
    exit 1
  }
  jq -e '.ok and .status=="accepted" and (.identity.pid>0) and (.identity.startTime|test("^[0-9]+$"))' <<<"$result" >/dev/null
  pid=$(jq -r .identity.pid <<<"$result")
  sandbox_on_exit "kill -- -$pid 2>/dev/null || true"
  for ((i = 0; i < 50; i++)); do
    [[ ! -f "$ARANEA_TEST_SANDBOX/cwd" ]] || break
    sleep .02
  done
  actual=$(jq -Rsc 'split("\n")[:-1]' "$ARANEA_TEST_SANDBOX/argv")
  [[ "$actual" == "$expected" && $(<"$ARANEA_TEST_SANDBOX/cwd") == "$checkout" ]] || {
    echo "Expected terminal argv $expected, got: $actual"
    exit 1
  }
  kill -- "-$pid" 2>/dev/null || true
  accepted=$((accepted + 1))
}

# Rejections must precede terminal invocation, with the exact failure envelope.
refuse() {
  local argv=$1 code=$2 rc=0 out
  rm -f "$ARANEA_TEST_SANDBOX/argv"
  out=$(jq -cn --arg cwd "$checkout" --argjson argv "$argv" '{argv:$argv,cwd:$cwd}' | PATH="$launch_path" "$launcher") || rc=$?
  [[ $rc != 0 ]] && jq -e --arg code "$code" '.ok==false and .status=="failed" and .code==$code' <<<"$out" >/dev/null && [[ ! -f "$ARANEA_TEST_SANDBOX/argv" ]] || {
    echo "Expected $code without launch for $argv, got: $out"
    exit 1
  }
  refused=$((refused + 1))
}

for terminal in kitty alacritty foot ghostty; do
  base=$(terminal_base "$terminal")
  for provider in claude codex; do
    if [[ "$provider" == claude ]]; then
      argv=$(jq -c '.+["claude"]' <<<"$base")
      expected=$(jq -c --arg bin "$tool_bin/claude" '.[1:]+[$bin]' <<<"$base")
    else
      argv=$(jq -c --arg cwd "$checkout" '.+["codex","--cd",$cwd]' <<<"$base")
      expected=$(jq -c --arg bin "$tool_bin/codex" --arg cwd "$checkout" '.[1:]+[$bin,"--cd",$cwd]' <<<"$base")
    fi
    launch "$argv" "$expected"
    refuse "$(jq -c '.+["--extra"]' <<<"$argv")" INVALID_LAUNCH
  done
  refuse "$(jq -c '.+["claude","--dangerously-skip-permissions"]' <<<"$base")" INVALID_LAUNCH
  refuse "$(jq -c '.+["codex","--cd","/elsewhere"]' <<<"$base")" INVALID_LAUNCH
  refuse "$(jq -c '.+["gemini"]' <<<"$base")" INVALID_LAUNCH
  refuse "$(jq -c '.+["codex"]' <<<"$base")" INVALID_LAUNCH
  # The previously supported editor and both resume forms keep exact argv.
  launch "$(jq -c --arg cwd "$checkout" '.+["nvim","--",$cwd]' <<<"$base")" "$(jq -c --arg bin "$tool_bin/nvim" --arg cwd "$checkout" '.[1:]+[$bin,"--",$cwd]' <<<"$base")"
  launch "$(jq -c --arg id "$session_id" '.+["claude","--resume",$id]' <<<"$base")" "$(jq -c --arg bin "$tool_bin/claude" --arg id "$session_id" '.[1:]+[$bin,"--resume",$id]' <<<"$base")"
  launch "$(jq -c --arg id "$session_id" --arg cwd "$checkout" '.+["codex","resume",$id,"--cd",$cwd]' <<<"$base")" "$(jq -c --arg bin "$tool_bin/codex" --arg id "$session_id" --arg cwd "$checkout" '.[1:]+[$bin,"resume",$id,"--cd",$cwd]' <<<"$base")"
done

# Canonical resolution accepts an outside symlink, but excludes checkout PATH
# entries (absolute, relative, nested, and aliases) and symlink targets.
base=$(terminal_base kitty)
for provider in claude codex; do
  if [[ "$provider" == claude ]]; then
    argv=$(jq -c '.+["claude"]' <<<"$base")
    expected=$(jq -c --arg bin "$tool_bin/real-claude" '.[1:]+[$bin]' <<<"$base")
  else
    argv=$(jq -c --arg cwd "$checkout" '.+["codex","--cd",$cwd]' <<<"$base")
    expected=$(jq -c --arg bin "$tool_bin/real-codex" --arg cwd "$checkout" '.[1:]+[$bin,"--cd",$cwd]' <<<"$base")
  fi
  mv "$tool_bin/$provider" "$tool_bin/real-$provider"
  ln -s "$tool_bin/real-$provider" "$tool_bin/$provider"
  launch "$argv" "$expected"
  rm "$tool_bin/$provider"
  mv "$tool_bin/real-$provider" "$checkout/nested/$provider"
  cp "$checkout/nested/$provider" "$checkout/$provider"
  ln -s "$checkout" "$ARANEA_TEST_SANDBOX/checkout-alias"
  launch_path=".:$checkout:$checkout/nested:$ARANEA_TEST_SANDBOX/checkout-alias:$tool_bin"
  cd "$checkout"
  refuse "$argv" TOOL_MISSING
  ln -s "$checkout/nested/$provider" "$tool_bin/$provider"
  refuse "$argv" TOOL_MISSING
  rm "$tool_bin/$provider" "$ARANEA_TEST_SANDBOX/checkout-alias"
  mv "$checkout/nested/$provider" "$tool_bin/$provider"
  launch_path="$tool_bin"
done
echo "PASS $accepted accepted launches, $refused refusals: all terminal/provider shapes, existing editor/resume shapes and canonical safe PATH"
