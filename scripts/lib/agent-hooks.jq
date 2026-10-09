# Provider-native to strict event contract. Input is in-memory only.
.[0].args as $a | .[1] as $state | .[2] as $clock | .[3] as $proof |
$a.provider as $provider |
($a.payload | if $provider == "codex" then del(.prompt_id,.task_id) + {prompt_id:.turn_id} else . end) as $p |
def text($n): if type == "string" then gsub("[\\x00-\\x1f\\x7f]";" ") | .[:$n] else "" end;
def id: type == "string" and length > 0 and length <= 180 and (test("[\\x00-\\x1f\\x7f]")|not);
if $provider == "codex" and (($p.hook_event_name|IN("SessionStart","UserPromptSubmit","PreToolUse","PermissionRequest","PostToolUse","Stop","SessionEnd","SubagentStart","SubagentStop","Interrupt","AraneaHeartbeat")|not) or (($p.hook_event_name|IN("SessionStart","SessionEnd","AraneaHeartbeat")|not) and ($p.turn_id|id|not))) then error("unsupported Codex hook or turn identity") else . end |
if ($p.session_id|id|not) then error("native session identity") else . end |
([$state.sessions[] | select(.provider == $provider and .providerSessionId == $p.session_id)][0] // null) as $s |
($p.hook_event_name // "") as $name |
if $s.provenance != null and $proof == null then error("unproven caller")
elif $name == "SessionStart" then
  (if $proof == null then "unconfirmed:"+$fingerprint else "process:"+([$proof.bootId,($proof.pid|tostring),$proof.startTime,$proof.commandHash]|join(":")) end) as $epoch |
  {action:"register",args:{provider:$provider,providerSessionId:$p.session_id,producerEpoch:$epoch,tasks:[],provenance:(if $s.producerEpoch == $epoch then $s.provenance else (if $proof == null then null else $proof + {observedAt:$clock.receivedAt} end) end)},nativeMetadata:{currentTaskId:null,turns:[],callbackOwners:[],observedHooks:(if $proof == null then [] else ["SessionStart"] end)}}
elif $s == null then error("unregistered session")
elif $s.provenance != null and ($proof == null or $proof.pid != $s.provenance.pid or $proof.startTime != $s.provenance.startTime or $proof.bootId != $s.provenance.bootId or $proof.commandHash != $s.provenance.commandHash) then error("unproven caller")
else
  ($s.nativeMetadata // {currentTaskId:null,turns:[]}) as $m |
  (if $name == "TaskCompleted" then if ($p.task_id|id) then "task:"+$p.task_id else error("missing task identity") end
   elif ($p.agent_id|id) then "agent:"+$p.agent_id
   elif $name|IN("SubagentStart","SubagentStop") then error("missing agent identity")
   elif $name == "UserPromptSubmit" then "prompt:"+(if ($p.prompt_id|id) then $p.prompt_id else "unconfirmed:"+$fingerprint end)
   elif ($p.prompt_id|id) then "prompt:"+$p.prompt_id
   else null end) as $native |
  (if ($p.tool_use_id|id) then $p.tool_use_id elif ($p.prompt_id|id) then $p.prompt_id elif ($p.agent_id|id) then $p.agent_id elif ($p.task_id|id) then $p.task_id else $fingerprint end) as $identity |
  ($m|has("callbackOwners")) as $modern |
  ([$m.callbackOwners[]? | select(.key == $callbackKey)][0] // null) as $callback |
  ([ $callback.taskId | select(. != null) ] +
    (if ($p.tool_use_id|id) then [$m.callbackOwners[]? | select(.toolUseId == $p.tool_use_id) | .taskId] else [] end) | unique) as $owners |
  ([$m.turns[]|select(.nativeId == $native)][0].taskId // null) as $mapped |
  if ($owners|length)>1 or ($mapped != null and ($owners|length)==1 and $mapped != $owners[0]) then error("conflicting native ownership")
  elif ($modern|not) and $native == null and $name != "AraneaHeartbeat" then error("uncorrelated legacy callback")
  elif $mapped == null and $native != null and ($name|IN("UserPromptSubmit","SubagentStart","TaskCompleted")|not) then error("unknown native identity") else . end |
  ($owners[0] // $mapped //
    (if $name|IN("UserPromptSubmit","SubagentStart","TaskCompleted") then $provider+":"+$clock.generatedId else $m.currentTaskId end) // "session") as $task |
  ([$state.tasks[]|select(.taskId == $task)][0] // null) as $old |
  $fingerprint as $fp |
  (if $modern then $callback.eventId // ("pending:"+$callbackKey) else $name+":"+$task+":"+$identity end) as $eventId |
  (if $modern and $callback == null then null else ([$s.receipts[]|select(.eventId == $eventId)][0] // null) end) as $receipt |
  if $old != null and ($name|IN("UserPromptSubmit","SubagentStart","TaskCompleted")) and $receipt == null then error("retained native identity outside replay window") else . end |
  ($receipt.sequence // ($s.highWaterSequence+1)) as $sequence |
  (if $name == "UserPromptSubmit" then
    {kind:"snapshot",payload:{cwd:$p.cwd,reportedState:"working",description:(($p.prompt // "")|split("\n")|map(gsub("^[[:space:]]+|[[:space:]]+$";""))|map(text(160))|map(select(length>0))|.[0]//""|.[:160])}}
   elif $name == "SubagentStart" then {kind:"snapshot",payload:{cwd:$p.cwd,reportedState:"working",description:("Subagent "+($p.agent_type|text(160)))}}
   elif $name == "TaskCompleted" then {kind:"snapshot",payload:{cwd:$p.cwd,reportedState:"finished",description:($p.task_subject|text(160)),result:"Native task reported completed"}}
   elif $provider == "codex" and $name == "Interrupt" then {kind:"diagnostic",payload:{summary:"Turn interrupted; unfinished work and permission resolution remain unconfirmed"}}
   elif $provider == "codex" and ($name|IN("PreToolUse","PostToolUse")) then {kind:"diagnostic",payload:{summary:($name+": "+($p.tool_name|text(160)))}}
   elif $name == "PreToolUse" and ($p.tool_name|IN("AskUserQuestion","ExitPlanMode")) then
    {kind:"needs-input",payload:{blockerId:(if ($p.tool_use_id|id) then "tool:"+$p.tool_use_id else "unconfirmed:"+$fp end),question:(if $p.tool_name == "AskUserQuestion" then ($p.tool_input.questions[0].question|text(4096)) else "Review the proposed plan" end)}}
   elif $name == "PermissionRequest" then {kind:"needs-input",payload:{blockerId:"permission-unconfirmed:"+$fp,question:("Permission requested for "+($p.tool_name|text(160))+"; resolution unconfirmed (no native correlation ID)")}}
   elif $name|IN("PostToolUse","PostToolUseFailure") then
    (if ($p.tool_use_id|id) then "tool:"+$p.tool_use_id else "unconfirmed-no-match" end) as $blocker |
    if ($p.tool_name|IN("AskUserQuestion","ExitPlanMode")) and ($p.tool_use_id|id) and ($name == "PostToolUse" or any($old.blockers[]?;.blockerId == $blocker)) then {kind:"blocker-resolved",payload:({blockerId:$blocker}+(if $name == "PostToolUseFailure" then {summary:($p.error|text(4096))} else {} end))}
    elif $name == "PostToolUseFailure" then {kind:"diagnostic",payload:{summary:($p.error|text(4096))}}
    else error("irrelevant tool") end
   elif $name|IN("Stop","SubagentStop") then {kind:"ready-for-review",payload:{result:($p.last_assistant_message|text(4096))}}
   elif $name == "StopFailure" then {kind:"failed",payload:{result:($p.error|text(4096))}}
   elif $name == "Notification" then {kind:"diagnostic",payload:{summary:($p.message|text(4096))}}
   elif $name == "SessionEnd" then {kind:"disconnected",payload:{}}
   elif $name == "AraneaHeartbeat" then {kind:"heartbeat",payload:{}}
   else error("unsupported hook") end) as $event |
  {action:"report",args:({schemaVersion:1,eventId:$eventId,provider:$provider,providerSessionId:$p.session_id,producerEpoch:$s.producerEpoch,sequence:$sequence,taskId:$task}+$event),
    nativeMetadata:($m | if $name|IN("UserPromptSubmit","SubagentStart","TaskCompleted") then
      .turns = ([.turns[]|select(.nativeId != $native)]+[{nativeId:$native,taskId:$task}]) |
      if $name == "UserPromptSubmit" and ($p.agent_id|id|not) then
        if $old == null and .currentTaskId != null then .inactiveTaskIds = (((.inactiveTaskIds//[])+[.currentTaskId])|unique) else . end |
        if $old == null then .currentTaskId=$task else . end
      else . end else . end |
      if $proof != null and $s.provenance != null and $name != "AraneaHeartbeat" then .observedHooks=(((.observedHooks//[])+[$name])|unique) else . end |
      if $modern and $name != "AraneaHeartbeat" then .callbackOwners = ([.callbackOwners[]|select(.key != $callbackKey)] + [{key:$callbackKey,eventId:$eventId,taskId:$task} + (if ($p.tool_use_id|id) then {toolUseId:$p.tool_use_id} else {} end)] | .[-512:]) else . end)}
end
