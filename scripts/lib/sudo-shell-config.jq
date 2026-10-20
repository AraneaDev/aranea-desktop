# Reversible projection of the native PasswordlessSudo indicator into its own
# widget. The native Indicators host remains present for expiry refresh IPC.
def sudo_entry_id: if type == "string" then . else .id? end;
def sudo_defaults: ["PasswordlessSudo","ScreenRecording","RemoteSession","Reminder","NightLight","Dnd","StayAwake"];
def sudo_source:
  if (.items|type) == "array" and (.items|length) > 0 then {field:"items",entries:.items}
  elif (.indicators|type) == "array" and (.indicators|length) > 0 then {field:"indicators",entries:.indicators}
  else {field:"items",entries:sudo_defaults} end;
def sudo_original_entries:
  (if type == "string" then {id:.} else . end)
  |
  if .araneaSudoMigration? then .araneaSudoMigration.selected else sudo_source.entries end;
def sudo_selected: any(sudo_original_entries[];sudo_entry_id == "PasswordlessSudo");
def sudo_restore_indicator:
  if type != "object" then .
  elif (.araneaSudoMigration?|type) != "object" then .
  else .araneaSudoMigration as $saved
    | if .[$saved.field] == $saved.derived then
        if $saved.hadField then .[$saved.field] = $saved.original else del(.[$saved.field]) end
      elif (.[$saved.field]|type) == "array" then
        # Insert removed entries at their original positions. Every current
        # non-sudo entry (including later user additions/settings) stays intact.
        if any(.[$saved.field][];sudo_entry_id == "PasswordlessSudo") then .
        else reduce ($saved.selected|to_entries[]|select(.value|sudo_entry_id == "PasswordlessSudo")) as $removed
          (.; .[$saved.field] |= (.[:$removed.key] + [$removed.value] + .[$removed.key:])) end
      else . end
    | del(.araneaSudoMigration,.araneaSudoHostHidden)
    | if $saved.wasString and keys == ["id"] then .id else . end
  end;
def sudo_project_indicator:
  . as $original | (if type == "string" then {id:.} else . end)
  | if .araneaSudoMigration? then
      # A formerly sole-sudo host may acquire other indicators while Aranea is
      # active. Keep their edits and reveal that host again after reconciliation.
      .araneaSudoMigration.field as $field | sudo_source as $source
      | if $source.field != $field then
          # A nonempty items list can supersede a projected indicators list.
          # Restore only that old list first. Conversely, switching away from
          # items means the user cleared it: do not undo that deliberate edit.
          (if $field == "items" then del(.araneaSudoMigration,.araneaSudoHostHidden)
           else sudo_restore_indicator end)
          | if sudo_selected then sudo_project_indicator else . end
        else ($source.entries|map(select(sudo_entry_id != "PasswordlessSudo"))) as $remaining
          | if ($remaining|length) > 0 then .[$field] = $remaining | del(.araneaSudoHostHidden)
            else .araneaSudoHostHidden = true end
        end
  else sudo_source as $source
    | ($source.entries|map(select(sudo_entry_id != "PasswordlessSudo"))) as $remaining
    | .araneaSudoMigration = {
        wasString:($original|type == "string"),field:$source.field,
        hadField:has($source.field),original:.[$source.field],selected:$source.entries,
        derived:(if ($remaining|length) == 0 then $source.entries else $remaining end)}
    | if ($remaining|length) == 0 then .araneaSudoHostHidden = true
      else .[$source.field] = $remaining end
  end;
def sudo_present: any(.bar.layout[]?|arrays|.[];sudo_entry_id == "araneadev.sudo");
def sudo_dedupe_layout:
  .bar.layout = (reduce (.bar.layout|to_entries[]) as $section ({layout:{},seen:false};
    if ($section.value|type) == "array" then
      .layout[$section.key] = []
      | reduce $section.value[] as $entry (.;
          if ($entry|sudo_entry_id) == "araneadev.sudo" and .seen then .
          else .layout[$section.key] += [$entry]
            | if ($entry|sudo_entry_id) == "araneadev.sudo" then .seen = true else . end end)
    else .layout[$section.key] = $section.value end) | .layout);
def repair_sudo($installed;$place):
  if ($installed|not) or (.bar.layout|type) != "object" then .
  else sudo_present as $present
    | ([.bar.layout|to_entries[]|select(.value|type == "array")
        | .key as $section | .value|to_entries[]
        | select(.value|sudo_entry_id == "omarchy.indicators")
        | select(.value|sudo_selected)
        | {section:$section,index:.key,entry:.value}][0]) as $target
    | if $target == null then .
      else
        ($target.entry|sudo_original_entries|map(select(sudo_entry_id == "PasswordlessSudo"))|.[0]
          | if type == "object" then del(.id) else {} end) as $settings
        | .bar.layout |= with_entries(.value |= (if type == "array" then
            map(if sudo_entry_id == "omarchy.indicators" and sudo_selected then sudo_project_indicator else . end)
          else . end))
        | if $present or ($place|not) then .
          else .bar.layout[$target.section] |= (.[:($target.index+1)] + [{id:"araneadev.sudo",nativeSettings:$settings}] + .[($target.index+1):]) end
        | sudo_dedupe_layout
        | if sudo_present then
            .plugins = ((.plugins // []) + [{id:"araneadev.sudo"}]
              | reduce .[] as $entry ([];if any(.[];sudo_entry_id == ($entry|sudo_entry_id)) then . else .+[$entry] end))
          else . end
      end
  end;
def release_sudo:
  if (.bar.layout|type) == "object" then
    .bar.layout |= with_entries(.value |= (if type == "array" then
      map(if sudo_entry_id == "omarchy.indicators" then sudo_restore_indicator else . end)
    else . end))
  else . end;
