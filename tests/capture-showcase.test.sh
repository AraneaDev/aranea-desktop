#!/usr/bin/env bash
# Behaviour of `scripts/capture-screenshots --surface network|bluetooth` with
# the desktop stubbed: the dropdown is summoned, handed the stand-in names
# through its `showcase` IPC method (the defaults, or the ARANEA_CAPTURE_*
# overrides), given time to draw (the graph delay for Network, the scan delay
# for Bluetooth), grabbed and hidden. A showcase call that doesn't answer "ok"
# (a closed dropdown answers "closed"), or a summon that fails, fails the
# surface with exit 3 and writes no screenshot, so real names never reach one.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

capture="$repo_root/scripts/capture-screenshots"
bin="$ARANEA_TEST_SANDBOX/showcase-bin"
out="$ARANEA_TEST_SANDBOX/shots"
log="$ARANEA_TEST_SANDBOX/calls.log"
mkdir -p "$bin" "$out"

# omarchy-shell answers "ok" to summon and showcase (showcase answers
# SHOWCASE_ANSWER when set) and logs every call, one argument per field.
# Like qs, it reads an argument that starts with "[" as a list, so a bare
# JSON array never reaches the method as one string.
cat >"$bin/omarchy-shell" <<'SH'
#!/usr/bin/env bash
printf 'omarchy-shell'"$(printf ' [%%s]%.0s' "$@")"'\n' "$@" >>"$ARANEA_TEST_SANDBOX/calls.log"
case "$2" in
  summon)
    if [[ "${SUMMON_FAILS:-0}" == 1 ]]; then
      echo 'omarchy-shell is not running' >&2
      exit 1
    fi
    echo ok
    ;;
  showcase)
    if [[ "$3" == "["* ]]; then
      echo 'Too many arguments provided (1 required but 8 were provided.)'
    else
      echo "${SHOWCASE_ANSWER-ok}"
    fi
    ;;
esac
SH
# grim writes the frame and logs it; sleep only logs its seconds.
cat >"$bin/grim" <<'SH'
#!/usr/bin/env bash
printf 'grim\n' >>"$ARANEA_TEST_SANDBOX/calls.log"
printf 'frame\n' >"${@: -1}"
SH
cat >"$bin/sleep" <<'SH'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls.log"
SH
chmod +x "$bin"/*
export PATH="$bin:$PATH"

wifi_default='["Aranea-Home","Neighbour-5G","Cafe-Guest","Library-Free","Studio-2G","Atelier","Harbour-Net","Old-Router"]'
bt_default='["WH-1000XM5","MX Master 3S","Pixel 9","Keychron K3","JBL Flip 6","Xbox Controller","Galaxy Buds2","Kindle"]'

# Fails with MESSAGE unless the call log holds LINES in this order (other
# calls may come between them).
assert_calls_in_order() {
  local message="$1"
  shift
  local -a want=("$@")
  local line next=0
  while IFS= read -r line; do
    ((next < ${#want[@]})) && [[ "$line" == "${want[next]}" ]] && next=$((next + 1))
  done <"$log"
  ((next == ${#want[@]})) || {
    printf '%s\nexpected, in order:\n%s\ngot:\n%s\n' "$message" "$(printf '%s\n' "${want[@]}")" "$(cat "$log")" >&2
    exit 1
  }
}

# --- Network: default names, the 20 s graph delay, then grim, then hide.
: >"$log"
"$capture" --surface network --output "$out" >/dev/null
test -f "$out/network.png"
assert_calls_in_order 'network: summon, showcase defaults, graph wait, grim, hide' \
  'omarchy-shell [shell] [summon] [omarchy.network]' \
  "omarchy-shell [omarchy.network] [showcase] [ $wifi_default]" \
  'sleep 20' \
  'grim' \
  'omarchy-shell [shell] [hide] [omarchy.network]'

# --- Network: names and the graph delay are overridable.
: >"$log"
rm -f "$out/network.png"
ARANEA_CAPTURE_WIFI_NAMES='["Only-One"]' ARANEA_NETWORK_GRAPH_DELAY=0 \
  "$capture" --surface network --output "$out" >/dev/null
assert_calls_in_order 'network: overrides' \
  'omarchy-shell [omarchy.network] [showcase] [ ["Only-One"]]' \
  'sleep 0' \
  'grim'
if grep -Fxq 'sleep 20' "$log"; then
  echo 'network: ARANEA_NETWORK_GRAPH_DELAY=0 must replace the 20 s wait' >&2
  exit 1
fi

# --- Bluetooth: default names, the normal delay plus the scan delay.
: >"$log"
"$capture" --surface bluetooth --output "$out" >/dev/null
test -f "$out/bluetooth.png"
assert_calls_in_order 'bluetooth: summon, showcase defaults, waits, grim, hide' \
  'omarchy-shell [shell] [summon] [omarchy.bluetooth]' \
  "omarchy-shell [omarchy.bluetooth] [showcase] [ $bt_default]" \
  'sleep 1' \
  'sleep 3' \
  'grim' \
  'omarchy-shell [shell] [hide] [omarchy.bluetooth]'
: >"$log"
ARANEA_CAPTURE_BT_NAMES='["Pod"]' "$capture" --surface bluetooth --output "$out" >/dev/null
grep -Fxq 'omarchy-shell [omarchy.bluetooth] [showcase] [ ["Pod"]]' "$log"

# --- A showcase call that isn't "ok" (the stock panel, no answer, bad JSON)
# fails the surface: exit 3, a clear message, no screenshot, dropdown hidden.
for surface in network bluetooth; do
  for answer in 'Function not found.' 'invalid' 'closed' ''; do
    : >"$log"
    rm -f "$out/$surface.png"
    status=0
    errors="$(SHOWCASE_ANSWER="$answer" "$capture" --surface "$surface" --output "$out" 2>&1 >/dev/null)" || status=$?
    if ((status != 3)) || [[ -e "$out/$surface.png" ]] || grep -Fxq grim "$log"; then
      printf '%s: a showcase answer of "%s" must fail without a screenshot (status %s)\n' "$surface" "$answer" "$status" >&2
      exit 1
    fi
    grep -Fq 'stand-in names' <<<"$errors" || {
      printf '%s: the failure must say why: %s\n' "$surface" "$errors" >&2
      exit 1
    }
    grep -Fxq "omarchy-shell [shell] [hide] [omarchy.$surface]" "$log" || {
      printf '%s: a failed showcase must hide the dropdown\n' "$surface" >&2
      exit 1
    }
  done
done

# --- A summon that fails (omarchy-shell down) is the scripted exit 3 with
# no screenshot and no showcase call, not a set -e abort.
for surface in network bluetooth; do
  : >"$log"
  rm -f "$out/$surface.png"
  status=0
  errors="$(SUMMON_FAILS=1 "$capture" --surface "$surface" --output "$out" 2>&1 >/dev/null)" || status=$?
  if ((status != 3)) || [[ -e "$out/$surface.png" ]] || grep -Fq '[showcase]' "$log"; then
    printf '%s: a failed summon must exit 3 without a screenshot (status %s): %s\n' "$surface" "$status" "$errors" >&2
    exit 1
  fi
  grep -Fq "Unable to summon popup omarchy.$surface" <<<"$errors"
done

echo "capture showcase behaviour passed"
