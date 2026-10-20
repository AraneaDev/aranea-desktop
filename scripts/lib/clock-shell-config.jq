# Reversible projection of standalone world-clock/weather settings into Clock.
def clock_entry_id: if type == "string" then . else .id? end;
def clock_canonical_id:
  if . == "omarchy.elsewhen" then "araneadev.worldclock"
  elif . == "omarchy.weather" then "araneadev.weather" else . end;
def clock_settings: if type == "object" then del(.id) else {} end;
def clock_entries:
  [.bar.layout | to_entries[] | select(.value|type == "array")
   | .key as $section | .value | to_entries[]
   | {section:$section,index:.key,entry:.value}];
def clock_project_part($key;$id;$entries):
  (clock_entries | map(select(.entry|clock_entry_id == "araneadev.clock")) | .[0]) as $target
  | ($entries | map(select(.entry|clock_entry_id == $id))) as $sources
  | if $target == null or ($sources|length) == 0 then .
    else
      $target.entry as $original
      | (if ($original|type) == "object" then $original else {id:$original} end) as $owner
      | ($owner.araneaClockMigration // {version:1,wasString:(($original|type)=="string"),parts:{}}) as $meta
      | ($meta.parts[$key] // {hadSetting:($owner|has($key)),records:[]}) as $part
      | ($owner[$key] | if type == "object" then . else ($sources[0].entry|clock_settings) end) as $settings
      | ($part + {baseline:($part.baseline // $settings),records:(reduce ($part.records + $sources)[] as $record ([];if any(.[];. == $record) then . else . + [$record] end))}) as $updated
      | ($owner + {($key):$settings,araneaClockMigration:($meta|.parts[$key]=$updated)}) as $next
      | .bar.layout[$target.section][$target.index] = $next
      | .bar.layout |= with_entries(.value |= (if type == "array" then map(select(clock_entry_id != $id)) else . end))
    end;
def repair_clock($worldclock;$weather):
  if (.bar.layout|type) != "object" then .
  else
    clock_entries as $raw
    | (($raw|map(select(.entry|clock_entry_id == "araneadev.clock"))|.[0].entry
       | if type == "object" then .araneaClockMigration.parts else {} end) // {}) as $prior
    | ([$prior[].records[]]) as $removed
    | ($raw|map(. as $record
        | .index = (reduce ($removed|map(select(.section == $record.section))|sort_by(.index)[]) as $old
            ($record.index; if . >= $old.index then . + 1 else . end)))) as $entries
    | (if $worldclock then clock_project_part("worldClock";"araneadev.worldclock";$entries) else . end)
    | (if $weather then clock_project_part("weather";"araneadev.weather";$entries) else . end)
    # Local clones need a config reference even when their button is hosted.
    | if (clock_entries|any(.[];.entry|clock_entry_id == "araneadev.clock")) then
        .plugins = (((.plugins // [])|map(
            if type == "string" and (($worldclock and . == "araneadev.worldclock") or ($weather and . == "araneadev.weather"))
            then {id:.} else . end))
          + (if $worldclock then [{id:"araneadev.worldclock"}] else [] end)
          + (if $weather then [{id:"araneadev.weather"}] else [] end)
          | reduce .[] as $entry ([];if any(.[];clock_entry_id == ($entry|clock_entry_id)) then . else . + [$entry] end))
      else . end
  end;
# Preserve distinct source preferences unless their shared projected key actually changed.
def clock_restored_settings($part;$record;$current):
  ($record.entry|clock_settings) as $original
  | ($part.baseline // {}) as $baseline
  | (if $part.hadSetting and $record == $part.records[0] then $original + $baseline else $original end) as $base
  | reduce (($baseline|keys) + ($current|keys)|unique)[] as $key ($base;
      if (($baseline|has($key)) != ($current|has($key))) or $baseline[$key] != $current[$key] then
        if $current|has($key) then .[$key] = $current[$key] else del(.[$key]) end
      else . end);
# Restore string shape only when neither the original nor current settings need an object.
def clock_restored_entry($record;$settings):
  if ($record.entry|type) == "string" and ($settings|length) == 0 then $record.entry
  else {id:($record.entry|clock_entry_id)} + $settings end;
def release_clock:
  if (.bar.layout|type) != "object" then .
  else
    ([clock_entries[].entry|clock_entry_id|clock_canonical_id]) as $present
    | (clock_entries | map(select((.entry|type)=="object" and (.entry.araneaClockMigration|type)=="object"))) as $owners
    | ([$owners[] as $owner
         | $owner.entry.araneaClockMigration.parts|to_entries[]
         | . as $part
         | ($owner.entry[$part.key] | if type == "object" then . else {} end) as $settings
         | $part.value.records[] | . as $record
         | {record:$record,settings:clock_restored_settings($part.value;$record;$settings)}]
       | sort_by(.record.section,.record.index)) as $restore
    | reduce $restore[] as $item (.;
        $item.record as $record
        | ($record.entry|clock_entry_id|clock_canonical_id) as $id
        | if ($present|index($id)) != null then .
          else
            (clock_restored_entry($record;$item.settings)) as $entry
            | (.bar.layout[$record.section] // []) as $section
            | ([$record.index,($section|length)]|min) as $index
            | .bar.layout[$record.section] = ($section[:$index] + [$entry] + $section[$index:])
          end)
    | .bar.layout |= with_entries(.value |= (if type == "array" then map(
        if type == "object" and (.araneaClockMigration|type) == "object" then
          .araneaClockMigration as $meta
          | reduce ($meta.parts|to_entries[]) as $part (.;
              if $part.value.hadSetting or any($part.value.records[]; (.entry|clock_entry_id|clock_canonical_id) as $id | ($present|index($id)) != null)
              then . else del(.[$part.key]) end)
          | del(.araneaClockMigration)
          | if $meta.wasString and (keys == ["id"]) then .id else . end
        else . end) else . end))
  end;
