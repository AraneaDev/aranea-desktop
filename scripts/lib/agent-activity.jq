$ARGS.named.activity_provider as $activity_provider | $activity_context[0] as $context | $activity_projects[0] as $projects | $activity_request[0] as $request |
# Pure validation, ordering, reduction and read-only freshness projection.
def fields($r;$o): type == "object" and (keys as $keys | (($r - $keys)|length == 0) and (($keys - ($r+$o))|length == 0));
def uint: type == "number" and . == floor and . >= 0 and . <= 9007199254740991;
def text($n): type == "string" and length <= $n and (test("[\\x00-\\x1f\\x7f]")|not);
def id: text(256) and length > 0;
# Check individual bounds before joining for one character-class scan. Histories
# can hold thousands of IDs/digests; compiling a regex for each entry delays
# durable native delivery beyond its deadline without adding validation.
def ids: all(.[];type == "string" and length > 0 and length <= 256) and ((add // "")|test("[\\x00-\\x1f\\x7f]")|not);
def digests: all(.[];type == "string" and length == 64) and ((add // "")|test("[^a-f0-9]")|not);
def path: text(4096) and startswith("/");
def unique_values: length == (unique|length);
def provider: . == "claude" or . == "codex";
def lifecycle: IN("working","needs-input","ready-for-review","failed","finished");
def verification: fields(["status","summary","commands"];[]) and (.status|IN("unknown","reported-pass","reported-fail")) and (.summary|text(4096)) and (.commands|type == "array" and length <= 16 and all(.[];text(512)));
def blocker: fields(["blockerId","question"];[]) and (.blockerId|id) and (.question|text(4096));
def blockers: type == "array" and length <= 32 and all(.[];blocker) and (map(.blockerId)|unique_values);
def process_identity: fields(["pid","startTime"];[]) and (.pid|uint and . > 0) and (.startTime|id);
def provenance: . == null or (fields(["pid","startTime","bootId","ancestors","windowAddress","observedAt"];["executable","commandHash"]) and (.pid|uint and . > 0) and (.startTime|id) and (.bootId|id) and (.observedAt|uint) and (.windowAddress == null or (.windowAddress|id)) and (.ancestors|type == "array" and length <= 32 and all(.[];process_identity) and (map(.pid)|unique_values)) and (has("executable") == has("commandHash")) and ((has("executable")|not) or ((.executable|path) and (.commandHash|type == "string" and test("^[a-f0-9]{64}$")))));
# State-only references use string guards before exact membership in fully valid
# task/receipt ID indexes proves the complete ID constraint. Standalone metadata
# has no such indexes and retains the original full ID validation.
def reference_id($indexed): if $indexed then type == "string" else id end;
def callback_owner($indexed): type == "object" and has("key") and has("eventId") and has("taskId") and (length == 3 or (length == 4 and has("toolUseId"))) and (.key|type == "string" and length == 64) and (.eventId|reference_id($indexed)) and (.taskId|reference_id($indexed)) and ((has("toolUseId")|not) or (.toolUseId|type == "string" and length > 0 and length <= 180));
def metadata($indexed): fields(["currentTaskId","turns"];["inactiveTaskIds","observedHooks","callbackOwners"]) and (.currentTaskId == null or (.currentTaskId|reference_id($indexed))) and (.turns|type == "array" and length <= 512 and all(.[];fields(["nativeId","taskId"];[]) and (.nativeId|id) and (.taskId|reference_id($indexed))) and (map(.nativeId)|unique_values)) and ((has("inactiveTaskIds")|not) or (.inactiveTaskIds|type == "array" and length <= 512 and all(.[];reference_id($indexed)) and unique_values)) and (. as $m | all((.inactiveTaskIds//[])[];. != $m.currentTaskId)) and ((has("observedHooks")|not) or (.observedHooks|type == "array" and length <= 32 and all(.[];type == "string" and length <= 64 and test("^[A-Za-z][A-Za-z0-9]*$")) and unique_values)) and ((has("callbackOwners")|not) or (.callbackOwners|type == "array" and length <= 512 and all(.[];callback_owner(true)) and (if $indexed then true else (map(.eventId)|ids) and (map(.taskId)|ids) end) and ([.[]|select(has("toolUseId"))|.toolUseId]|ids) and (map(.key)|digests and unique_values) and (map(.eventId)|unique_values)));
def metadata: metadata(false);
def task_snapshot: fields(["cwd","reportedState"];["taskId","projectId","checkoutId","description","result","question","blockers","verification"])
  and (.cwd|path) and (.reportedState|lifecycle)
  and ((has("taskId")|not) or (.taskId|id))
  and ((has("projectId")|not) or (.projectId|id)) and ((has("checkoutId")|not) or (.checkoutId|id))
  and (has("projectId") == has("checkoutId"))
  and all([.description?,.result?,.question?][]; . == null or text(4096))
  and ((has("blockers")|not) or (.blockers|blockers)) and ((has("verification")|not) or (.verification|verification));
def event: fields(["schemaVersion","eventId","provider","providerSessionId","producerEpoch","sequence","taskId","kind","payload"];[])
  and .schemaVersion == 1 and (.eventId|id) and (.provider|provider) and (.providerSessionId|id) and (.producerEpoch|id) and (.sequence|uint and . > 0) and (.taskId|id)
  and (.kind as $kind | .payload |
    if $kind == "snapshot" then task_snapshot and (has("taskId")|not)
    elif $kind == "working" then fields([];["description"]) and ((has("description")|not) or (.description|text(4096)))
    elif $kind == "needs-input" then blocker
    elif $kind == "blocker-resolved" then fields(["blockerId"];["summary"]) and (.blockerId|id) and ((has("summary")|not) or (.summary|text(4096)))
    elif $kind|IN("ready-for-review","failed","finished") then fields([];["result"]) and ((has("result")|not) or (.result|text(4096)))
    elif $kind == "diagnostic" then fields(["summary"];[]) and (.summary|text(4096))
    elif $kind == "verification" then verification
    elif $kind|IN("heartbeat","disconnected") then fields([];[])
    else false end);
def registration: fields(["provider","providerSessionId","producerEpoch","tasks"];["provenance"])
  and (.provider|provider) and (.providerSessionId|id) and (.producerEpoch|id)
  and ((has("provenance")|not) or (.provenance|provenance))
  and (.tasks|type == "array" and length <= 700 and all(.[];task_snapshot and has("taskId")) and (map(.taskId)|unique_values));
def request_valid: fields(["action","args"];["expectedRevision"]) and ((has("expectedRevision")|not) or (.expectedRevision|uint))
  and (.action as $action | .args |
    if $action == "register" then registration
    elif $action == "report" then event
    elif $action == "dismiss" then fields(["taskId"];[]) and (.taskId|id)
    elif $action == "dismiss-many" then fields(["taskIds"];[]) and (.taskIds|type == "array" and length > 0 and length <= 700 and all(.[];id) and unique_values)
    elif $action == "prune" then fields([];[])
    elif $action == "native" then fields(["provider","payload","caller"];[]) and (.provider|provider) and (.payload|type == "object") and (.caller|provenance)
    else false end);
def connection: fields(["receivedAt","monotonic","bootId","connected"];[]) and (.receivedAt|uint) and (.monotonic|uint) and (.bootId|id) and (.connected|type == "boolean");
def session: fields(["provider","providerSessionId","producerEpoch","highWaterSequence","receipts","registrationHash","retiredEpochs","connection","provenance","nativeMetadata"];[])
  and (.provider|provider) and (.providerSessionId|id) and (.producerEpoch|id) and (.highWaterSequence|uint)
  and (.registrationHash|test("^[a-f0-9]{64}$"))
  and (.retiredEpochs|type == "array" and length <= 512 and all(.[];id) and unique_values)
  and (.receipts|type == "array" and length <= 512 and all(.[];type == "object" and length == 3 and has("eventId") and has("hash") and has("sequence") and (.sequence|uint and . > 0)) and (map(.eventId)|ids and unique_values) and (map(.hash)|digests))
  and (.highWaterSequence as $max | all(.receipts[];.sequence <= $max))
  and (.connection|connection) and (.provenance|provenance) and (.nativeMetadata|metadata(true));
def association: fields(["status","projectId","checkoutId","cwd"];[]) and (.status|IN("registered","unassigned")) and (.cwd|path)
  and (if .status == "registered" then (.projectId|id) and (.checkoutId|id) else .projectId == null and .checkoutId == null end);
def task: fields(["taskId","provider","providerSessionId","producerEpoch","reportedState","description","result","question","blockers","diagnostics","verification","association","lastReceivedAt","source"];["reportVersion"])
  and (.taskId|id) and (.provider|provider) and (.providerSessionId|id) and (.producerEpoch|id) and (.reportedState|lifecycle)
  and ((has("reportVersion")|not) or (.reportVersion|text(64) and startswith("report:") and (.[7:]|fromjson|uint)))
  and all([.description,.result,.question][];text(4096)) and (.blockers|blockers)
  and (.diagnostics|type == "array" and length <= 20 and all(.[];fields(["summary","receivedAt"];[]) and (.summary|text(4096)) and (.receivedAt|uint)))
  and (.verification|verification) and (.association|association) and (.lastReceivedAt|uint) and (.source|IN("report","native"));
def same_session($a): .provider == $a.provider and .providerSessionId == $a.providerSessionId;
# Serialize tuple identities; delimiter-containing IDs must never share a key.
def session_key: [.provider,.providerSessionId]|tojson;
def session_index: INDEX(.[];session_key) | map_values({session:.,inactive:INDEX((.nativeMetadata.inactiveTaskIds//[])[];.)});
def state_valid($validated_sessions): fields(["schemaVersion","revision","sessions","tasks"];[]) and .schemaVersion == 1 and (.revision|uint)
  and (.sessions|type == "array" and length <= 1200 and all(.[]; . as $s | ($validated_sessions[session_key] != null and $validated_sessions[session_key] == $s) or session) and (map([.provider,.providerSessionId])|unique_values))
  and (.tasks|type == "array" and length <= 700 and all(.[];task) and (map(.taskId)|unique_values))
  # Build membership indexes only after every indexed shape and identity validates.
  and (INDEX(.sessions[];session_key) as $sessions
    | (reduce .tasks[] as $task ({}; .[$task|session_key][$task.taskId] = true)) as $tasks
    | all(.tasks[]; . as $t | $sessions[session_key].producerEpoch == $t.producerEpoch)
      and all(.sessions[]; $tasks[session_key] as $sessionTasks | INDEX(.receipts[];.eventId) as $receipts
        | (.nativeMetadata.currentTaskId == null or $sessionTasks[.nativeMetadata.currentTaskId] != null)
          and all(.nativeMetadata.turns[]; $sessionTasks[.taskId] != null)
          and all((.nativeMetadata.inactiveTaskIds//[])[]; $sessionTasks[.] != null)
          and all((.nativeMetadata.callbackOwners//[])[]; $sessionTasks[.taskId] != null and $receipts[.eventId] != null)));
def state_valid: state_valid({});
def fresh($s): $s.connection.connected and $s.connection.bootId == $context.bootId and $context.monotonic >= $s.connection.monotonic and ($context.monotonic - $s.connection.monotonic) < 60 and $context.receivedAt >= $s.connection.receivedAt and ($context.receivedAt - $s.connection.receivedAt) < 60;
def live($sessions): . as $t | $sessions[session_key] as $entry
  | .reportedState != "finished" and $entry != null and fresh($entry.session) and $entry.inactive[$t.taskId] == null;
# Working with no report for 6 hours ended without one, even while heartbeats
# keep its session connected (ActivityLogic.silentWork uses the same age).
def stale_work: .reportedState == "working" and ($context.receivedAt - .lastReceivedAt) >= 21600;
# Live work stays protected; completed review/failure without blockers may go.
def dismissible($sessions): (live($sessions) and (((.reportedState|IN("ready-for-review","failed")) and (.blockers|length) == 0)|not) and (stale_work|not))|not;
def clock($connected): {receivedAt:$context.receivedAt,monotonic:$context.monotonic,bootId:$context.bootId,connected:$connected};
def associate($a): [$projects.projects[] as $p | $p.checkouts[] | select(.path == $a.cwd) | {status:"registered",projectId:$p.id,checkoutId:.id,cwd:$a.cwd}] as $found
  | if ($a|has("projectId")) and (all($found[]; .projectId != $a.projectId or .checkoutId != $a.checkoutId) or ($found|length == 0)) then error("ASSOCIATION_MISMATCH")
    else $found[0] // {status:"unassigned",projectId:null,checkoutId:null,cwd:$a.cwd} end;
def make_task($a;$t;$source): {taskId:$t.taskId,provider:$a.provider,providerSessionId:$a.providerSessionId,producerEpoch:$a.producerEpoch,
  reportedState:$t.reportedState,description:($t.description//""),result:($t.result//""),question:($t.question//""),blockers:($t.blockers//[]),diagnostics:[],
  verification:($t.verification//{status:"unknown",summary:"",commands:[]}),association:associate($t),lastReceivedAt:$context.receivedAt,source:$source,reportVersion:("report:"+($a.sequence//0|tostring))};
def retain:
  (.sessions|session_index) as $sessions
  | [.tasks[]|select(live($sessions))] as $live
  | .tasks = ($live + ([.tasks[]|select(live($sessions)|not)|select(.lastReceivedAt >= ($context.receivedAt - 1209600))]|sort_by(.lastReceivedAt,.taskId)|.[-500:]))
  # Retention changes task membership. Rebuild indexes before cleaning references.
  | INDEX(.tasks[];.taskId) as $tasks | INDEX(.tasks[];session_key) as $taskSessions
  | .sessions |= map(select(. as $s | $taskSessions[session_key] != null or fresh($s))
      | .nativeMetadata.turns |= map(select($tasks[.taskId] != null))
      | if (.nativeMetadata|has("inactiveTaskIds")) then .nativeMetadata.inactiveTaskIds |= map(select($tasks[.] != null)) else . end
      | . as $s | INDEX(.receipts[];.eventId) as $receipts
      | if (.nativeMetadata|has("callbackOwners")) then .nativeMetadata.callbackOwners |= map(select(. as $owner | ($tasks[$owner.taskId]|same_session($s)) and $receipts[$owner.eventId] != null)) else . end
      | if $tasks[.nativeMetadata.currentTaskId // ""] != null then . else .nativeMetadata.currentTaskId = null end)
  | if ($live|length) > 200 or (.sessions|length) > 1200 then error("CAPACITY_EXCEEDED") else . end;
def register($a;$source):
  ([.sessions[]|select(same_session($a))][0] // null) as $old
  | if $old.producerEpoch == $a.producerEpoch then
      if $old.registrationHash == $hash then . else error("EPOCH_CONFLICT") end
    elif $old != null and any($old.retiredEpochs[];. == $a.producerEpoch) then error("EPOCH_MISMATCH")
    elif $old != null and ($old.retiredEpochs|length) >= 512 then error("CAPACITY_EXCEEDED")
    else .tasks |= map(select(same_session($a)|not))
      | if any(.tasks[];.taskId as $id | any($a.tasks[];.taskId == $id)) then error("TASK_ID_CONFLICT") else . end
      | .tasks += [$a.tasks[]|make_task($a;.;$source)]
      | .sessions = ([.sessions[]|select(same_session($a)|not)] + [{provider:$a.provider,providerSessionId:$a.providerSessionId,producerEpoch:$a.producerEpoch,
          highWaterSequence:0,receipts:[],registrationHash:$hash,retiredEpochs:(($old.retiredEpochs//[]) + (if $old == null then [] else [$old.producerEpoch] end)),
          connection:clock(true),provenance:($a.provenance//null),nativeMetadata:{currentTaskId:null,turns:[]}}]) | .revision += 1 end;
# The accepted sequence identifies reports within the exact producer epoch,
# including reports in one wall-clock second. Replays bypass this update.
def update_task($e): .lastReceivedAt = $context.receivedAt | .reportVersion = ("report:"+($e.sequence|tostring))
  | if $e.kind == "snapshot" then make_task($e;($e.payload+{taskId:$e.taskId});.source)
    elif $e.kind == "needs-input" then .blockers = ([.blockers[]|select(.blockerId != $e.payload.blockerId)] + [$e.payload]) | if (.blockers|length) > 32 then error("CAPACITY_EXCEEDED") else . end | .reportedState = "needs-input" | .question = $e.payload.question
    elif $e.kind == "blocker-resolved" then any(.blockers[];.blockerId == $e.payload.blockerId) as $resolved
      | .blockers |= map(select(.blockerId != $e.payload.blockerId))
      | if $resolved and .reportedState == "needs-input" and (.blockers|length == 0) then .reportedState = "working" | .question = "" elif (.blockers|length > 0) then .question = .blockers[-1].question else . end
      | if $resolved and ($e.payload|has("summary")) then .diagnostics = ((.diagnostics + [{summary:$e.payload.summary,receivedAt:$context.receivedAt}])|.[-20:]) else . end
    elif $e.kind == "working" then (if (.blockers|length == 0) then .reportedState = "working" else . end) | .description = ($e.payload.description//.description)
    elif $e.kind|IN("ready-for-review","failed","finished") then .reportedState = $e.kind | .result = ($e.payload.result//.result)
    elif $e.kind == "diagnostic" then .diagnostics = ((.diagnostics + [{summary:$e.payload.summary,receivedAt:$context.receivedAt}])|.[-20:])
    elif $e.kind == "verification" then .verification = $e.payload
    else . end;
def report($e;$source):
  ([.sessions[]|select(same_session($e))][0]//null) as $s
  | if $s == null then error("SESSION_NOT_FOUND")
    elif $s.producerEpoch != $e.producerEpoch then error("EPOCH_MISMATCH")
    else ([$s.receipts[]|select(.eventId == $e.eventId)][0]//null) as $receipt
      | if $receipt != null then if $receipt.hash == $hash then . else error("EVENT_ID_CONFLICT") end
        elif $e.sequence <= $s.highWaterSequence then error("STALE_SEQUENCE")
        else
          if any(.tasks[];.taskId == $e.taskId and (same_session($e)|not)) then error("TASK_ID_CONFLICT")
          elif (any(.tasks[];.taskId == $e.taskId)|not) then
            if $e.kind == "snapshot" then .tasks += [make_task($e;($e.payload+{taskId:$e.taskId});$source)]
            elif $e.kind|IN("heartbeat","disconnected") then .
            else error("TASK_NOT_FOUND") end
          else .tasks |= map(if .taskId == $e.taskId then update_task($e) | .source = $source else . end) end
          | .sessions |= map(if same_session($e) then .highWaterSequence = $e.sequence
              | .connection = clock($e.kind != "disconnected")
              | .receipts = ((.receipts + [{eventId:$e.eventId,sequence:$e.sequence,hash:$hash}])|.[-512:]) else . end)
          | .revision += 1 end end;
def mutation($r;$source;$prepared_metadata):
  if $r.action == "register" then register($r.args;$source)
  elif $r.action == "report" then report($r.args;$source)
  elif $r.action == "dismiss" then
    ([.tasks[]|select(.taskId == $r.args.taskId)][0]//null) as $task
    | if $task == null then error("TASK_NOT_FOUND")
      elif ((.sessions|session_index) as $sessions | $task|dismissible($sessions)|not) then error("TASK_LIVE")
      else .tasks |= map(select(.taskId != $r.args.taskId)) | .revision += 1 end
  elif $r.action == "dismiss-many" then
    # One write for the whole set; missing IDs are skipped, live tasks stay.
    (.sessions|session_index) as $sessions | INDEX(.tasks[];.taskId) as $tasks
    | (reduce $r.args.taskIds[] as $id ({}; if $tasks[$id] != null and ($tasks[$id]|dismissible($sessions)) then .[$id] = true else . end)) as $drop
    | if ($drop|length) == 0 then . else .tasks |= map(select($drop[.taskId] == null)) | .revision += 1 end
  elif $r.action == "prune" then .revision += 1
  elif $r.action == "native" then $r.args.normalized as $n
    | if ($n|fields(["action","args"];["nativeMetadata"])) and ($n.action|IN("register","report")) and ($n|del(.nativeMetadata)|request_valid) and (($n|has("nativeMetadata")|not) or $prepared_metadata or ($n.nativeMetadata|metadata)) then
      .revision as $beforeRevision | mutation(($n|del(.nativeMetadata));"native";false)
      | if .revision != $beforeRevision and ($n|has("nativeMetadata")) then .sessions |= map(if same_session($n.args) then .nativeMetadata = $n.nativeMetadata else . end) else . end
    else error("INVALID_REQUEST") end
  else error("INVALID_REQUEST") end;
# Store transactions reuse the already fully validated, unchanged native metadata.
# All event/registration fields are checked again after canonical path preparation.
# Pure mutate also rechecks metadata; final state constraints remain unconditional.
def mutation($r;$source): mutation($r;$source;false);
# Per-ID outcome of a dismiss-many: removed, not present before, or still kept.
def dismiss_result($before;$after;$r):
  if $r.action == "dismiss-many" then INDEX($before.tasks[];.taskId) as $old | INDEX($after.tasks[];.taskId) as $new
    | {result:{removed:[$r.args.taskIds[]|select($old[.] != null and $new[.] == null)],missing:[$r.args.taskIds[]|select($old[.] == null)],refused:[$r.args.taskIds[]|select($old[.] != null and $new[.] != null)]}}
  else {} end;
def project_state:
  .revision as $revision | (.sessions|session_index) as $sessions | .tasks |= map(. as $task | $sessions[session_key] as $entry | $entry.session as $s
    # Old schema-1 rows have no persisted report version. The state revision bounds
    # their identity until their first new report assigns a persisted sequence.
    | .reportVersion //= ("legacy:"+($revision|tostring))
    | .freshness = (if $entry.inactive[$task.taskId] != null then "connection-lost" elif fresh($s) then if $s.provenance == null or ($s.provenance|has("commandHash")|not) then "unconfirmed" else "connected" end else "connection-lost" end)
    | if .association.status == "registered" and (any($projects.projects[];.id == $task.association.projectId and any(.checkouts[];.id == $task.association.checkoutId and .path == $task.association.cwd))|not) then .association.status = "unavailable" else . end)
  | .capabilities = {heartbeatSeconds:15,connectionLostSeconds:60,maxLiveTasks:200,maxInactiveTasks:500,inactiveRetentionDays:14,duplicateReceiptWindow:512,maxRetiredEpochs:512,epochHistoryLifetime:"retained-session"};
if $operation == "load" then
  if utf8bytelength > 33554432 then error("ACTIVITY_INVALID")
  else fromjson | if state_valid then . else error("ACTIVITY_INVALID") end end
elif $operation == "validate" then try state_valid catch false
elif $operation == "read-request" then
  if utf8bytelength > 1048576 then error("INPUT_TOO_LARGE")
  else (try fromjson catch error("INVALID_REQUEST_JSON"))
    | if (try request_valid catch false) then . else error("INVALID_REQUEST_SCHEMA") end end
elif $operation == "request" then try request_valid catch false
elif $operation == "normalized" or $operation == "normalized-fingerprint" then
  (try (fields(["action","args"];["nativeMetadata"]) and (.action|IN("register","report")) and (del(.nativeMetadata)|request_valid) and ((has("nativeMetadata")|not) or (.nativeMetadata|metadata))) catch false) as $valid
  | if $operation == "normalized" then $valid
    elif $valid and .args.provider == $activity_provider then del(.nativeMetadata)
    else error("INVALID_REQUEST") end
elif $operation == "mutate" then . as $before | mutation($request;"report") | if . == $before then . else retain end
elif $operation == "project" then project_state
elif $operation == "response" then project_state | {ok:true,state:.,error:null}
elif $operation == "transaction" or $operation == "store-transaction" then
  . as $before | (mutation($request;"report";true) | if . == $before then . else retain end) as $after
  # The store has fully validated $before under the same held lock. Reuse only
  # exact unchanged session values; changed sessions and every global reference
  # still validate. Standalone transactions retain full independent validation.
  | (if $operation == "store-transaction" then INDEX($before.sessions[];session_key) else {} end) as $validated_sessions
  | if $after|state_valid($validated_sessions) then $after,($after|project_state|{ok:true,state:.,error:null} + dismiss_result($before;$after;$request)) else error("ACTIVITY_INVALID") end
else error("INVALID_OPERATION") end
