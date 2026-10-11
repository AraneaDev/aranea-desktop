#!/usr/bin/env bash
# Tool discovery reads sandboxed defaults and never executes their contents.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
probe="$repo_root/scripts/aranea-project-tools"
[[ -x "$probe" ]] || {
  echo 'Expected executable project tools probe'
  exit 1
}
mkdir -p "$TMPDIR/bin" "$XDG_STATE_HOME/omarchy/defaults"
# Availability fixtures must never receive launch arguments.
for id in alacritty kitty foot ghostty code nvim claude codex; do
  cat >"$TMPDIR/bin/$id" <<'TOOL'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >>"$ARANEA_TEST_SANDBOX/forbidden-tool-calls"
exit 99
TOOL
  chmod +x "$TMPDIR/bin/$id"
done
export PATH="$TMPDIR/bin:$PATH"
printf 'code\n' >"$XDG_STATE_HOME/omarchy/defaults/editor"
printf '# ordered preferences\nunsupported.desktop\nkitty.desktop\nalacritty.desktop\n' >"$XDG_CONFIG_HOME/xdg-terminals.list"
"$probe" --json >"$TMPDIR/tools"
jq -e '.defaults == {editorId:"code",terminalId:"kitty"} and ([.terminals[].id] == ["alacritty","kitty","foot","ghostty"]) and ([.editors[].id] == ["code","nvim"]) and all(.terminals[]; .available and .supported) and all(.editors[]; .available and .supported)' "$TMPDIR/tools"
jq -e '[.agents[].id] == ["claude","codex"] and ([.agents[].label] == ["Claude Code","Codex"]) and all(.agents[]; .available and .supported)' "$TMPDIR/tools"
[[ ! -e "$ARANEA_TEST_SANDBOX/forbidden-tool-calls" ]]
# shellcheck disable=SC2016 # The shell fragment is deliberately inert fixture text.
printf '$(touch %s/EXECUTED); code\n' "$ARANEA_TEST_SANDBOX" >"$XDG_STATE_HOME/omarchy/defaults/editor"
"$probe" --json | jq -e '.defaults.editorId == null'
[[ ! -e "$ARANEA_TEST_SANDBOX/EXECUTED" ]]
printf '%s/code\n' "$TMPDIR/bin" >"$XDG_STATE_HOME/omarchy/defaults/editor"
"$probe" --json | jq -e '.defaults.editorId == "code"'
printf 'code\nnvim\n' >"$XDG_STATE_HOME/omarchy/defaults/editor"
"$probe" --json | jq -e '.defaults.editorId == null'
rm "$XDG_STATE_HOME/omarchy/defaults/editor" "$XDG_CONFIG_HOME/xdg-terminals.list"
"$probe" --json | jq -e '.defaults == {editorId:"nvim",terminalId:null}'
# A minimal isolated PATH exposes only utilities; no supported tools are installed.
mkdir "$TMPDIR/minimal"
ln -s "$(command -v jq)" "$TMPDIR/minimal/jq"
ln -s "$(command -v dirname)" "$TMPDIR/minimal/dirname"
ln -s "$(command -v realpath)" "$TMPDIR/minimal/realpath"
PATH="$TMPDIR/minimal" /bin/bash "$probe" --json | jq -e '.defaults == {editorId:null,terminalId:null} and .terminals == [] and .editors == [] and .agents == []'
# Relative entries (including aliases to absolute directories) cannot advertise tools.
mkdir -p "$TMPDIR/relative"
cp "$TMPDIR/bin/claude" "$TMPDIR/bin/code" "$TMPDIR/relative/"
cp "$TMPDIR/bin/claude" "$TMPDIR/bin/code" "$TMPDIR/"
cat >"$TMPDIR/relative/realpath" <<'TOOL'
#!/bin/bash
printf '%s\n' "$0 $*" >>"$ARANEA_TEST_SANDBOX/forbidden-tool-calls"
exec /usr/bin/realpath "$@"
TOOL
chmod +x "$TMPDIR/relative/realpath"
ln -s "$TMPDIR/relative" "$TMPDIR/relative-alias"
(
  cd "$TMPDIR"
  for lookup in 'relative' './relative' 'relative-alias' '.' ''; do
    PATH="$lookup:$TMPDIR/minimal" /bin/bash "$probe" --json |
      jq -e '.terminals == [] and .editors == [] and .agents == []'
  done
)
[[ ! -e "$ARANEA_TEST_SANDBOX/forbidden-tool-calls" ]]
# Absolute directory and executable symlinks report the real file, without execution.
mkdir -p "$TMPDIR/links" "$TMPDIR/targets"
cp "$TMPDIR/bin/claude" "$TMPDIR/targets/provider"
ln -s "$TMPDIR/targets/provider" "$TMPDIR/links/claude"
ln -s "$TMPDIR/targets/missing" "$TMPDIR/links/codex"
ln -s "$TMPDIR/links" "$TMPDIR/bin-alias"
PATH="$TMPDIR/bin-alias:$TMPDIR/minimal" /bin/bash "$probe" --json |
  jq -e --arg executable "$TMPDIR/targets/provider" '.agents == [{id:"claude",label:"Claude Code",executable:$executable,available:true,supported:true}]'
chmod -x "$TMPDIR/targets/provider"
PATH="$TMPDIR/links:$TMPDIR/minimal" /bin/bash "$probe" --json | jq -e '.agents == []'
[[ ! -e "$ARANEA_TEST_SANDBOX/forbidden-tool-calls" ]]
status=0
"$probe" --unknown >"$TMPDIR/invalid" 2>&1 || status=$?
[[ $status == 2 ]]
echo 'PASS sandboxed tool availability, defaults, inert contents, absent tools and usage'
