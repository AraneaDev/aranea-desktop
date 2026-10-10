#!/usr/bin/env bash
# Real install/removal boundaries must retain authority until exact owned drain.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
backend="$repo_root/scripts/aranea-project-actions"
# Even with the checkout excluded from PATH, all effect tools remain sandboxed.
"$backend" availability </dev/null >"$TMPDIR/availability"
jq -e '.availability.userManager==false' "$TMPDIR/availability" >/dev/null
grep -Fq 'systemctl --user --no-ask-password show --property=Version' "$ARANEA_TEST_SANDBOX/guard.log"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/repo" "$ARANEA_TEST_SANDBOX/manager"
for tool in systemd-run systemctl journalctl curl xdg-open; do ln -s "$repo_root/tests/fixtures/project-actions-manager.sh" "$ARANEA_TEST_SANDBOX/bin/$tool"; done
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
manager="$ARANEA_TEST_SANDBOX/manager"
git init -q "$ARANEA_TEST_SANDBOX/repo"
printf 'repository sentinel\n' >"$ARANEA_TEST_SANDBOX/repo/keep"
source "$repo_root/scripts/lib/ownership.sh"
# Register/configure only through real stores; submitted argv is never executed.
setup_action() {
  "$backend" activate </dev/null >/dev/null
  "$repo_root/scripts/aranea-agent-store" activate >/dev/null
  jq -cn --arg p "$ARANEA_TEST_SANDBOX/repo" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
  project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
  jq -cn --arg p "$project" '{projectId:$p,definition:{name:"Checks",kind:"command",argv:["printf","never executed"],cwdRelative:".",previewUrl:null}}' | "$backend" configure >"$TMPDIR/configured"
  action=$(jq -r '.state.definitions[0].id' "$TMPDIR/configured")
  jq -cn --arg p "$project" --arg a "$action" --arg r "req-$(cat /proc/sys/kernel/random/uuid)" '{projectId:$p,actionId:$a,requestId:$r}' >"$TMPDIR/start"
}
pids=()
# Release held transport before waiting for children on failure.
cleanup_children() {
  rm -f "$manager/show-hold" "$TMPDIR/lifecycle-hold" "$TMPDIR/gsettings-hold"
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
}
sandbox_on_exit cleanup_children
if [[ ${1:-} != --lifecycle-effects-only ]]; then
  for scope in integration complete; do
    for layout in separate equal action-nested ownership-nested; do
      base="$ARANEA_TEST_SANDBOX/$scope-$layout"
      export ARANEA_STATE_ROOT="$base/actions" ARANEA_OWNERSHIP_ROOT="$base/ownership"
      case "$layout" in
        equal) export ARANEA_OWNERSHIP_ROOT="$ARANEA_STATE_ROOT" ;;
        action-nested) export ARANEA_STATE_ROOT="$ARANEA_OWNERSHIP_ROOT/nested/actions" ;;
        ownership-nested) export ARANEA_OWNERSHIP_ROOT="$ARANEA_STATE_ROOT/nested/ownership" ;;
      esac
      setup_action
      generation=$(cat "$ARANEA_STATE_ROOT/project-actions.json.lock")
      generation=${generation:-initial}
      "$backend" start <"$TMPDIR/start" >"$TMPDIR/run"
      unit=$(jq -r .run.unitName "$TMPDIR/run")
      inodes=$(stat -c %i "$ARANEA_STATE_ROOT/agent-activity.json.lock" "$ARANEA_STATE_ROOT/project-actions.json.lock" "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock")
      mkdir -p "$ARANEA_OWNERSHIP_ROOT/unrelated-dir"
      touch "$ARANEA_OWNERSHIP_ROOT/project-actions.json.fake.lock"
      printf 'unrelated unit\n' >"$manager/unrelated.service"
      cp "$ARANEA_STATE_ROOT/project-actions.json" "$TMPDIR/before"
      "$repo_root/scripts/uninstall.sh" --yes --dry-run --scope "$scope" >/dev/null
      cmp "$ARANEA_STATE_ROOT/project-actions.json" "$TMPDIR/before"
      [[ ! -e "$manager/stops" ]]
      "$repo_root/scripts/uninstall.sh" --yes --json --scope "$scope" >"$TMPDIR/uninstall"
      [[ ! -e "$ARANEA_STATE_ROOT/project-actions.json" ]] || {
        echo "FAIL $scope/$layout retained action payload"
        exit 1
      }
      grep -Fxq "$unit" "$manager/stops"
      [[ $(wc -l <"$manager/stops") == 1 ]]
      [[ $(cat "$manager/unrelated.service") == 'unrelated unit' ]]
      [[ $(stat -c %i "$ARANEA_STATE_ROOT/agent-activity.json.lock" "$ARANEA_STATE_ROOT/project-actions.json.lock" "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock") == "$inodes" ]]
      [[ ! -e "$ARANEA_OWNERSHIP_ROOT/unrelated-dir" && ! -e "$ARANEA_OWNERSHIP_ROOT/project-actions.json.fake.lock" ]]
      jq -es 'last.status=="ok"' "$TMPDIR/uninstall" >/dev/null
      "$backend" activate </dev/null >/dev/null
      if ARANEA_ACTION_GENERATION="$generation" "$backend" start <"$TMPDIR/start" >"$TMPDIR/late"; then
        echo 'FAIL old ingress crossed reinstall'
        exit 1
      fi
      jq -e '.error.code=="ACTION_REMOVED"' "$TMPDIR/late" >/dev/null
      [[ $(cat "$ARANEA_TEST_SANDBOX/repo/keep") == 'repository sentinel' ]]
      rm "$manager/stops"
      echo "PASS $scope/$layout exact drain, inert dry-run, stable coordination and retired ingress"
    done
  done
  # Refused drain must precede removal of command, plugins, hooks or theme code.
  for failure in unavailable replaced cleanup-unconfirmed; do
    export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/refusal-$failure" ARANEA_OWNERSHIP_ROOT="$ARANEA_TEST_SANDBOX/owner-$failure"
    setup_action
    echo running >"$manager/mode"
    if [[ $failure == cleanup-unconfirmed ]]; then
      echo fast >"$manager/mode"
      touch "$manager/stop-no-change"
    fi
    "$backend" start <"$TMPDIR/start" >"$TMPDIR/run" || true
    run=$(jq -r .run.id "$TMPDIR/run")
    unit=$(jq -r .run.unitName "$TMPDIR/run")
    cp "$manager/$unit" "$TMPDIR/proof"
    case "$failure" in
      unavailable) touch "$manager/unavailable" ;;
      replaced) sed -i 's/InvocationID=.*/InvocationID=22222222222222222222222222222222/' "$manager/$unit" ;;
    esac
    mkdir -p "$HOME/.local/bin" "$HOME/.config/omarchy/plugins/araneadev.projects"
    ln -sf "$HOME/.config/omarchy/themes/aranea/scripts/aranea" "$HOME/.local/bin/aranea"
    record_managed_file "$HOME/.local/bin/aranea"
    : >"$ARANEA_TEST_SANDBOX/guard.log"
    if "$repo_root/scripts/uninstall.sh" --yes --json --scope complete >"$TMPDIR/refused"; then
      echo "FAIL $failure teardown claimed success"
      exit 1
    fi
    jq -es 'last.status=="failed" and last.code=="action_teardown_failed"' "$TMPDIR/refused" >/dev/null
    [[ -f "$ARANEA_STATE_ROOT/project-actions.json" && -f "$ARANEA_STATE_ROOT/projects.json" && -L "$HOME/.local/bin/aranea" && -d "$HOME/.config/omarchy/plugins/araneadev.projects" ]]
    [[ $(cat "$ARANEA_STATE_ROOT/project-actions.json.lock") == draining:* ]]
    if grep -Fq 'theme remove' "$ARANEA_TEST_SANDBOX/guard.log"; then
      echo 'FAIL removed recovery theme'
      exit 1
    fi
    if "$backend" activate </dev/null >"$TMPDIR/reactivate"; then
      echo 'FAIL protected drain reactivated'
      exit 1
    fi
    jq -e '.error.code=="RUN_PROTECTED"' "$TMPDIR/reactivate" >/dev/null
    rm -f "$manager/unavailable" "$manager/stop-no-change"
    cp "$TMPDIR/proof" "$manager/$unit"
    jq -cn --arg r "$run" '{runId:$r}' | "$backend" stop >/dev/null
    "$repo_root/scripts/uninstall.sh" --yes --scope complete >/dev/null
    [[ ! -e "$ARANEA_STATE_ROOT/project-actions.json" ]]
    echo "PASS $failure retains fenced recovery payload and installed command until exact cleanup"
  done
  # A start holds actual dispatch authority while its first observation is pending.
  export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/held" ARANEA_OWNERSHIP_ROOT="$ARANEA_TEST_SANDBOX/held-owner"
  setup_action
  echo running >"$manager/mode"
  touch "$manager/show-hold"
  "$backend" start <"$TMPDIR/start" >"$TMPDIR/held-start" &
  writer=$!
  pids+=("$writer")
  for _ in {1..200}; do
    [[ ! -e "$manager/show-entered" ]] || break
    sleep .01
  done
  [[ -e "$manager/show-entered" ]]
  "$repo_root/scripts/uninstall.sh" --yes --json >"$TMPDIR/held-removal" &
  removal=$!
  pids+=("$removal")
  sleep .1
  kill -0 "$removal"
  [[ -f "$ARANEA_STATE_ROOT/project-actions.json" ]]
  rm "$manager/show-hold"
  wait "$writer"
  wait "$removal"
  [[ ! -e "$ARANEA_STATE_ROOT/project-actions.json" ]]
  # Capture generation before blocked stdin, then remove/reactivate before release.
  "$backend" activate </dev/null >/dev/null
  mkfifo "$TMPDIR/input"
  "$backend" start <"$TMPDIR/input" >"$TMPDIR/queued" &
  queued=$!
  pids+=("$queued")
  exec {input_fd}>"$TMPDIR/input"
  reading=false
  for _ in {1..200}; do
    children=()
    read -r -a children <"/proc/$queued/task/$queued/children" || true
    for child in "${children[@]}"; do
      if [[ $(tr '\0' ' ' <"/proc/$child/cmdline" 2>/dev/null || true) == *'head -c 1048577'* ]]; then reading=true; fi
    done
    [[ $reading != true ]] || break
    sleep .01
  done
  [[ $reading == true ]]
  launches=$(wc -l <"$manager/launches")
  "$repo_root/scripts/uninstall.sh" --yes >/dev/null
  "$backend" activate </dev/null >/dev/null
  cat "$TMPDIR/start" >&"$input_fd"
  exec {input_fd}>&-
  if wait "$queued"; then
    echo 'FAIL queued stdin crossed reinstall'
    exit 1
  fi
  jq -e '.error.code=="ACTION_REMOVED"' "$TMPDIR/queued" >/dev/null
  [[ $(wc -l <"$manager/launches") == "$launches" ]]
  echo 'PASS held dispatch drains and blocked stdin stays fenced after reinstall'

  # A timed-out submission may arrive late: never erase its accepted intent.
  export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/late-acceptance" ARANEA_OWNERSHIP_ROOT="$ARANEA_TEST_SANDBOX/late-owner"
  setup_action
  echo late >"$manager/mode"
  "$backend" start <"$TMPDIR/start" >"$TMPDIR/late-run"
  jq -e '.run.submissionUnconfirmed' "$TMPDIR/late-run" >/dev/null
  touch "$manager/unavailable"
  if "$repo_root/scripts/uninstall.sh" --yes --json >"$TMPDIR/late-refusal"; then
    echo 'FAIL late acceptance erased'
    exit 1
  fi
  [[ -f "$ARANEA_STATE_ROOT/project-actions.json" ]]
  rm "$manager/unavailable"
  sleep 1.2
  "$repo_root/scripts/uninstall.sh" --yes >/dev/null
  [[ ! -e "$ARANEA_STATE_ROOT/project-actions.json" ]]
  echo 'PASS late accepted intent survives unavailable manager and drains on retry'

  # Unsafe action roots/leafs are refused without following or deleting sentinels.
  for unsafe in root payload lock dispatch; do
    export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/symlink-$unsafe" ARANEA_OWNERSHIP_ROOT="$ARANEA_TEST_SANDBOX/symlink-owner-$unsafe"
    target="$ARANEA_TEST_SANDBOX/target-$unsafe"
    mkdir -p "$target" "$ARANEA_STATE_ROOT"
    printf 'untouched\n' >"$target/sentinel"
    case "$unsafe" in
      root)
        rmdir "$ARANEA_STATE_ROOT"
        ln -s "$target" "$ARANEA_STATE_ROOT"
        ;;
      payload) ln -s "$target/sentinel" "$ARANEA_STATE_ROOT/project-actions.json" ;;
      lock) ln -s "$target/sentinel" "$ARANEA_STATE_ROOT/project-actions.json.lock" ;;
      dispatch) ln -s "$target/sentinel" "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock" ;;
    esac
    if "$repo_root/scripts/uninstall.sh" --yes --json >"$TMPDIR/unsafe"; then
      echo "FAIL unsafe $unsafe removed"
      exit 1
    fi
    jq -es 'last.status=="failed" and (last.code=="action_teardown_failed" or last.code=="action_lifecycle_busy")' "$TMPDIR/unsafe" >/dev/null
    [[ $(cat "$target/sentinel") == untouched ]]
  done
  echo 'PASS symlink action roots and payload/coordination leaves preserve targets'

