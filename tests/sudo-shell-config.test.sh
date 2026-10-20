#!/usr/bin/env bash
# Real shell JSON migration, restoration and user-edit preservation contracts.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
# Starts a fresh shell config and independent once-only placement state.
fixture() {
  config="$TMPDIR/$1/shell.json"
  export ARANEA_STATE_ROOT="$TMPDIR/$1/state"
  mkdir -p "$(dirname "$config")" "$ARANEA_STATE_ROOT"
  # Keep unrelated once-only widgets out of these exact layout assertions.
  touch "$ARANEA_STATE_ROOT/notifications-widget-placed" "$ARANEA_STATE_ROOT/health-widget-placed"
  printf '%s\n' "$2" >"$config"
}
# Marks the new widget as deployed beside this fixture config.
deployed() {
  mkdir -p "$(dirname "$config")/plugins/araneadev.sudo"
  printf '{}\n' >"$(dirname "$config")/plugins/araneadev.sudo/manifest.json"
}
# Applies the real repair command to the current fixture.
repair() { "$repo_root/scripts/repair-shell-config" "$config" >/dev/null; }
# Applies the real theme-leave command to the current fixture.
release() { "$repo_root/scripts/release-shell-config" "$config" >/dev/null; }
# Checks actual rewritten JSON and reports the behavior that failed.
check() { jq -e "$1" "$config" >/dev/null || {
  echo "FAIL: $2" >&2
  exit 1
}; }
# Simulates a user shell JSON edit between lifecycle commands.
edit() {
  jq "$1" "$config" >"$config.next"
  mv "$config.next" "$config"
}

fixture defaults '{"bar":{"layout":{"center":["omarchy.indicators","user.widget"]}},"cities":["keep"]}'
repair
check '.bar.layout.center == ["omarchy.indicators","user.widget"]' 'undeployed sudo leaves stock selection alone'
deployed
repair
check '(.bar.layout.center|map(if type=="string" then . else .id end)) == ["omarchy.indicators","araneadev.sudo","user.widget"] and .bar.layout.center[0].items == ["ScreenRecording","RemoteSession","Reminder","NightLight","Dnd","StayAwake"] and .cities==["keep"]' 'deployed default splits only PasswordlessSudo adjacent to indicators'
cp "$config" "$TMPDIR/repaired"
repair
cmp "$config" "$TMPDIR/repaired"
release
check '.bar.layout.center == ["omarchy.indicators","user.widget"]' 'release restores string entry and default field absence'
repair
check '(.bar.layout.center|map(if type=="string" then . else .id end)|index("araneadev.sudo")) != null' 'parked sudo returns'
edit '.bar.layout.center |= map(select((if type=="string" then . else .id end)!="araneadev.sudo"))'
repair
release
repair
check '([.bar.layout[][]|if type=="string" then . else .id end]|index("araneadev.sudo")) == null' 'explicit widget removal survives repair and theme return'
check 'all(.bar.layout[][]|select((if type=="string" then . else .id end)=="omarchy.indicators"); type=="object" and ((.araneaSudoHostHidden==true) or all(.items[]; (if type=="string" then . else .id end)!="PasswordlessSudo")))' 'removed control does not reappear as the stock red indicator after theme return'

fixture custom '{"bar":{"layout":{"left":[{"id":"omarchy.indicators","alwaysShow":true,"items":["Dnd",{"id":"PasswordlessSudo","duration":45,"custom":"keep"},"NightLight"],"indicators":["Reminder"]}],"right":[]}}}'
deployed
repair
check '.bar.layout.left[0].items==["Dnd","NightLight"] and .bar.layout.left[0].indicators==["Reminder"] and .bar.layout.left[0].alwaysShow and .bar.layout.left[1].nativeSettings=={duration:45,custom:"keep"}' 'native items priority and nested sudo settings preserved'
edit '.bar.layout.left[0].items=[{id:"Dnd",changed:true},"ScreenRecording","NightLight"] | .bar.layout.left[0].newSetting="user"'
release
check '.bar.layout.left[0].items==[{id:"Dnd",changed:true},{id:"PasswordlessSudo",duration:45,custom:"keep"},"ScreenRecording","NightLight"] and .bar.layout.left[0].newSetting=="user" and .bar.layout.left[0].indicators==["Reminder"]' 'release restores sudo position without clobbering other edited entries'

