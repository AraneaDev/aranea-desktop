#!/usr/bin/env bash
# Real repair/release lifecycle for the unified Clock's nested preferences.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
# Starts an independent config, with unrelated once-only widgets already placed.
fixture() {
  config="$TMPDIR/$1/shell.json"
  export ARANEA_STATE_ROOT="$TMPDIR/$1/state"
  mkdir -p "$(dirname "$config")" "$ARANEA_STATE_ROOT"
  touch "$ARANEA_STATE_ROOT/notifications-widget-placed" "$ARANEA_STATE_ROOT/health-widget-placed"
  printf '%s\n' "$2" >"$config"
}
# Marks only the requested plugin controllers as deployed next to the config.
deploy() {
  local plugin
  for plugin in "$@"; do
    mkdir -p "$(dirname "$config")/plugins/araneadev.$plugin"
    printf '{}\n' >"$(dirname "$config")/plugins/araneadev.$plugin/manifest.json"
  done
}
# Applies the real theme-entry command.
repair() { "$repo_root/scripts/repair-shell-config" "$config" >/dev/null; }
# Applies the real theme-leave command.
release() { "$repo_root/scripts/release-shell-config" "$config" >/dev/null; }
# Checks rewritten JSON and names the broken user-facing contract.
check() {
  jq -e "$1" "$config" >/dev/null || {
    echo "FAIL: $2" >&2
    exit 1
  }
}
# Models an independent user preference change between lifecycle commands.
edit() {
  jq "$1" "$config" >"$config.next"
  cat "$config.next" >"$config"
  rm "$config.next"
}

fixture merged '{"bar":{"layout":{"center":[{"id":"omarchy.clock","format":"HH:mm","weekStartDay":1},{"id":"omarchy.elsewhen","cities":[{"name":"UTC","zone":"UTC"}],"custom":"world"},{"id":"omarchy.weather","unit":"f","refreshMinutes":17},"user.widget"]}},"custom":"top"}'
deploy clock worldclock weather
repair
check '(.bar.layout.center|map(if type=="string" then . else .id end))==["araneadev.clock","user.widget"] and .bar.layout.center[0].format=="HH:mm" and .bar.layout.center[0].weekStartDay==1 and .bar.layout.center[0].worldClock=={cities:[{name:"UTC",zone:"UTC"}],custom:"world"} and .bar.layout.center[0].weather=={unit:"f",refreshMinutes:17} and .custom=="top"' 'one clock owns all saved preferences without separate icons'
check '([.plugins[]|if type=="string" then . else .id end]|index("araneadev.weather"))!=null and ([.plugins[]|if type=="string" then . else .id end]|index("araneadev.worldclock"))!=null' 'hosted clone IDs remain enabled for native shell shortcut resolution'
cp "$config" "$TMPDIR/merged-once"
repair
cmp "$config" "$TMPDIR/merged-once"
edit '.bar.layout.center[0].worldClock.cities=[{name:"London",zone:"Europe/London",home:true}] | .bar.layout.center[0].weather.unit="c" | .bar.layout.center[0].format="yyyy-MM-dd HH:mm" | .bar.layout.center += [{id:"user.added",keep:true}]'
release
check '(.bar.layout.center|map(if type=="string" then . else .id end))==["omarchy.clock","omarchy.elsewhen","omarchy.weather","user.widget","user.added"] and .bar.layout.center[0].format=="yyyy-MM-dd HH:mm" and .bar.layout.center[0].weekStartDay==1 and (.bar.layout.center[0]|has("araneaClockMigration")|not) and .bar.layout.center[1].cities==[{name:"London",zone:"Europe/London",home:true}] and .bar.layout.center[1].custom=="world" and .bar.layout.center[2]=={id:"omarchy.weather",unit:"c",refreshMinutes:17}' 'release restores positions and current edited preferences'
cp "$config" "$TMPDIR/released-once"
release
cmp "$config" "$TMPDIR/released-once"
repair
check '.bar.layout.center[0].worldClock.cities==[{name:"London",zone:"Europe/London",home:true}] and .bar.layout.center[0].weather.unit=="c" and (.bar.layout.center|length)==3' 'theme return retains edited nested settings'

