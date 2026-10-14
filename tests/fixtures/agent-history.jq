# Dense valid retained history; each session owns exact receipt and task identities.
def task_id($s;$t): "task:[\""+($s|tostring)+"\",\""+($t|tostring)+"\"]:with:separators";
def task_count($s): if $s == 6 then 5 else 6 end;
def event_id($r): "receipt:"+($r|tostring);
{schemaVersion:1,revision:100,
 sessions:[range(7) as $s |
   {provider:(if $s == 1 then "codex" else "claude" end),providerSessionId:("dense:session:"+($s|tostring)),producerEpoch:"dense:epoch",highWaterSequence:512,
    receipts:[range(512) as $r | {eventId:event_id($r),sequence:($r+1),hash:("0"*64)}],registrationHash:("0"*64),retiredEpochs:[],
    connection:{receivedAt:$now,monotonic:$monotonic,bootId:$boot,connected:true},provenance:null,
    nativeMetadata:{currentTaskId:task_id($s;(task_count($s)-1)),turns:[range(task_count($s)) as $t|{nativeId:("prompt:turn:"+($t|tostring)),taskId:task_id($s;$t)}],
      inactiveTaskIds:[range(task_count($s)-1) as $t|task_id($s;$t)],observedHooks:[],
      callbackOwners:[range(512) as $r|{key:(("0"*64)+($r|tostring)|.[-64:]),eventId:event_id($r),taskId:task_id($s;($r%task_count($s))),toolUseId:("dense-tool:"+($r|tostring))}]}}],
 tasks:[range(7) as $s | range(task_count($s)) as $t |
   {taskId:task_id($s;$t),provider:(if $s == 1 then "codex" else "claude" end),providerSessionId:("dense:session:"+($s|tostring)),producerEpoch:"dense:epoch",
    reportedState:"working",description:("Dense task "+($t|tostring)),result:"",question:"",blockers:[],diagnostics:[],verification:{status:"unknown",summary:"",commands:[]},
    association:{status:"unassigned",projectId:null,checkoutId:null,cwd:$cwd},lastReceivedAt:$now,source:"native"}]}
