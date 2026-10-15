#!/usr/bin/env bash
# Registration and explicit seeding give every project a startable default profile.
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
repo() {
  git init -q -b main "$ARANEA_TEST_SANDBOX/repos/$1"
  printf '%s\n' "$ARANEA_TEST_SANDBOX/repos/$1"
}
register() { jq -cn --arg p "$1" '{action:"register",args:{paths:[$p]}}' | PATH="$tools:$minbin" "$store" mutate >"$TMPDIR/out"; }
project_of() { jq -r --arg p "$1" '.state.projects[]|select(any(.checkouts[];.path==$p))|.id' "$TMPDIR/out"; }
profiles_of() { jq -c --arg p "$1" '.state.projects[]|select(.id==$p)|.profiles' "$TMPDIR/out"; }
mkdir -p "$ARANEA_TEST_SANDBOX/repos"

# Pure preset rule mirrors ProjectProfiles.js presets().
probe='{"editors":[{"id":"code","available":true,"supported":true},{"id":"nvim","available":true,"supported":true}],"terminals":[{"id":"alacritty","available":true,"supported":true},{"id":"kitty","available":true,"supported":true}],"agents":[{"id":"claude","available":true,"supported":true}],"defaults":{"editorId":"code","terminalId":"kitty"}}'
jq -n --argjson tools "$probe" -f "$repo_root/scripts/lib/project-presets.jq" >"$TMPDIR/presets"
expect "$TMPDIR/presets" '' '. == [{name:"VS Code",roles:["editor"],tools:{editorId:"code",terminalId:null,agentId:null}},{name:"Terminal + Agent",roles:["terminal","agent"],tools:{editorId:null,terminalId:"kitty",agentId:"claude"}},{name:"Neovim",roles:["editor"],tools:{editorId:"nvim",terminalId:"kitty",agentId:null}},{name:"Terminal",roles:["terminal"],tools:{editorId:null,terminalId:"kitty",agentId:null}}]' 'preset rule'
jq -n --argjson tools '{"editors":[],"terminals":[],"agents":[]}' -f "$repo_root/scripts/lib/project-presets.jq" >"$TMPDIR/presets"
expect "$TMPDIR/presets" '' '. == []' 'no tools, no presets'

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
expect "$TMPDIR/out" "$(project_of "$three")" '.state.projects[]|select(.id==$p)|.profiles==[]' 'probe failure seeds nothing'

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