fixture fallback '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":[],"indicators":["NightLight","PasswordlessSudo","Dnd"]}]}}}'
deployed
repair
check '.bar.layout.center[0].items==[] and .bar.layout.center[0].indicators==["NightLight","Dnd"]' 'empty items fall through to nonempty indicators'
release
check '.bar.layout.center[0]=={id:"omarchy.indicators",items:[],indicators:["NightLight","PasswordlessSudo","Dnd"]}' 'fallback source exact round trip'

fixture precedence-edit '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":[],"indicators":["PasswordlessSudo","Dnd"]}]}}}'
deployed
repair
edit '.bar.layout.center[0].items=["NightLight"]'
repair
check '.bar.layout.center[0].items==["NightLight"] and .bar.layout.center[0].indicators==["PasswordlessSudo","Dnd"]' 'a higher priority source edit preserves the old inactive indicator list'
release
check '.bar.layout.center[0]=={id:"omarchy.indicators",items:["NightLight"],indicators:["PasswordlessSudo","Dnd"]}' 'release preserves both fields after a higher priority source change'

fixture precedence-sudo '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":[],"indicators":["PasswordlessSudo","Dnd"]}]}}}'
deployed
repair
edit '.bar.layout.center[0].items=["NightLight",{id:"PasswordlessSudo",custom:"new-source"}]'
repair
check '.bar.layout.center[0].items==["NightLight"] and .bar.layout.center[0].indicators==["PasswordlessSudo","Dnd"] and .bar.layout.center[0].araneaSudoMigration.field=="items"' 'a new selected source projects sudo without clobbering the old inactive field'
release
check '.bar.layout.center[0]=={id:"omarchy.indicators",items:["NightLight",{id:"PasswordlessSudo",custom:"new-source"}],indicators:["PasswordlessSudo","Dnd"]}' 'the new source sudo settings and both fields survive release'

fixture precedence-fallback '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":["PasswordlessSudo","Dnd"],"indicators":["NightLight","PasswordlessSudo"]}]}}}'
deployed
repair
edit '.bar.layout.center[0].items=[]'
repair
check '.bar.layout.center[0].items==[] and .bar.layout.center[0].indicators==["NightLight"] and .bar.layout.center[0].araneaSudoMigration.field=="indicators"' 'clearing items intentionally switches to indicators without undoing the edit'
release
check '.bar.layout.center[0]=={id:"omarchy.indicators",items:[],indicators:["NightLight","PasswordlessSudo"]}' 'release retains the deliberately cleared higher priority source'

fixture sole '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":[{"id":"PasswordlessSudo","duration":9}]}]}}}'
deployed
repair
check '.bar.layout.center[0].items==[{id:"PasswordlessSudo",duration:9}] and .bar.layout.center[0].araneaSudoHostHidden==true and .bar.layout.center[1].nativeSettings=={duration:9}' 'sole sudo preserves native IPC host and hides its visual slot'
release
check '.bar.layout.center==[{id:"omarchy.indicators",items:[{id:"PasswordlessSudo",duration:9}]}]' 'sole host release removes internal metadata and hide flag'

fixture sole-edited '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":["PasswordlessSudo"]}]}}}'
deployed
repair
edit '.bar.layout.center[0].items += [{id:"Dnd",alwaysShow:true}]'
repair
check '.bar.layout.center[0].items==[{id:"Dnd",alwaysShow:true}] and (.bar.layout.center[0]|has("araneaSudoHostHidden")|not)' 'a later native indicator remains visible after repair of a sole-sudo host'
release
check '.bar.layout.center==[{id:"omarchy.indicators",items:["PasswordlessSudo",{id:"Dnd",alwaysShow:true}]}]' 'sole-host edits survive release'

fixture sole-reset '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":["PasswordlessSudo"]}]}}}'
deployed
repair
edit '.bar.layout.center[0].items=[]'
repair
check '.bar.layout.center[0].items==["ScreenRecording","RemoteSession","Reminder","NightLight","Dnd","StayAwake"] and (.bar.layout.center[0]|has("araneaSudoHostHidden")|not)' 'resetting a sole-host list reveals native defaults without duplicating sudo'
release
check '.bar.layout.center[0].items==["PasswordlessSudo","ScreenRecording","RemoteSession","Reminder","NightLight","Dnd","StayAwake"]' 'reset default selection survives release'