fixture strings '{"bar":{"layout":{"left":["omarchy.weather"],"center":["omarchy.clock"],"custom":["user.before","omarchy.elsewhen","user.after"]}}}'
deploy clock worldclock weather
repair
check '.bar.layout.left==[] and .bar.layout.custom==["user.before","user.after"] and .bar.layout.center[0].weather=={} and .bar.layout.center[0].worldClock=={}' 'string entries and custom sections consolidate'
release
check '.bar.layout.left==["omarchy.weather"] and .bar.layout.center==["omarchy.clock"] and .bar.layout.custom==["user.before","omarchy.elsewhen","user.after"]' 'unchanged original string shapes and positions round-trip'

fixture partial '{"bar":{"layout":{"center":["omarchy.clock",{"id":"omarchy.elsewhen","cities":[]},{"id":"omarchy.weather","unit":"f"}]}}}'
deploy clock worldclock
repair
check '(.bar.layout.center|map(if type=="string" then . else .id end))==["araneadev.clock","omarchy.weather"] and .bar.layout.center[0].worldClock.cities==[] and (.bar.layout.center[0]|has("weather")|not)' 'only deployed optional controllers consolidate'

fixture absent '{"bar":{"layout":{"center":[{"id":"omarchy.elsewhen","cities":[{"name":"UTC","zone":"UTC"}]},"omarchy.weather"]}}}'
deploy clock worldclock weather
repair
check '(.bar.layout.center|map(if type=="string" then . else .id end))==["araneadev.worldclock","araneadev.weather"]' 'without a mounted clock standalone widgets remain'

fixture nested '{"bar":{"layout":{"center":[{"id":"omarchy.clock","worldClock":{"cities":[{"name":"London","zone":"Europe/London"}]},"weather":{"unit":"c"}}, {"id":"omarchy.elsewhen","cities":[{"name":"UTC","zone":"UTC"}]},{"id":"omarchy.weather","unit":"f"}]}}}'
deploy clock worldclock weather
repair
check '.bar.layout.center[0].worldClock.cities==[{name:"London",zone:"Europe/London"}] and .bar.layout.center[0].weather.unit=="c"' 'existing nested preferences win over stale standalone copies'
release
check '.bar.layout.center[0].worldClock.cities==[{name:"London",zone:"Europe/London"}] and .bar.layout.center[0].weather.unit=="c" and .bar.layout.center[1].cities==[{name:"London",zone:"Europe/London"}]' 'pre-existing nested preferences remain on theme release'

fixture unavailable-clock '{"bar":{"layout":{"center":["araneadev.clock",{"id":"omarchy.elsewhen","cities":[]},"omarchy.weather"]}}}'
deploy worldclock weather
repair
check '(.bar.layout.center|map(if type=="string" then . else .id end))==["araneadev.clock","araneadev.worldclock","araneadev.weather"]' 'a missing clock plugin leaves standalone controls available'

fixture before-clock '{"bar":{"layout":{"center":[{"id":"omarchy.weather","unit":"f"},"user.a",{"id":"omarchy.elsewhen","cities":[]},"omarchy.clock","user.b"]}}}'
deploy clock worldclock weather
repair
check '(.bar.layout.center|map(if type=="string" then . else .id end))==["user.a","araneadev.clock","user.b"]' 'consolidation works when both controls precede Clock'
release
check '.bar.layout.center==[{id:"omarchy.weather",unit:"f"},"user.a",{id:"omarchy.elsewhen",cities:[]},"omarchy.clock","user.b"]' 'both original pre-clock positions round-trip'

fixture staged '{"bar":{"layout":{"center":["omarchy.clock",{"id":"omarchy.elsewhen","cities":[]},{"id":"omarchy.weather","unit":"f"}]}}}'
deploy clock worldclock
repair
deploy weather
repair
release
check '.bar.layout.center==["omarchy.clock",{id:"omarchy.elsewhen",cities:[]},{id:"omarchy.weather",unit:"f"}]' 'staged optional deployment restores the original order'

