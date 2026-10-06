#!/usr/bin/env bash
# Focused-display observations and owner confirmation for aranea-settings.
# Caller supplies scratch, error_code and the target/mode/validation observations.
# shellcheck disable=SC2154
# This module never evaluates monitor configuration or writes preferences.
display_owner="${ARANEA_DISPLAY_OWNER:-omarchy}"
display_hyprctl="${ARANEA_HYPRCTL:-hyprctl}"
display_config="$HOME/.config/hypr/monitors.lua"
# Recognize owner saving support separately from conservative literal readback.
display_persistence() {
  display_support=unsupported
  display_configured=null
  if [[ -e "$display_config" && ! -r "$display_config" ]]; then
    display_support=unknown
  elif [[ -f "$display_config" ]]; then
    local literal=''
    # Match the owner's generic-config predicates, including trailing comments.
    if grep -q '^local omarchy_monitor_scale = ' "$display_config"; then
      display_support=supported
      literal="$(sed -nE 's/^local omarchy_monitor_scale = ([0-9]+([.][0-9]+)?)([[:space:]]*--.*)?[[:space:]]*$/\1/p' "$display_config")"
    elif grep -Eq '^hl\.monitor\(\{ output = "", mode = "preferred", position = "auto", scale = ("auto"|[0-9.]+) \}\)' "$display_config"; then
      display_support=supported
      literal="$(sed -nE 's/^hl\.monitor\(\{ output = "", mode = "preferred", position = "auto", scale = ([0-9]+([.][0-9]+)?) \}\)([[:space:]]*--.*)?[[:space:]]*$/\1/p' "$display_config")"
    fi
    # Nonliteral expressions may be save-capable but are never interpreted.
    if [[ "$literal" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      display_configured="$(jq -cn --arg scale "$literal" '$scale | tonumber')"
    fi
  fi
}
# Read monitor JSON, retaining identity even when the scaling owner is missing.
read_display() {
  display_persistence
  local availability=unavailable
  echo null >"$scratch/focused-display"
  echo '[]' >"$scratch/monitors"
  if command -v "$display_hyprctl" >/dev/null 2>&1 &&
    "$display_hyprctl" monitors -j >"$scratch/monitors" 2>"$scratch/display.err" &&
    jq -e 'type == "array"' "$scratch/monitors" >/dev/null 2>&1; then
    jq -ce '[.[] | select(.focused == true)] | if length == 1 then .[0] else null end |
      select((.name | type == "string" and test("^[A-Za-z0-9._-]+$")) and
        (.scale | type == "number" and . > 0) and
        (.width | type == "number" and . > 0 and . == floor) and
        (.height | type == "number" and . > 0 and . == floor))' "$scratch/monitors" >"$scratch/focused-display" 2>/dev/null || echo null >"$scratch/focused-display"
    if [[ "$(cat "$scratch/focused-display")" != null ]] && command -v "$display_owner" >/dev/null 2>&1 &&
      { [[ "$display_owner" != omarchy ]] || command -v omarchy-hyprland-monitor-scaling >/dev/null 2>&1; }; then
      availability=available
    fi
  fi
  if ! jq -e 'type == "array"' "$scratch/monitors" >/dev/null 2>&1; then echo '[]' >"$scratch/monitors"; fi
  jq -cn --slurpfile monitor "$scratch/focused-display" --arg availability "$availability" \
    --arg support "$display_support" --argjson configured "$display_configured" \
    '{monitor:$monitor[0].name,scale:$monitor[0].scale,width:$monitor[0].width,height:$monitor[0].height,
      availability:$availability,persistenceSupport:$support,configuredScale:$configured}' >"$scratch/display"
}
# Predict the installed owner's clean 1/120 fraction from the observed mode.
display_expected_scale() {
  awk -v scale="$1" -v width="$2" -v height="$3" '
    function gcd(a,b,t) { while (b) { t=a%b; a=b; b=t } return a }
    BEGIN { g=gcd(width*120,height*120); k=int(scale*120+0.5); if(k>g)k=g;
      while(g%k!=0)k++; printf "%.12g\n",k/120 }'
}
# Confirm display identity, clean effective scale and literal persistence after apply.
confirm_display_scale() {
  local confirmed=false persistence=unconfirmed
  if [[ "$(jq -r '.availability' "$scratch/display")" != available ]]; then
    [[ -n "$error_code" ]] || invalid APPLICATION_NOT_CONFIRMED 'Focused display could not be read after application. Check the compositor and helper, then Retry.' 1
  elif [[ "$(jq -r '.monitor' "$scratch/display")" != "$display_target" ]]; then
    [[ -n "$error_code" ]] || invalid FOCUS_CHANGED 'Focused display changed during application. Review the focused display and Apply again.' 1
  elif ! jq -e --argjson expected "$display_expected" --argjson width "$display_width" --argjson height "$display_height" \
    '.availability == "available" and .width == $width and .height == $height and .scale != null and ((.scale - $expected) | fabs) < 0.00001' "$scratch/display" >/dev/null; then
    [[ -n "$error_code" ]] || invalid APPLICATION_NOT_CONFIRMED 'Display scale was not confirmed. Check the current scale and helper diagnostics, then Apply again.' 1
  elif [[ -z "$error_code" ]]; then
    confirmed=true
  fi
  if [[ "$display_support" == unsupported ]]; then
    persistence=session-only
  elif [[ "$display_support" == supported ]] && jq -e --argjson expected "$display_expected" \
    '.configuredScale != null and ((.configuredScale - $expected) | fabs) < 0.00001' "$scratch/display" >/dev/null && [[ "$display_validation_failed" == false ]]; then
    persistence=persisted
  fi
  local effective
  effective="$(jq -c --arg monitor "$display_target" '[.[] | select(.name == $monitor and (.scale | type == "number")) | .scale] | if length == 1 then .[0] else null end' "$scratch/monitors")"
  jq -cn --argjson effective "$effective" --argjson width "$display_width" --argjson height "$display_height" --arg requested "$3" --arg monitor "$display_target" --argjson expected "$display_expected" \
    --argjson confirmed "$confirmed" --arg persistence "$persistence" \
    '{displayScale:{requested:$requested,monitor:$monitor,width:$width,height:$height,expectedScale:$expected,
      effectiveScale:$effective,confirmed:$confirmed,persistence:$persistence}}' >"$scratch/result"
}
