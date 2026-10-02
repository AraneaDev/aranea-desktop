#!/usr/bin/env bash
# Behaviour of `scripts/capture-screenshots --surface network|bluetooth|vpn|clock`:
# the dropdown is summoned, handed stand-in display data (names for
# Network/Bluetooth, a place for Clock, both via `showcase`; rows for VPN via
# `showcaseFixture`; defaults, or ARANEA_CAPTURE_* overrides), given time to
# draw, grabbed and hidden. A non-"ok" answer, or a failed summon, fails the
# surface with exit 3 and no screenshot, so no real data ever reaches one.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

capture="$repo_root/scripts/capture-screenshots"
bin="$ARANEA_TEST_SANDBOX/showcase-bin"
out="$ARANEA_TEST_SANDBOX/shots"
log="$ARANEA_TEST_SANDBOX/calls.log"
mkdir -p "$bin" "$out"

# omarchy-shell answers "ok" to summon, showcase and showcaseFixture
# (showcase/showcaseFixture answer SHOWCASE_ANSWER when set) and logs every
# call, one argument per field. Like qs, it reads an argument that starts
# with "[" as a list, so a bare JSON array never reaches the method as one
# string.
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
  showcase | showcaseFixture)
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
vpn_default='[{"name":"Office (Firebox)","label":"OpenVPN","kind":"nm","connected":true,"ip":"10.20.4.17","server":"vpn.example.com","upMinutes":72},{"name":"Azure (Contoso)","label":"Azure VPN Client","kind":"app","connected":true,"upMinutes":23},{"name":"Client A","label":"OpenVPN","kind":"nm","connected":false},{"name":"GlobalProtect (HQ)","label":"GlobalProtect","kind":"app","connected":false},{"name":"Azure (Fabrikam)","label":"Azure VPN Client","kind":"app","connected":false}]'
clock_default='{"name":"Amsterdam","latitude":52.37,"longitude":4.90}'

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

# --- VPN: default fixture rows (summon araneadev.vpn, showcaseFixture on
# aranea.vpn), then grim, then hide. No real VPN profile is ever named.
: >"$log"
"$capture" --surface vpn --output "$out" >/dev/null
test -f "$out/vpn.png"
assert_calls_in_order 'vpn: summon, showcaseFixture defaults, grim, hide' \
  'omarchy-shell [shell] [summon] [araneadev.vpn]' \
  "omarchy-shell [aranea.vpn] [showcaseFixture] [ $vpn_default]" \
  'grim' \
  'omarchy-shell [shell] [hide] [araneadev.vpn]'

# --- VPN: the fixture rows are overridable.
: >"$log"
rm -f "$out/vpn.png"
ARANEA_CAPTURE_VPN_FIXTURE='[{"name":"Solo","kind":"nm","connected":false}]' \
  "$capture" --surface vpn --output "$out" >/dev/null
grep -Fxq 'omarchy-shell [aranea.vpn] [showcaseFixture] [ [{"name":"Solo","kind":"nm","connected":false}]]' "$log"

# --- Clock: default stand-in place (Amsterdam), then grim, then hide. The
# README must never show the user's real area.
: >"$log"
"$capture" --surface clock --output "$out" >/dev/null
test -f "$out/clock.png"
assert_calls_in_order 'clock: summon, showcase default place, grim, hide' \
  'omarchy-shell [shell] [summon] [omarchy.clock]' \
  "omarchy-shell [omarchy.clock] [showcase] [$clock_default]" \
  'sleep 1' \
  'grim' \
  'omarchy-shell [shell] [hide] [omarchy.clock]'

# --- Clock: the stand-in place is overridable.
: >"$log"
rm -f "$out/clock.png"
ARANEA_CAPTURE_CLOCK_PLACE='{"name":"Testville","latitude":1,"longitude":2}' \
  "$capture" --surface clock --output "$out" >/dev/null
grep -Fxq 'omarchy-shell [omarchy.clock] [showcase] [{"name":"Testville","latitude":1,"longitude":2}]' "$log"

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

# --- A showcaseFixture answer that isn't "ok" fails the vpn surface the same
# way: exit 3, a clear message, no screenshot, dropdown hidden. A real VPN
# profile must never reach a screenshot because the fixture call failed.
for answer in 'Function not found.' 'invalid' 'closed' ''; do
  : >"$log"
  rm -f "$out/vpn.png"
  status=0
  errors="$(SHOWCASE_ANSWER="$answer" "$capture" --surface vpn --output "$out" 2>&1 >/dev/null)" || status=$?
  if ((status != 3)) || [[ -e "$out/vpn.png" ]] || grep -Fxq grim "$log"; then
    printf 'vpn: a showcaseFixture answer of "%s" must fail without a screenshot (status %s)\n' "$answer" "$status" >&2
    exit 1
  fi
  grep -Fq 'fixture rows' <<<"$errors" || {
    printf 'vpn: the failure must say why: %s\n' "$errors" >&2
    exit 1
  }
  grep -Fxq 'omarchy-shell [shell] [hide] [araneadev.vpn]' "$log" || {
    echo 'vpn: a failed showcaseFixture must hide the dropdown' >&2
    exit 1
  }
done

# --- A showcase answer that isn't "ok" fails the clock surface the same way:
# exit 3, a clear message, no screenshot, dropdown hidden. The user's real
# area must never reach a screenshot because the showcase call failed.
for answer in 'Function not found.' 'invalid' 'closed' ''; do
  : >"$log"
  rm -f "$out/clock.png"
  status=0
  errors="$(SHOWCASE_ANSWER="$answer" "$capture" --surface clock --output "$out" 2>&1 >/dev/null)" || status=$?
  if ((status != 3)) || [[ -e "$out/clock.png" ]] || grep -Fxq grim "$log"; then
    printf 'clock: a showcase answer of "%s" must fail without a screenshot (status %s)\n' "$answer" "$status" >&2
    exit 1
  fi
  grep -Fq 'stand-in place' <<<"$errors" || {
    printf 'clock: the failure must say why: %s\n' "$errors" >&2
    exit 1
  }
  grep -Fxq 'omarchy-shell [shell] [hide] [omarchy.clock]' "$log" || {
    echo 'clock: a failed showcase must hide the dropdown' >&2
    exit 1
  }
done

# --- A summon that fails (omarchy-shell down) is the scripted exit 3 with
# no screenshot and no showcase call, not a set -e abort.
for surface in network bluetooth clock; do
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

# --- A failed vpn summon is the same scripted exit 3, with no screenshot and
# no showcaseFixture call (the real profiles are never at risk).
: >"$log"
rm -f "$out/vpn.png"
status=0
errors="$(SUMMON_FAILS=1 "$capture" --surface vpn --output "$out" 2>&1 >/dev/null)" || status=$?
if ((status != 3)) || [[ -e "$out/vpn.png" ]] || grep -Fq '[showcaseFixture]' "$log"; then
  printf 'vpn: a failed summon must exit 3 without a screenshot (status %s): %s\n' "$status" "$errors" >&2
  exit 1
fi
grep -Fq 'Unable to summon popup araneadev.vpn' <<<"$errors"

echo "capture showcase behaviour passed"
