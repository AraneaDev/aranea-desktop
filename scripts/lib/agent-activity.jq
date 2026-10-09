$activity_context[0] as $context | $activity_projects[0] as $projects | $activity_request[0] as $request |
# Pure validation, ordering, reduction and read-only freshness projection.
def fields($r;$o): type == "object" and (($r - keys)|length == 0) and ((keys - ($r+$o))|length == 0);
def uint: type == "number" and . == floor and . >= 0 and . <= 9007199254740991;
def text($n): type == "string" and length <= $n and (test("[\\x00-\\x1f\\x7f]")|not);
def id: text(256) and length > 0;
def path: text(4096) and startswith("/");
def unique_values: length == (unique|length);
def provider: . == "claude" or . == "codex";
def lifecycle: IN("working","needs-input","ready-for-review","failed","finished");
def verification: fields(["status","summary","commands"];[]) and (.status|IN("unknown","reported-pass","reported-fail")) and (.summary|text(4096)) and (.commands|type == "array" and length <= 16 and all(.[];text(512)));
def blocker: fields(["blockerId","question"];[]) and (.blockerId|id) and (.question|text(4096));
def blockers: type == "array" and length <= 32 and all(.[];blocker) and (map(.blockerId)|unique_values);
def process_identity: fields(["pid","startTime"];[]) and (.pid|uint and . > 0) and (.startTime|id);
def provenance: . == null or (fields(["pid","startTime","bootId","ancestors","windowAddress","observedAt"];[]) and (.pid|uint and . > 0) and (.startTime|id) and (.bootId|id) and (.observedAt|uint) and (.windowAddress == null or (.windowAddress|id)) and (.ancestors|type == "array" and length <= 32 and all(.[];process_identity) and (map(.pid)|unique_values)));
def metadata: fields(["currentTaskId","turns"];[]) and (.currentTaskId == null or (.currentTaskId|id)) and (.turns|type == "array" and length <= 512 and all(.[];fields(["nativeId","taskId"];[]) and (.nativeId|id) and (.taskId|id)) and (map(.nativeId)|unique_values));
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
    elif $kind == "blocker-resolved" then fields(["blockerId"];[]) and (.blockerId|id)
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
    elif $action == "prune" then fields([];[])
    elif $action == "native" then fields(["provider","payload","caller"];[]) and (.provider|provider) and (.payload|type == "object") and (.caller|provenance)
    else false end);
def connection: fields(["receivedAt","monotonic","bootId","connected"];[]) and (.receivedAt|uint) and (.monotonic|uint) and (.bootId|id) and (.connected|type == "boolean");
def session: fields(["provider","providerSessionId","producerEpoch","highWaterSequence","receipts","registrationHash","retiredEpochs","connection","provenance","nativeMetadata"];[])
  and (.provider|provider) and (.providerSessionId|id) and (.producerEpoch|id) and (.highWaterSequence|uint)
  and (.registrationHash|test("^[a-f0-9]{64}$"))
  and (.retiredEpochs|type == "array" and length <= 512 and all(.[];id) and unique_values)
  and (.receipts|type == "array" and length <= 512 and all(.[];fields(["eventId","hash","sequence"];[]) and (.eventId|id) and (.hash|test("^[a-f0-9]{64}$")) and (.sequence|uint and . > 0)) and (map(.eventId)|unique_values))
  and (.highWaterSequence as $max | all(.receipts[];.sequence <= $max))
  and (.connection|connection) and (.provenance|provenance) and (.nativeMetadata|metadata);
def association: fields(["status","projectId","checkoutId","cwd"];[]) and (.status|IN("registered","unassigned")) and (.cwd|path)
  and (if .status == "registered" then (.projectId|id) and (.checkoutId|id) else .projectId == null and .checkoutId == null end);
def task: fields(["taskId","provider","providerSessionId","producerEpoch","reportedState","description","result","question","blockers","diagnostics","verification","association","lastReceivedAt","source"];[])
  and (.taskId|id) and (.provider|provider) and (.providerSessionId|id) and (.producerEpoch|id) and (.reportedState|lifecycle)
  and all([.description,.result,.question][];text(4096)) and (.blockers|blockers)
  and (.diagnostics|type == "array" and length <= 20 and all(.[];fields(["summary","receivedAt"];[]) and (.summary|text(4096)) and (.receivedAt|uint)))
  and (.verification|verification) and (.association|association) and (.lastReceivedAt|uint) and (.source|IN("report","native"));
def same_session($a): .provider == $a.provider and .providerSessionId == $a.providerSessionId;
def state_valid: fields(["schemaVersion","revision","sessions","tasks"];[]) and .schemaVersion == 1 and (.revision|uint)
  and (.sessions|type == "array" and length <= 1200 and all(.[];session) and (map([.provider,.providerSessionId])|unique_values))
  and (.tasks|type == "array" and length <= 700 and all(.[];task) and (map(.taskId)|unique_values))
  and (.sessions as $s | all(.tasks[]; . as $t | any($s[];same_session($t) and .producerEpoch == $t.producerEpoch)))
  and (.tasks as $ts | all(.sessions[]; . as $s | (.nativeMetadata.currentTaskId == null or any($ts[];same_session($s) and .taskId == $s.nativeMetadata.currentTaskId)) and all(.nativeMetadata.turns[]; .taskId as $tid | any($ts[];same_session($s) and .taskId == $tid))));
