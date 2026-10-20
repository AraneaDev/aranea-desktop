#!/usr/bin/env bash
# Fixed argv, safe provider lookup and refusals exercise the real project guard.
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
  local argv=$1 expected=$2 invoked=${3:-} provider_args=${4:-} resume_request=${5:-} result pid actual
  rm -f "$ARANEA_TEST_SANDBOX/invoked" "$ARANEA_TEST_SANDBOX/provider-argv"
  rm -f "$ARANEA_TEST_SANDBOX/argv" "$ARANEA_TEST_SANDBOX/cwd"
  if [[ -n "$resume_request" ]]; then
    result=$(PATH="$launch_path" "$repo_root/scripts/aranea-agent-launch" <<<"$resume_request") || {
      echo "Expected resume acceptance, got: $result"
      exit 1
    }
  else
    result=$(jq -cn --arg cwd "$checkout" --argjson argv "$argv" '{argv:$argv,cwd:$cwd}' | PATH="$launch_path" "$launcher") || {
      echo "Expected acceptance for $argv, got: $result"
      exit 1
    }
  fi
  jq -e '.ok and .status=="accepted" and (.identity.pid>0) and (.identity.startTime|test("^[0-9]+$"))' <<<"$result" >/dev/null
  pid=$(jq -r .identity.pid <<<"$result")
  sandbox_on_exit "kill -- -$pid 2>/dev/null || true"
  for ((i = 0; i < 50; i++)); do
    [[ ! -f "$ARANEA_TEST_SANDBOX/cwd" ]] || break
    sleep .02
  done
  if [[ -n "$invoked" ]]; then
    for ((i = 0; i < 50; i++)); do
      [[ ! -f "$ARANEA_TEST_SANDBOX/invoked" ]] || break
      sleep .02
    done
    actual=$(jq -Rsc 'split("\n")[:-1]' "$ARANEA_TEST_SANDBOX/provider-argv")
    [[ -f "$ARANEA_TEST_SANDBOX/invoked" && $(<"$ARANEA_TEST_SANDBOX/invoked") == "$invoked" && "$actual" == "$provider_args" ]] || {
      echo "Expected executed $invoked $provider_args, got $(cat "$ARANEA_TEST_SANDBOX/invoked" 2>/dev/null) $actual"
      exit 1
    }
  fi
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

