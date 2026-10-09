#!/usr/bin/env bash
# Stateful sandbox-only manager, journal, HTTP and browser effect boundary.
set -euo pipefail
: "${ARANEA_TEST_SANDBOX:?}"
root="$ARANEA_TEST_SANDBOX/manager"
mkdir -p "$root"
name=${0##*/}
printf '%s\0' "$@" >"$root/$name.argv"
case "$name" in
  systemd-run)
    [[ ${1:-} != --version ]] || {
      echo 'systemd 261'
      exit
    }
    unit='' description=''
    for arg in "$@"; do
      case "$arg" in --unit=*) unit=${arg#*=} ;; --description=*) description=${arg#*=} ;; esac
    done
    [[ -n "$unit" && -n "$description" ]]
    echo "$unit" >>"$root/launches"
    mode=$(cat "$root/mode" 2>/dev/null || echo running)
    [[ $mode != reject ]] || exit 1
    active=active sub=running result=success code=0 status=0
    case "$mode" in
      fast) sub=exited code=1 ;;
      failed) active=failed sub=failed result=exit-code code=1 status=7 ;;
      timeout) active=failed sub=failed result=timeout code=2 status=15 ;;
    esac
    cat >"$root/pending" <<PROPS
Id=$unit
LoadState=loaded
Transient=yes
Description=$description
InvocationID=11111111111111111111111111111111
ActiveState=$active
SubState=$sub
Result=$result
ExecMainCode=$code
ExecMainStatus=$status
PROPS
    if [[ $mode == late ]]; then
      # shellcheck disable=SC2016
      setsid bash -c 'sleep 3; cp "$1/pending" "$1/$2"' bash "$root" "$unit" </dev/null >/dev/null 2>&1 &
      sleep 10
      exit
    fi
    cp "$root/pending" "$root/$unit"
    [[ $mode != accepted-error ]] || exit 1
    ;;
  systemctl)
    [[ ! -e "$root/unavailable" ]] || exit 1
    case " $* " in
      *' --property=Version '*) echo Version=261 ;;
      *' show '*)
        [[ ! -e $root/show-delay ]] || sleep "$(cat "$root/show-delay")"
        if [[ -e $root/show-hold ]]; then
          touch "$root/show-entered"
          while [[ -e $root/show-hold ]]; do sleep .01; done
        fi
        if [[ -f $root/${!#} ]]; then
          cat "$root/${!#}"
        else
          printf 'Id=%s\nLoadState=not-found\nTransient=no\nDescription=\nInvocationID=\nActiveState=inactive\nSubState=dead\nResult=success\nExecMainCode=0\nExecMainStatus=0\n' "${!#}"
          exit 1
        fi
        ;;
      *' stop '*)
        echo "${!#}" >>"$root/stops"
        [[ ! -e "$root/stop-fails" ]] || exit 1
        [[ ! -e "$root/stop-no-change" ]] || exit 0
        [[ ! -e "$root/stop-delays" ]] || sleep 10
        if [[ -e "$root/check-release" ]]; then
          jq -e --arg u "${!#}" 'any(.runs[];.unitName==$u and (.processState=="succeeded" or .processState=="failed" or .processState=="stopped") and .submissionUnconfirmed)' "$ARANEA_STATE_ROOT/project-actions.json" >/dev/null
        fi
        if [[ -e $root/gc-on-release ]]; then
          rm -f "$root/${!#}"
          exit 0
        fi
        sed -i -e 's/^ActiveState=.*/ActiveState=inactive/' -e 's/^SubState=.*/SubState=dead/' "$root/${!#}"
        ;;
      *' reset-failed '*) echo "${!#}" >>"$root/resets" ;;
      *) exit 91 ;;
    esac
    ;;
  journalctl)
    full=false
    for arg in "$@"; do [[ $arg != --all ]] || full=true; done
    jq -c --argjson full "$full" --arg b "$(tr -d '-' </proc/sys/kernel/random/boot_id)" '. + (if has("_BOOT_ID") then {} else {_BOOT_ID:$b} end) | if ($full|not) and (.MESSAGE|type)=="string" and (.MESSAGE|utf8bytelength)>4096 then .MESSAGE=null else . end' "$root/journal"
    [[ ! -e $root/journal-malformed ]] || printf '{malformed\n'
    [[ ! -e $root/journal-fails ]] || exit 1
    ;;
  curl) [[ ! -e "$root/unreachable" ]] ;;
  xdg-open) echo opened >>"$root/opened" ;;
  *) exit 92 ;;
esac