fixture distinct '{"bar":{"layout":{"center":["omarchy.clock",{"id":"omarchy.elsewhen","cities":[{"name":"London","zone":"Europe/London"}]}],"custom":[{"id":"omarchy.elsewhen","cities":[{"name":"Tokyo","zone":"Asia/Tokyo"}],"custom":"keep"}]}}}'
deploy clock worldclock weather
repair
release
check '.bar.layout.center[1].cities==[{name:"London",zone:"Europe/London"}] and .bar.layout.custom[0]=={id:"omarchy.elsewhen",cities:[{name:"Tokyo",zone:"Asia/Tokyo"}],custom:"keep"}' 'unchanged duplicate sources retain distinct original preferences'
repair
edit '.bar.layout.center[0].worldClock.cities=[{name:"UTC",zone:"UTC"}]'
release
check '.bar.layout.center[1].cities==[{name:"UTC",zone:"UTC"}] and .bar.layout.custom[0]=={id:"omarchy.elsewhen",cities:[{name:"UTC",zone:"UTC"}],custom:"keep"}' 'only edited nested keys propagate to restored sources'

fixture deleted '{"bar":{"layout":{"center":["omarchy.clock",{"id":"omarchy.weather","unit":"f","custom":"remove-me"}]}}}'
deploy clock weather
repair
edit 'del(.bar.layout.center[0].weather.custom)'
release
check '.bar.layout.center[1]=={id:"omarchy.weather",unit:"f"}' 'deleted nested preference keys stay deleted on release'

fixture deleted-preset '{"bar":{"layout":{"center":[{"id":"omarchy.clock","weather":{"unit":"f","custom":"preset"}},{"id":"omarchy.weather","unit":"c","custom":"remove-me","sourceOnly":"keep"}]}}}'
deploy clock weather
repair
edit 'del(.bar.layout.center[0].weather.custom)'
release
check '.bar.layout.center[0].weather=={unit:"f"} and .bar.layout.center[1]=={id:"omarchy.weather",unit:"f",sourceOnly:"keep"}' 'preset nested preference deletion also survives release'

fixture source-order '{"bar":{"layout":{"center":[{"id":"omarchy.clock","worldClock":{"cities":[{"name":"London","zone":"Europe/London"}]}},{"id":"omarchy.elsewhen","cities":[{"name":"UTC","zone":"UTC"}]}],"aaa":[{"id":"omarchy.elsewhen","cities":[{"name":"Tokyo","zone":"Asia/Tokyo"}]}]}}}'
deploy clock worldclock
repair
release
check '.bar.layout.center[1].cities==[{name:"London",zone:"Europe/London"}] and .bar.layout.aaa[0].cities==[{name:"Tokyo",zone:"Asia/Tokyo"}]' 'preset preferences apply to the primary source without sorting metadata ownership'

fixture registry-existing '{"plugins":[{"id":"user.plugin","custom":true},{"id":"araneadev.weather","custom":"keep"},"araneadev.worldclock"],"bar":{"layout":{"center":["omarchy.clock"]}}}'
deploy clock worldclock weather
repair
check '([.plugins[]|select(type=="object" and .id=="araneadev.worldclock")]|length)==1 and ([.plugins[]|select(type=="object" and .id=="araneadev.weather")])==[{id:"araneadev.weather",custom:"keep"}] and ([.plugins[]|select(type=="object" and .id=="user.plugin")])==[{id:"user.plugin",custom:true}]' 'hosted registration preserves existing plugin objects and normalizes legacy string IDs'

fixture symlink '{"bar":{"layout":{"center":["omarchy.clock","omarchy.elsewhen","omarchy.weather"]}}}'
deploy clock worldclock weather
mv "$config" "$config.real"
ln -s shell.json.real "$config"
repair
[[ -L "$config" ]]
check '(.bar.layout.center|length)==1' 'repair writes through the symlink'
release
[[ -L "$config" ]]
check '.bar.layout.center==["omarchy.clock","omarchy.elsewhen","omarchy.weather"]' 'release writes through the symlink'
printf 'clock shell config: ok\n'