fi

# Hold actual removal after backend drain; a fresh installer must not reactivate.
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/concurrent" ARANEA_OWNERSHIP_ROOT="$ARANEA_TEST_SANDBOX/concurrent-owner"
setup_action
mkdir -p "$TMPDIR/lifecycle-bin" "$HOME/.config/omarchy/themes/aranea" "$HOME/.config/omarchy/plugins/araneadev.projects"
cp -a "$repo_root/scripts" "$repo_root/branding" "$HOME/.config/omarchy/themes/aranea/"
cat >"$TMPDIR/lifecycle-bin/omarchy" <<'LIFECYCLE'
#!/bin/bash
for fd in /proc/$$/fd/*; do
  if [[ $(readlink "$fd") == "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock" ]]; then
    printf '%s %s\n' "${0##*/}" "$1" >>"$TMPDIR/effect-leaks"
  fi
done
if [[ ${0##*/} == gsettings ]]; then
  printf '%s\n' "$1" >>"$TMPDIR/gsettings-calls"
  # A distinct open-file description must remain locked by the parent.
  if flock -n "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock" true; then
    touch "$TMPDIR/parent-authority-lost"
  fi
  if [[ $1 == set && -e $TMPDIR/gsettings-hold ]]; then
    touch "$TMPDIR/gsettings-entered"
    while [[ -e $TMPDIR/gsettings-hold ]]; do sleep .01; done
  fi
  [[ $1 != get ]] || printf "'Aranea-icons'\n"
  exit 0
fi
if [[ $* == 'restart shell' || $* == 'theme install '* ]]; then
  touch "$TMPDIR/lifecycle-entered"
  while [[ -e $TMPDIR/lifecycle-hold ]]; do sleep .01; done
fi
exit 0
LIFECYCLE
chmod +x "$TMPDIR/lifecycle-bin/omarchy"
export PATH="$TMPDIR/lifecycle-bin:$PATH"
touch "$TMPDIR/lifecycle-hold"
"$repo_root/scripts/uninstall.sh" --yes --json >"$TMPDIR/concurrent-uninstall" &
removal=$!
pids+=("$removal")
for _ in {1..300}; do
  [[ ! -e "$TMPDIR/lifecycle-entered" ]] || break
  sleep .01
done
[[ -e "$TMPDIR/lifecycle-entered" ]]
# Avoid blocking inside the install fixture: its mutex must refuse first.
if timeout 4s "$repo_root/scripts/install.sh" --yes --json --profile minimal --source https://example.invalid/aranea.git >"$TMPDIR/concurrent-install"; then
  echo 'FAIL installer crossed removal'
  exit 1
fi
jq -es 'last.status=="failed" and last.code=="action_lifecycle_busy"' "$TMPDIR/concurrent-install" >/dev/null
[[ $(cat "$ARANEA_STATE_ROOT/project-actions.json.lock") == removed:* ]]
rm "$TMPDIR/lifecycle-hold"
wait "$removal"
# Reverse direction: hold install deployment; removal must refuse before cleanup.
rm "$TMPDIR/lifecycle-entered"
touch "$TMPDIR/lifecycle-hold"
"$repo_root/scripts/install.sh" --yes --json --profile minimal --source https://example.invalid/aranea.git >"$TMPDIR/held-install" &
installer=$!
pids+=("$installer")
for _ in {1..300}; do
  [[ ! -e "$TMPDIR/lifecycle-entered" ]] || break
  sleep .01
done
[[ -e "$TMPDIR/lifecycle-entered" ]]
if "$repo_root/scripts/uninstall.sh" --yes --json >"$TMPDIR/install-blocked-removal"; then
  echo 'FAIL removal crossed deployment'
  exit 1
fi
jq -es 'last.status=="failed" and last.code=="action_lifecycle_busy"' "$TMPDIR/install-blocked-removal" >/dev/null
rm "$TMPDIR/lifecycle-hold"
wait "$installer"
[[ $(cat "$ARANEA_STATE_ROOT/project-actions.json.lock") == active:* ]]
echo 'PASS mutually exclusive install/removal and later reinstall activation'

# The same native boundary also covers settings restoration's set/get/reset paths.
ln -s "$TMPDIR/lifecycle-bin/omarchy" "$TMPDIR/lifecycle-bin/gsettings"
mkdir -p "$ARANEA_OWNERSHIP_ROOT/gsettings"
printf "'Adwaita'\n" >"$ARANEA_OWNERSHIP_ROOT/gsettings/org.gnome.desktop.interface.cursor-theme"
touch "$TMPDIR/gsettings-hold"
"$repo_root/scripts/uninstall.sh" --yes --json >"$TMPDIR/settings-uninstall" &
removal=$!
pids+=("$removal")
for _ in {1..300}; do
  [[ ! -e "$TMPDIR/gsettings-entered" ]] || break
  sleep .01
done
[[ -e "$TMPDIR/gsettings-entered" ]]
if "$repo_root/scripts/install.sh" --yes --json --profile minimal --source https://example.invalid/aranea.git >"$TMPDIR/settings-blocked-install"; then
  echo 'FAIL installer crossed settings restoration'
  exit 1
fi
jq -es 'last.status=="failed" and last.code=="action_lifecycle_busy"' "$TMPDIR/settings-blocked-install" >/dev/null
rm "$TMPDIR/gsettings-hold"
wait "$removal"
for method in set get reset; do grep -Fxq "$method" "$TMPDIR/gsettings-calls"; done
[[ ! -e "$TMPDIR/parent-authority-lost" ]]
if [[ -e "$TMPDIR/effect-leaks" ]]; then
  echo 'FAIL lifecycle authority leaked into native effects:'
  cat "$TMPDIR/effect-leaks"
  exit 1
fi
# Completion releases the parent descriptor as well.
flock -n "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock" true
echo 'PASS gsettings set/get/reset close child authority while parent fences concurrent install'
