#!/usr/bin/env bash
# Contract for the boot splash memory: post-boot records whether the Aranea
# splash was chosen, post-update restores it after an Omarchy upgrade reset it,
# and scripts/aranea-boot-splash switches it on and off. Omarchy's plymouth
# commands are fakes that log their calls and answer from a "current" file.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

fake="$ARANEA_TEST_SANDBOX/fake-bin"
calls="$ARANEA_TEST_SANDBOX/calls.log"
current_file="$ARANEA_TEST_SANDBOX/current"
state="$XDG_STATE_HOME/aranea/boot-splash"
mkdir -p "$XDG_STATE_HOME/aranea" "$fake" "$HOME/.config/omarchy/themes/aranea"
cat >"$fake/omarchy" <<'STUB'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls.log"
case "$*" in
  "plymouth current") [[ -e "$ARANEA_TEST_SANDBOX/current-fails" ]] && exit 1; cat "$ARANEA_TEST_SANDBOX/current" ;;
  "theme current") echo "Tokyo Night" ;;
esac
exit 0
STUB
cat >"$fake/omarchy-plymouth-set-by-theme" <<'STUB'
#!/usr/bin/env bash
printf 'set-by-theme %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls.log"
[[ ! -e "$ARANEA_TEST_SANDBOX/set-fails" ]] || exit 1
echo aranea >"$ARANEA_TEST_SANDBOX/current"
STUB
cat >"$fake/omarchy-plymouth-reset" <<'STUB'
#!/usr/bin/env bash
printf 'reset\n' >>"$ARANEA_TEST_SANDBOX/calls.log"
echo default >"$ARANEA_TEST_SANDBOX/current"
STUB
chmod +x "$fake"/*
export PATH="$fake:$PATH"

# Sets the splash the fake Omarchy reports and clears the call log.
splash_is() {
  printf '%s\n' "$1" >"$current_file"
  : >"$calls"
}
# Fails unless the state file holds $1 (or is absent for "none").
state_is() {
  if [[ $1 == none ]]; then [[ ! -e "$state" ]]; else [[ "$(<"$state")" == "$1" ]]; fi
}

# post-boot records the choice, even when Aranea is not the active theme.
splash_is aranea
"$repo_root/hooks/post-boot"
state_is on
splash_is Aranea
rm -f "$state"
"$repo_root/hooks/post-boot"
state_is on
splash_is tokyo-night
"$repo_root/hooks/post-boot"
state_is off
# default means an upgrade may just have reset it: leave the record alone.
printf on >"$state"
splash_is default
"$repo_root/hooks/post-boot"
state_is on
# A failing query changes nothing and does not fail the hook.
touch "$ARANEA_TEST_SANDBOX/current-fails"
"$repo_root/hooks/post-boot"
state_is on
rm -f "$ARANEA_TEST_SANDBOX/current-fails"

# post-update restores only when the record says on and the splash is default.
printf on >"$state"
splash_is default
out="$("$repo_root/hooks/post-update")"
grep -Fxq 'set-by-theme aranea' "$calls"
grep -Fq 'Aranea boot splash' <<<"$out"
for case_name in off-default on-aranea on-other none-default; do
  case "$case_name" in
    off-default)
      printf off >"$state"
      splash_is default
      ;;
    on-aranea)
      printf on >"$state"
      splash_is aranea
      ;;
    on-other)
      printf on >"$state"
      splash_is tokyo-night
      ;;
    none-default)
      rm -f "$state"
      splash_is default
      ;;
  esac
  "$repo_root/hooks/post-update" >/dev/null
  ! grep -q '^set-by-theme' "$calls" || {
    echo "post-update acted for $case_name" >&2
    exit 1
  }
done

# Aranea not installed: nothing to restore from.
printf on >"$state"
splash_is default
rmdir "$HOME/.config/omarchy/themes/aranea"
"$repo_root/hooks/post-update" >/dev/null
if grep -q '^set-by-theme' "$calls"; then
  echo 'unexpected restore' >&2
  exit 1
fi
mkdir "$HOME/.config/omarchy/themes/aranea"

# A failing restore warns but never fails the update.
touch "$ARANEA_TEST_SANDBOX/set-fails"
splash_is default
status=0
out="$("$repo_root/hooks/post-update" 2>&1)" || status=$?
[[ $status == 0 ]]
grep -Fiq 'warning' <<<"$out"
rm -f "$ARANEA_TEST_SANDBOX/set-fails"

# aranea-boot-splash on / off / status.
rm -f "$state"
splash_is default
"$repo_root/scripts/aranea-boot-splash" on >/dev/null
grep -Fxq 'set-by-theme aranea' "$calls"
state_is on
splash_is aranea
"$repo_root/scripts/aranea-boot-splash" off >/dev/null
grep -Fxq 'reset' "$calls"
state_is off
out="$("$repo_root/scripts/aranea-boot-splash" status)"
grep -Fq 'off' <<<"$out"
grep -Fq 'default' <<<"$out"
# A failed switch leaves the record alone and reports failure.
touch "$ARANEA_TEST_SANDBOX/set-fails"
if "$repo_root/scripts/aranea-boot-splash" on >/dev/null 2>&1; then
  echo "on ignored a failure" >&2
  exit 1
fi
state_is off
if "$repo_root/scripts/aranea-boot-splash" bogus >/dev/null 2>&1; then
  echo "bogus accepted" >&2
  exit 1
fi

# The installer and uninstaller handle the hook.
# shellcheck disable=SC2016
grep -Fq 'run omarchy hook install post-update "$repo_root/hooks/post-update"' "$repo_root/scripts/install.sh"
hooks="$HOME/.config/omarchy/hooks"
mkdir -p "$hooks/post-update.d"
cp "$repo_root/hooks/post-update" "$hooks/post-update.d/post-update"
printf on >"$state"
PATH="${PATH#"$fake:"}" "$repo_root/scripts/uninstall.sh" --yes >/dev/null
[[ ! -e "$hooks/post-update.d/post-update" && ! -e "$state" ]]
