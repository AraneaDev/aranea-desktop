#!/usr/bin/env bash
# Registration and explicit seeding give every project a startable default profile.
# shellcheck disable=SC2016 # jq predicates are single-quoted on purpose
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
store="$repo_root/scripts/aranea-project-store"
cli="$repo_root/scripts/aranea"
# Minimal PATH of required utilities only, so host editors/terminals never leak in.
minbin="$ARANEA_TEST_SANDBOX/minbin"
tools="$ARANEA_TEST_SANDBOX/tools"
mkdir -p "$minbin" "$tools" "$XDG_STATE_HOME/omarchy/defaults"
for cmd in bash env jq git flock realpath mktemp mv rm cat date sed head tail stat timeout sort uniq tr cut dirname basename mkdir ls readlink printf grep awk ln cp chmod touch id uname; do
  found=$(command -v "$cmd" || true)
  [[ -z $found || $found != /* ]] || ln -sf "$found" "$minbin/$cmd"
done
# Availability fixtures that must never be executed.
fake_tool() {
  cat >"$tools/$1" <<'TOOL'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >>"$ARANEA_TEST_SANDBOX/forbidden-tool-calls"
exit 99
TOOL
  chmod +x "$tools/$1"
}
# Assert a jq predicate over a file; $p is bound to the second argument.
expect() {
  local file=$1 p=$2 predicate=$3 message=$4
  jq -e --arg p "$p" "$predicate" "$file" >/dev/null || {
    echo "FAIL: $message" >&2
    jq . "$file" >&2
    exit 1
  }
}
# Create a fresh git repository and print its path.
repo() {
  git init -q -b main "$ARANEA_TEST_SANDBOX/repos/$1"
  printf '%s\n' "$ARANEA_TEST_SANDBOX/repos/$1"
}
# Register one path through the store with only the stub tools on PATH.
register() { jq -cn --arg p "$1" '{action:"register",args:{paths:[$p]}}' | PATH="$tools:$minbin" "$store" mutate >"$TMPDIR/out"; }
# Project ID owning the checkout path.
project_of() { jq -r --arg p "$1" '.state.projects[]|select(any(.checkouts[];.path==$p))|.id' "$TMPDIR/out"; }
# Saved profiles of one project from the last store response.
profiles_of() { jq -c --arg p "$1" '.state.projects[]|select(.id==$p)|.profiles' "$TMPDIR/out"; }
mkdir -p "$ARANEA_TEST_SANDBOX/repos"

# Pure preset rule mirrors ProjectProfiles.js presets().
probe='{"editors":[{"id":"code","available":true,"supported":true},{"id":"nvim","available":true,"supported":true}],"terminals":[{"id":"alacritty","available":true,"supported":true},{"id":"kitty","available":true,"supported":true}],"agents":[{"id":"claude","available":true,"supported":true}],"defaults":{"editorId":"code","terminalId":"kitty"}}'
jq -n --argjson tools "$probe" -f "$repo_root/scripts/lib/project-presets.jq" >"$TMPDIR/presets"
expect "$TMPDIR/presets" '' '. == [{name:"VS Code",roles:["editor"],tools:{editorId:"code",terminalId:null,agentId:null}},{name:"Terminal + Agent",roles:["terminal","agent"],tools:{editorId:null,terminalId:"kitty",agentId:"claude"}},{name:"Neovim",roles:["editor"],tools:{editorId:"nvim",terminalId:"kitty",agentId:null}},{name:"Terminal",roles:["terminal"],tools:{editorId:null,terminalId:"kitty",agentId:null}}]' 'preset rule'
jq -n --argjson tools '{"editors":[],"terminals":[],"agents":[]}' -f "$repo_root/scripts/lib/project-presets.jq" >"$TMPDIR/presets"
expect "$TMPDIR/presets" '' '. == []' 'no tools, no presets'

# One tool-ID list: the shared jq module names exactly what aranea-project-tools probes, per group.
ids_module="$repo_root/scripts/lib/project-tool-ids.jq"
[[ -f $ids_module ]] || {
  echo 'FAIL: scripts/lib/project-tool-ids.jq is missing' >&2
  exit 1
}
module_ids=$(jq -nr 'include "project-tool-ids" {search: "'"$repo_root/scripts/lib"'"}; tool_ids | [.[][]] | sort | join(" ")')
probed_ids=$(sed -nE 's/^for id in (.*); do$/\1/p' "$repo_root/scripts/aranea-project-tools" | tr ' ' '\n' | sort | paste -sd' ')
[[ -n $probed_ids && $module_ids == "$probed_ids" ]] || {
  echo "FAIL: tool IDs drifted: module [$module_ids] probe [$probed_ids]" >&2
  exit 1
}
for id in $probed_ids; do fake_tool "$id"; done
PATH="$tools:$minbin" "$repo_root/scripts/aranea-project-tools" --json >"$TMPDIR/probe"
jq -e --argjson ids "$(jq -nc 'include "project-tool-ids" {search: "'"$repo_root/scripts/lib"'"}; tool_ids')" \
  '(.editors|map(.id)|sort) == ($ids.editors|sort) and (.terminals|map(.id)|sort) == ($ids.terminals|sort) and (.agents|map(.id)|sort) == ($ids.agents|sort)' "$TMPDIR/probe" >/dev/null ||
  {
    echo 'FAIL: probe groups differ from the shared tool IDs' >&2
    jq . "$TMPDIR/probe" >&2
    exit 1
  }
rm -f "$tools"/*

# Bad probe IDs never become drafts the store would refuse.
jq -n --argjson tools '{"editors":[{"id":"code;rm","available":true,"supported":true},{"id":7,"available":true,"supported":true}],"terminals":[{"id":7,"available":true,"supported":true},{"id":null,"available":true,"supported":true},"junk"],"agents":[{"id":["claude"],"available":true,"supported":true}],"defaults":{"terminalId":7}}' -f "$repo_root/scripts/lib/project-presets.jq" >"$TMPDIR/presets"
expect "$TMPDIR/presets" '' '. == []' 'bad probe IDs yield no drafts'
jq -n --argjson tools '{"editors":"x","terminals":{"id":"kitty"},"agents":null}' -f "$repo_root/scripts/lib/project-presets.jq" >"$TMPDIR/presets"
expect "$TMPDIR/presets" '' '. == []' 'malformed groups yield no drafts'

# Registration seeds presets from the probe (code + kitty + claude).
fake_tool code
fake_tool kitty
fake_tool claude
printf 'kitty.desktop\n' >"$XDG_CONFIG_HOME/xdg-terminals.list"
one=$(repo one)
register "$one"
p1=$(project_of "$one")
expect "$TMPDIR/out" "$p1" '.state.projects[]|select(.id==$p)|(.profiles|map(.name))==["VS Code","Terminal + Agent","Terminal"] and all(.profiles[];.revision==1 and (.id|startswith("f-"))) and .lastProfileId==null' 'register seeds'

# Existing project untouched: a second checkout (worktree) of the same repository.
git -C "$one" -c user.name=F -c user.email=f@x.invalid commit --allow-empty -qm init
wt="$ARANEA_TEST_SANDBOX/repos/one-wt"
git -C "$one" worktree add -qb review "$wt"
before=$(profiles_of "$p1")
register "$wt"
[[ $(profiles_of "$p1") == "$before" ]]

# Repeat seed is a no-op once profiles exist.
jq -cn --arg p "$p1" '{action:"profiles-seed",args:{projectId:$p}}' | PATH="$tools:$minbin" "$store" mutate >"$TMPDIR/out"
[[ $(profiles_of "$p1") == "$before" ]]

# Explicit save first, then seed: unchanged.
fake_tool_save_target=$(repo saved)
rm -f "$tools"/*
register "$fake_tool_save_target"
ps=$(project_of "$fake_tool_save_target")
jq -cn --arg p "$ps" '{action:"profile-save",args:{projectId:$p,profile:{name:"Mine",roles:["terminal"],tools:{editorId:null,terminalId:"kitty",agentId:null}}}}' | PATH="$tools:$minbin" "$store" mutate >"$TMPDIR/out"
saved=$(profiles_of "$ps")
fake_tool code
fake_tool kitty
fake_tool claude
jq -cn --arg p "$ps" '{action:"profiles-seed",args:{projectId:$p}}' | PATH="$tools:$minbin" "$store" mutate >"$TMPDIR/out"
[[ $(profiles_of "$ps") == "$saved" ]]
expect "$TMPDIR/out" "$ps" '.state.projects[]|select(.id==$p)|(.profiles|map(.name))==["Mine"]' 'seed after save keeps only the saved profile'

# No supported tools: registration succeeds with zero profiles.
rm -f "$tools"/*
two=$(repo two)
register "$two"
expect "$TMPDIR/out" '' '.ok==true' 'register without tools succeeds'
p2=$(project_of "$two")
expect "$TMPDIR/out" "$p2" '.state.projects[]|select(.id==$p)|.profiles==[]' 'no tools, no profiles'

# Probe failure (no `timeout` available to the store) never fails registration.
fake_tool code
nobin="$ARANEA_TEST_SANDBOX/nobin"
mkdir -p "$nobin"
for f in "$minbin"/*; do [[ $(basename "$f") == timeout ]] || ln -sf "$(readlink "$f")" "$nobin/$(basename "$f")"; done
three=$(repo three)
jq -cn --arg p "$three" '{action:"register",args:{paths:[$p]}}' | PATH="$tools:$nobin" "$store" mutate >"$TMPDIR/out"
expect "$TMPDIR/out" '' '.ok==true' 'probe failure tolerated'
p3=$(project_of "$three")
expect "$TMPDIR/out" "$p3" '.state.projects[]|select(.id==$p)|.profiles==[]' 'probe failure seeds nothing'

# An explicit seed whose probe fails says so instead of looking like "no tools", and changes nothing.
registry_before=$(cat "$ARANEA_STATE_ROOT/projects.json")
status=0
jq -cn --arg p "$p3" '{action:"profiles-seed",args:{projectId:$p}}' | PATH="$tools:$nobin" "$store" mutate >"$TMPDIR/out" || status=$?
[[ $status != 0 ]] || {
  echo 'FAIL: a failed probe must fail the seed' >&2
  exit 1
}
expect "$TMPDIR/out" "Couldn't check which tools are installed." '.ok==false and .error.code=="PROBE_FAILED" and .error.message==$p and .error.recovery=="Check again."' 'failed probe refuses the seed'
[[ $(cat "$ARANEA_STATE_ROOT/projects.json") == "$registry_before" ]] || {
  echo 'FAIL: a failed probe changed the registry' >&2
  exit 1
}

# Backfill through the public CLI once tools exist.
PATH="$tools:$minbin" "$cli" projects profiles seed "$p2" --json >"$TMPDIR/cli"
jq -es '.[-1].status=="observed" and .[-1].data.seeded==1 and .[-1].data.reason==null and (.[-1].data.profiles|map(.name))==["VS Code"]' "$TMPDIR/cli" >/dev/null
PATH="$tools:$minbin" "$cli" projects profiles seed "$p2" --json >"$TMPDIR/cli"
jq -es '.[-1].data.seeded==0 and .[-1].data.reason=="HAS_PROFILES"' "$TMPDIR/cli" >/dev/null
rm -f "$tools/code"
four=$(repo four)
register "$four"
p4=$(project_of "$four")
PATH="$tools:$minbin" "$cli" projects profiles seed "$p4" --json >"$TMPDIR/cli"
jq -es '.[-1].data.seeded==0 and .[-1].data.reason=="NO_SUPPORTED_TOOLS"' "$TMPDIR/cli" >/dev/null
[[ ! -e $ARANEA_TEST_SANDBOX/forbidden-tool-calls ]]
echo 'projects-profile-seed: ok'