def fresh($s): $s.connection.connected and $s.connection.bootId == $context.bootId and $context.monotonic >= $s.connection.monotonic and ($context.monotonic - $s.connection.monotonic) < 60 and $context.receivedAt >= $s.connection.receivedAt and ($context.receivedAt - $s.connection.receivedAt) < 60;
def live($sessions): . as $t | .reportedState != "finished" and any($sessions[];same_session($t) and fresh(.));
def clock($connected): {receivedAt:$context.receivedAt,monotonic:$context.monotonic,bootId:$context.bootId,connected:$connected};
def associate($a): [$projects.projects[] as $p | $p.checkouts[] | select(.path == $a.cwd) | {status:"registered",projectId:$p.id,checkoutId:.id,cwd:$a.cwd}] as $found
  | if ($a|has("projectId")) and (all($found[]; .projectId != $a.projectId or .checkoutId != $a.checkoutId) or ($found|length == 0)) then error("ASSOCIATION_MISMATCH")
    else $found[0] // {status:"unassigned",projectId:null,checkoutId:null,cwd:$a.cwd} end;
def make_task($a;$t;$source): {taskId:$t.taskId,provider:$a.provider,providerSessionId:$a.providerSessionId,producerEpoch:$a.producerEpoch,
  reportedState:$t.reportedState,description:($t.description//""),result:($t.result//""),question:($t.question//""),blockers:($t.blockers//[]),diagnostics:[],
  verification:($t.verification//{status:"unknown",summary:"",commands:[]}),association:associate($t),lastReceivedAt:$context.receivedAt,source:$source};
def retain:
  .sessions as $sessions | .tasks = ([.tasks[]|select(live($sessions))] + ([.tasks[]|select(live($sessions)|not)|select(.lastReceivedAt >= ($context.receivedAt - 1209600))]|sort_by(.lastReceivedAt,.taskId)|.[-500:]))
  | .tasks as $tasks
  | .sessions |= map(select(. as $s | any($tasks[];same_session($s)) or fresh($s))
      | .nativeMetadata.turns |= map(select(.taskId as $tid | any($tasks[];.taskId == $tid)))
      | if (.nativeMetadata.currentTaskId as $tid | any($tasks[];.taskId == $tid)) then . else .nativeMetadata.currentTaskId = null end)
  | if ([.tasks[]|select(live($sessions))]|length) > 200 or (.sessions|length) > 1200 then error("CAPACITY_EXCEEDED") else . end;
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
def update_task($e): .lastReceivedAt = $context.receivedAt
  | if $e.kind == "snapshot" then make_task($e;($e.payload+{taskId:$e.taskId});.source)
    elif $e.kind == "needs-input" then .blockers = ([.blockers[]|select(.blockerId != $e.payload.blockerId)] + [$e.payload]) | if (.blockers|length) > 32 then error("CAPACITY_EXCEEDED") else . end | .reportedState = "needs-input" | .question = $e.payload.question
    elif $e.kind == "blocker-resolved" then any(.blockers[];.blockerId == $e.payload.blockerId) as $resolved
      | .blockers |= map(select(.blockerId != $e.payload.blockerId))
      | if $resolved and .reportedState == "needs-input" and (.blockers|length == 0) then .reportedState = "working" | .question = "" elif (.blockers|length > 0) then .question = .blockers[-1].question else . end
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
def mutation($r;$source):
  if $r.action == "register" then register($r.args;$source)
  elif $r.action == "report" then report($r.args;$source)
  elif $r.action == "dismiss" then
    ([.tasks[]|select(.taskId == $r.args.taskId)][0]//null) as $task
    | if $task == null then error("TASK_NOT_FOUND")
      elif (.sessions as $sessions | $task|live($sessions)) then error("TASK_LIVE")
      else .tasks |= map(select(.taskId != $r.args.taskId)) | .revision += 1 end
  elif $r.action == "prune" then .revision += 1
  elif $r.action == "native" then $r.args.normalized as $n
    | if ($n|fields(["action","args"];["nativeMetadata"])) and ($n.action|IN("register","report")) and ($n|del(.nativeMetadata)|request_valid) and (($n|has("nativeMetadata")|not) or ($n.nativeMetadata|metadata)) then
      .revision as $beforeRevision | mutation(($n|del(.nativeMetadata));"native")
      | if .revision != $beforeRevision and ($n|has("nativeMetadata")) then .sessions |= map(if same_session($n.args) then .nativeMetadata = $n.nativeMetadata else . end) else . end
    else error("INVALID_REQUEST") end
  else error("INVALID_REQUEST") end;
def project_state:
  . as $state | .tasks |= map(. as $task | [$state.sessions[]|select(same_session($task))][0] as $s
    | .freshness = (if fresh($s) then if $s.provenance == null then "unconfirmed" else "connected" end else "connection-lost" end)
    | if .association.status == "registered" and (any($projects.projects[];.id == $task.association.projectId and any(.checkouts[];.id == $task.association.checkoutId and .path == $task.association.cwd))|not) then .association.status = "unavailable" else . end)
  | .capabilities = {heartbeatSeconds:15,connectionLostSeconds:60,maxLiveTasks:200,maxInactiveTasks:500,inactiveRetentionDays:14,duplicateReceiptWindow:512,maxRetiredEpochs:512,epochHistoryLifetime:"retained-session"};
if $operation == "validate" then try state_valid catch false
elif $operation == "request" then try request_valid catch false
elif $operation == "normalized" then try (fields(["action","args"];["nativeMetadata"]) and (.action|IN("register","report")) and (del(.nativeMetadata)|request_valid) and ((has("nativeMetadata")|not) or (.nativeMetadata|metadata))) catch false
elif $operation == "mutate" then . as $before | mutation($request;"report") | if . == $before then . else retain end
elif $operation == "project" then project_state
else error("INVALID_OPERATION") end