fixture absent '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":["Dnd"],"indicators":["PasswordlessSudo"]}]}}}'
deployed
repair
check '.bar.layout.center==[{id:"omarchy.indicators",items:["Dnd"],indicators:["PasswordlessSudo"]}]' 'explicit selection excluding sudo creates no widget'
check '([.plugins[]|if type=="string" then . else .id end]|index("araneadev.sudo"))==null' 'unselected plugin is not registered'

fixture empty-default '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":[],"indicators":[]}]}}}'
deployed
repair
release
check '.bar.layout.center==[{id:"omarchy.indicators",items:[],indicators:[]}]' 'empty native lists return unchanged after default projection'

fixture edited-default '{"bar":{"layout":{"center":["omarchy.indicators"]}}}'
deployed
repair
edit '.bar.layout.center[0].items += [{id:"UserIndicator",custom:7}] | .bar.layout.center[0].alwaysShow=true'
release
check '.bar.layout.center[0].alwaysShow and .bar.layout.center[0].items==["PasswordlessSudo","ScreenRecording","RemoteSession","Reminder","NightLight","Dnd","StayAwake",{id:"UserIndicator",custom:7}]' 'edited derived defaults retain edits and restore sudo'

fixture symlink '{"bar":{"layout":{"center":["omarchy.indicators"]}}}'
deployed
ln -s "$config" "$TMPDIR/shell-link.json"
real_config="$config"
config="$TMPDIR/shell-link.json"
repair
[[ -L "$config" ]]
release
check '.bar.layout.center==["omarchy.indicators"]' 'symlink repair and release preserve target semantics'
[[ -L "$config" && -f "$real_config.aranea.bak" ]]

fixture duplicates '{"bar":{"layout":{"center":["omarchy.indicators","araneadev.sudo"],"right":[{"id":"araneadev.sudo","nativeSettings":{"duration":12}}]}}}'
deployed
repair
check '([.bar.layout[][]|if type=="string" then . else .id end]|map(select(.=="araneadev.sudo"))|length)==1' 'repeated sudo entries collapse to the first placement'

fixture repeated-native '{"bar":{"layout":{"center":[{"id":"omarchy.indicators","items":[{"id":"PasswordlessSudo","custom":"first"},{"id":"PasswordlessSudo","custom":"second"},"Dnd"]}]}}}'
deployed
repair
edit '.bar.layout.center[0].items += ["NightLight"]'
release
check '.bar.layout.center==[{id:"omarchy.indicators",items:[{id:"PasswordlessSudo",custom:"first"},{id:"PasswordlessSudo",custom:"second"},"Dnd","NightLight"]}]' 'all original native sudo entry settings survive an edited-list round trip'
repair
edit '.bar.layout.center[0].items=["Dnd",{id:"PasswordlessSudo",custom:"user-restored"},"NightLight"]'
release
check '.bar.layout.center==[{id:"omarchy.indicators",items:["Dnd",{id:"PasswordlessSudo",custom:"user-restored"},"NightLight"]}]' 'release retains an explicitly user-restored sudo selection without duplicates'

fixture uninstall '{"bar":{"layout":{"center":["omarchy.indicators"]}},"cities":[{"timezone":"Europe/Amsterdam","label":"keep"}]}'
mkdir -p "$HOME/.config/omarchy"
cp "$config" "$HOME/.config/omarchy/shell.json"
config="$HOME/.config/omarchy/shell.json"
deployed
repair
"$repo_root/scripts/uninstall.sh" --yes --scope integration >/dev/null
check '.bar.layout.center==["omarchy.indicators"] and .cities==[{timezone:"Europe/Amsterdam",label:"keep"}]' 'uninstall reverses migration without touching world clock settings'
[[ ! -d "$HOME/.config/omarchy/plugins/araneadev.sudo" ]]

echo 'PASS sudo shell config deployment guard, defaults, selection, restoration, edits, removal, return and symlinks'