# A mise-style executable depends on the invoked symlink basename.
# The terminal actually execs the resolved provider, rather than only recording argv.
cp "$tool_bin/kitty" "$tool_bin/recording-kitty"
cat >"$tool_bin/kitty" <<'TERMINAL'
#!/bin/bash
printf '%s\n' "$@" > "$ARANEA_TEST_SANDBOX/argv"
printf '%s\n' "$PWD" > "$ARANEA_TEST_SANDBOX/cwd"
shift 4
exec "$@"
TERMINAL
cat >"$tool_bin/mise" <<'SHIM'
#!/bin/bash
: > "$ARANEA_TEST_SANDBOX/provider-argv"
if (($#)); then printf '%s\n' "$@" > "$ARANEA_TEST_SANDBOX/provider-argv"; fi
printf '%s\n' "${0##*/}" > "$ARANEA_TEST_SANDBOX/invoked"
exec /usr/bin/sleep 10
SHIM
chmod +x "$tool_bin/mise"
for tool in claude codex nvim; do
  mv "$tool_bin/$tool" "$tool_bin/recording-$tool"
  ln -s "$tool_bin/mise" "$tool_bin/$tool"
done
base=$(terminal_base kitty)
for provider in claude codex; do
  if [[ "$provider" == claude ]]; then
    provider_args='[]'
    argv=$(jq -c '.+["claude"]' <<<"$base")
    expected=$(jq -c --arg bin "$tool_bin/claude" '.[1:]+[$bin]' <<<"$base")
  else
    provider_args=$(jq -cn --arg cwd "$checkout" '["--cd",$cwd]')
    argv=$(jq -c --arg cwd "$checkout" '.+["codex","--cd",$cwd]' <<<"$base")
    expected=$(jq -c --arg bin "$tool_bin/codex" --arg cwd "$checkout" '.[1:]+[$bin,"--cd",$cwd]' <<<"$base")
  fi
  launch "$argv" "$expected" "$provider" "$provider_args"
  if [[ "$provider" == claude ]]; then
    provider_args=$(jq -cn --arg id "$session_id" '["--resume",$id]')
  else
    provider_args=$(jq -cn --arg id "$session_id" --arg cwd "$checkout" '["resume",$id,"--cd",$cwd]')
  fi
  argv=$(jq -c --arg provider "$provider" --argjson args "$provider_args" '.+[$provider]+$args' <<<"$base")
  expected=$(jq -c --arg bin "$tool_bin/$provider" --argjson args "$provider_args" '.[1:]+[$bin]+$args' <<<"$base")
  launch "$argv" "$expected" "$provider" "$provider_args"
  resume_request=$(jq -cn --arg cwd "$checkout" --arg provider "$provider" --arg id "$session_id" --arg token "$token" '{cwd:$cwd,provider:$provider,providerSessionId:$id,terminalId:"kitty",token:$token}')
  launch "$argv" "$expected" "$provider" "$provider_args" "$resume_request"
done
provider_args=$(jq -cn --arg cwd "$checkout" '["--",$cwd]')
launch "$(jq -c --arg cwd "$checkout" '.+["nvim","--",$cwd]' <<<"$base")" "$(jq -c --arg bin "$tool_bin/nvim" --arg cwd "$checkout" '.[1:]+[$bin,"--",$cwd]' <<<"$base")" nvim "$provider_args"
for tool in claude codex nvim; do
  rm "$tool_bin/$tool"
  mv "$tool_bin/recording-$tool" "$tool_bin/$tool"
done
mv "$tool_bin/recording-kitty" "$tool_bin/kitty"

# Validated invocation preserves an outside symlink, but excludes checkout PATH
# entries (absolute, relative, nested, and aliases) and symlink targets.
base=$(terminal_base kitty)
for provider in claude codex; do
  if [[ "$provider" == claude ]]; then
    argv=$(jq -c '.+["claude"]' <<<"$base")
    expected=$(jq -c --arg bin "$tool_bin/claude" '.[1:]+[$bin]' <<<"$base")
  else
    argv=$(jq -c --arg cwd "$checkout" '.+["codex","--cd",$cwd]' <<<"$base")
    expected=$(jq -c --arg bin "$tool_bin/codex" --arg cwd "$checkout" '.[1:]+[$bin,"--cd",$cwd]' <<<"$base")
  fi
  mv "$tool_bin/$provider" "$tool_bin/real-$provider"
  ln -s "$tool_bin/real-$provider" "$tool_bin/$provider"
  launch "$argv" "$expected"
  rm "$tool_bin/$provider"
  # Even an alias whose target is trusted is excluded when the alias is in checkout.
  ln -s "$tool_bin/real-$provider" "$checkout/$provider"
  ln -s "$checkout" "$ARANEA_TEST_SANDBOX/checkout-alias"
  launch_path=".:$checkout:$checkout/nested:$ARANEA_TEST_SANDBOX/checkout-alias:$tool_bin"
  cd "$checkout"
  refuse "$argv" TOOL_MISSING
  rm "$checkout/$provider" "$ARANEA_TEST_SANDBOX/checkout-alias"
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
# Open diff: the saved terminal runs `git -C <registered checkout> diff <mergeBase>...HEAD`, nothing else.
cp "$tool_bin/kitty" "$tool_bin/git"
mkdir -p "$ARANEA_TEST_SANDBOX/home/.local/state/aranea" "$ARANEA_TEST_SANDBOX/other"
jq -cn --arg p "$checkout" '{projects:[{id:"p",checkouts:[{id:"c",path:$p,primary:false}]}]}' >"$ARANEA_TEST_SANDBOX/home/.local/state/aranea/projects.json"
merge_base=0123456789abcdef0123456789abcdef01234567
# Open diff request for a folder, merge base and terminal; defaults are valid.
diff_request() {
  jq -cn --arg cwd "${1:-$checkout}" --arg mb "${2:-$merge_base}" --arg t "${3:-kitty}" '{kind:"diff",cwd:$cwd,mergeBase:$mb,terminalId:$t}'
}
for terminal in kitty alacritty foot ghostty; do
  rm -f "$ARANEA_TEST_SANDBOX/argv" "$ARANEA_TEST_SANDBOX/cwd"
  result=$(diff_request "$checkout" "$merge_base" "$terminal" | PATH="$launch_path" "$launcher") || {
    echo "Expected diff acceptance for $terminal, got: $result"
    exit 1
  }
  jq -e '.ok and .status=="accepted"' <<<"$result" >/dev/null
  sandbox_on_exit "kill -- -$(jq -r .identity.pid <<<"$result") 2>/dev/null || true"
  for ((i = 0; i < 50; i++)); do
    [[ ! -f "$ARANEA_TEST_SANDBOX/cwd" ]] || break
    sleep .02
  done
  tail_actual=$(jq -Rsc 'split("\n")[:-1][-13:]' "$ARANEA_TEST_SANDBOX/argv")
  tail_expected=$(jq -cn --arg g "$tool_bin/git" --arg cwd "$checkout" --arg r "$merge_base...HEAD" '[$g,"-c","core.pager=less","-c","pager.diff=less","-c","core.fsmonitor=false","-C",$cwd,"diff","--no-ext-diff","--no-textconv",$r]')
  [[ "$tail_actual" == "$tail_expected" ]] || {
    echo "Expected diff tail $tail_expected for $terminal, got: $tail_actual"
    exit 1
  }
  accepted=$((accepted + 1))
done
# Refuse a raw launcher request with the given code and no terminal started.
refuse_raw() {
  local request=$1 code=$2 rc=0 out
  rm -f "$ARANEA_TEST_SANDBOX/argv"
  out=$(PATH="$launch_path" "$launcher" <<<"$request") || rc=$?
  [[ $rc != 0 ]] && jq -e --arg code "$code" '.ok==false and .code==$code' <<<"$out" >/dev/null && [[ ! -f "$ARANEA_TEST_SANDBOX/argv" ]] || {
    echo "Expected $code without launch for $request, got: $out"
    exit 1
  }
  refused=$((refused + 1))
}
refuse_raw "$(diff_request "$checkout" 'HEAD;id')" INVALID_LAUNCH
refuse_raw "$(diff_request "$checkout" "${merge_base^^}")" INVALID_LAUNCH
refuse_raw "$(diff_request "$checkout" "${merge_base}0")" INVALID_LAUNCH
refuse_raw "$(diff_request "$checkout" "$merge_base"$'\n')" INVALID_LAUNCH
refuse_raw "$(diff_request "$checkout" "$merge_base" xterm)" INVALID_LAUNCH
refuse_raw "$(diff_request "$ARANEA_TEST_SANDBOX/other")" CHECKOUT_INVALID
refuse_raw "$(diff_request "$checkout/nested")" CHECKOUT_INVALID
# A symlink to a registered checkout resolves there but is not the registered path itself.
rm -rf "$ARANEA_TEST_SANDBOX/diff-alias"
ln -s "$checkout" "$ARANEA_TEST_SANDBOX/diff-alias"
refuse_raw "$(diff_request "$ARANEA_TEST_SANDBOX/diff-alias")" CHECKOUT_INVALID
rm -f "$ARANEA_TEST_SANDBOX/diff-alias"
refuse_raw "$(diff_request | jq -c '.extra="x"')" INVALID_LAUNCH
refuse_raw "$(diff_request | jq -c '.argv=["kitty","x","y"]')" INVALID_LAUNCH
refuse_raw "$(diff_request | jq -c 'del(.terminalId)')" INVALID_LAUNCH
# Repository config never runs: a diff.external marker script is not executed by the real git.
real_bin="$ARANEA_TEST_SANDBOX/realbin"
mkdir -p "$real_bin"
ln -s /bin/bash "$real_bin/bash"
ln -s "$(command -v git)" "$real_bin/git"
ln -s /usr/bin/less "$real_bin/less"
cat >"$real_bin/kitty" <<'APP'
#!/bin/bash
shift 4
exec "$@"
APP
chmod +x "$real_bin/kitty"
repo="$ARANEA_TEST_SANDBOX/repo"
mkdir -p "$repo"
git_env=(GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t)
env "${git_env[@]}" git -C "$repo" init -q
echo one >"$repo/f"
env "${git_env[@]}" git -C "$repo" add f
env "${git_env[@]}" git -C "$repo" commit -q -m one
echo two >"$repo/f"
env "${git_env[@]}" git -C "$repo" commit -q -am two
base=$(git -C "$repo" rev-parse HEAD~1)
printf '#!/bin/sh\n: > "%s/external-ran"\n' "$ARANEA_TEST_SANDBOX" >"$ARANEA_TEST_SANDBOX/external.sh"
chmod +x "$ARANEA_TEST_SANDBOX/external.sh"
git -C "$repo" config diff.external "$ARANEA_TEST_SANDBOX/external.sh"
# Control: without the guard flags the same config does run the marker script.
git -C "$repo" --no-pager diff "$base...HEAD" >/dev/null 2>&1 || true
[[ -f "$ARANEA_TEST_SANDBOX/external-ran" ]] || {
  echo "Control failed: the marker script should run without --no-ext-diff"
  exit 1
}
rm -f "$ARANEA_TEST_SANDBOX/external-ran"
jq -cn --arg p "$repo" '{projects:[{id:"p",checkouts:[{id:"c",path:$p,primary:false}]}]}' >"$ARANEA_TEST_SANDBOX/home/.local/state/aranea/projects.json"
result=$(diff_request "$repo" "$base" kitty | PATH="$real_bin" "$launcher") || {
  echo "Expected real diff acceptance, got: $result"
  exit 1
}
sandbox_on_exit "kill -- -$(jq -r .identity.pid <<<"$result") 2>/dev/null || true"
sleep 1
[[ ! -f "$ARANEA_TEST_SANDBOX/external-ran" ]] || {
  echo "diff.external ran from repository config"
  exit 1
}
accepted=$((accepted + 1))
# A repository pager.diff outranks core.pager: run the launcher's argv under a real pty so git pages.
git -C "$repo" config pager.diff "/usr/bin/touch $ARANEA_TEST_SANDBOX/pager-ran; /usr/bin/cat"
cat >"$real_bin/kitty" <<'APP'
#!/bin/bash
shift 4
exec /usr/bin/script -qefc "$(printf '%q ' "$@")" /dev/null
APP
rm -f "$ARANEA_TEST_SANDBOX/pager-ran"
# Control: the previous argv (core.pager only) does execute the planted pager under a pty.
# An inherited GIT_PAGER (for example cat in an agent runner) outranks pager.diff.
# Clear it only for this control; the guarded launch must set its own safe pager.
env -u GIT_PAGER /usr/bin/script -qefc "$(printf '%q ' git -c core.pager=less -C "$repo" diff --no-ext-diff --no-textconv "$base...HEAD")" /dev/null </dev/null >/dev/null 2>&1 || true
[[ -f "$ARANEA_TEST_SANDBOX/pager-ran" ]] || {
  echo "Control failed: pager.diff should run under a pty with only core.pager set"
  exit 1
}
rm -f "$ARANEA_TEST_SANDBOX/pager-ran"
result=$(diff_request "$repo" "$base" kitty | PATH="$real_bin" "$launcher") || {
  echo "Expected pty diff acceptance, got: $result"
  exit 1
}
sandbox_on_exit "kill -- -$(jq -r .identity.pid <<<"$result") 2>/dev/null || true"
sleep 1
[[ ! -f "$ARANEA_TEST_SANDBOX/pager-ran" ]] || {
  echo "pager.diff ran from repository config"
  exit 1
}
accepted=$((accepted + 1))
# A repository core.fsmonitor hook never runs, even with a changed working tree (pty, real argv).
printf '#!/bin/sh\n: > "%s/fsmonitor-ran"\nprintf "\\0"\n' "$ARANEA_TEST_SANDBOX" >"$ARANEA_TEST_SANDBOX/fsmonitor.sh"
chmod +x "$ARANEA_TEST_SANDBOX/fsmonitor.sh"
git -C "$repo" config --unset pager.diff
git -C "$repo" config core.fsmonitor "$ARANEA_TEST_SANDBOX/fsmonitor.sh"
echo three >"$repo/f"
rm -f "$ARANEA_TEST_SANDBOX/fsmonitor-ran"
# Control: a plain status of the same repository does run the planted hook.
git -C "$repo" status >/dev/null 2>&1 || true
[[ -f "$ARANEA_TEST_SANDBOX/fsmonitor-ran" ]] || {
  echo "Control failed: core.fsmonitor should run for a status"
  exit 1
}
rm -f "$ARANEA_TEST_SANDBOX/fsmonitor-ran"
jq -cn --arg p "$repo" '{projects:[{id:"p",checkouts:[{id:"c",path:$p,primary:false}]}]}' >"$ARANEA_TEST_SANDBOX/home/.local/state/aranea/projects.json"
result=$(diff_request "$repo" "$base" kitty | PATH="$real_bin" "$launcher") || {
  echo "Expected fsmonitor diff acceptance, got: $result"
  exit 1
}
sandbox_on_exit "kill -- -$(jq -r .identity.pid <<<"$result") 2>/dev/null || true"
sleep 2
[[ ! -f "$ARANEA_TEST_SANDBOX/fsmonitor-ran" ]] || {
  echo "core.fsmonitor ran from repository config"
  exit 1
}
accepted=$((accepted + 1))
# A partial clone must not fetch a missing blob during Open diff: a planted uploadpack would run.
pc_remote="$ARANEA_TEST_SANDBOX/pc-remote.git"
git init -q --bare -b main "$pc_remote"
git -C "$pc_remote" config uploadpack.allowFilter true
git -C "$pc_remote" config uploadpack.allowAnySHA1InWant true
git clone -q "$pc_remote" "$ARANEA_TEST_SANDBOX/pc-seed" 2>/dev/null
echo old >"$ARANEA_TEST_SANDBOX/pc-seed/f"
env "${git_env[@]}" git -C "$ARANEA_TEST_SANDBOX/pc-seed" add f
env "${git_env[@]}" git -C "$ARANEA_TEST_SANDBOX/pc-seed" commit -q -m old
git -C "$ARANEA_TEST_SANDBOX/pc-seed" push -q origin HEAD:main
pc="$ARANEA_TEST_SANDBOX/pc"
pc_linked="$ARANEA_TEST_SANDBOX/pc-linked"
git clone -q --no-checkout --filter=blob:none "file://$pc_remote" "$pc" 2>/dev/null
git -C "$pc" worktree add -q --no-checkout -b feat "$pc_linked"
pc_blob=$(echo new | git -C "$pc_linked" hash-object -w --stdin)
git -C "$pc_linked" read-tree HEAD
git -C "$pc_linked" update-index --cacheinfo "100644,$pc_blob,f"
env "${git_env[@]}" git -C "$pc_linked" commit -q -m new
pc_base=$(git -C "$pc_linked" rev-parse HEAD~1)
git -C "$pc" config remote.origin.uploadpack "/usr/bin/touch $ARANEA_TEST_SANDBOX/lazy-ran; git-upload-pack"
jq -cn --arg p "$pc_linked" '{projects:[{id:"p",checkouts:[{id:"c",path:$p,primary:false}]}]}' >"$ARANEA_TEST_SANDBOX/home/.local/state/aranea/projects.json"
rm -f "$ARANEA_TEST_SANDBOX/lazy-ran"
result=$(diff_request "$pc_linked" "$pc_base" kitty | PATH="$real_bin" "$launcher") || {
  echo "Expected partial clone diff acceptance, got: $result"
  exit 1
}
sandbox_on_exit "kill -- -$(jq -r .identity.pid <<<"$result") 2>/dev/null || true"
sleep 2
[[ ! -f "$ARANEA_TEST_SANDBOX/lazy-ran" ]] || {
  echo "a lazy fetch ran the repository uploadpack command"
  exit 1
}
# Control: the same diff without the guard does fetch the blob and run the planted command.
/usr/bin/script -qefc "$(printf '%q ' git -C "$pc_linked" diff --no-ext-diff --no-textconv "$pc_base...HEAD")" /dev/null </dev/null >/dev/null 2>&1 || true
[[ -f "$ARANEA_TEST_SANDBOX/lazy-ran" ]] || {
  echo "Control failed: the planted uploadpack should run on a lazy fetch"
  exit 1
}
accepted=$((accepted + 1))
echo "PASS Open diff: four terminals accepted, malformed mergeBase, unregistered path, unknown terminal and extra fields refused"
echo "PASS $accepted accepted launches, $refused refusals: all terminal/provider shapes, basename-sensitive shims, editor/resume shapes and canonical safe PATH"
