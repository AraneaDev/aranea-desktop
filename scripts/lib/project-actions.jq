# Strict durable schema and pure reducer. Filesystem and hash authority are shell-owned.
def fields($required;$optional): type=="object" and (keys-($required+$optional)|length)==0 and ($required-keys|length)==0;
def integer: type=="number" and .==floor and .>=0;
def plain: type=="string" and (test("[\\x00-\\x1f\\x7f]")|not);
def uuid: type=="string" and test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$");
def id($p): type=="string" and startswith($p+"-") and (ltrimstr($p+"-")|uuid);
def hash: type=="string" and test("^[0-9a-f]{64}$");
def invocation: .==null or (type=="string" and test("^[0-9a-f]{32}$"));
def distinct: length==(unique|length);
def absolute: plain and startswith("/") and length>1;
def relative: plain and length>0 and length<=512 and (startswith("/")|not) and (split("/")|all(.[];.!=".." and .!=""));
def url: .==null or (plain and length<=2048 and test("^https?://(127\\.0\\.0\\.1|\\[::1\\]):[0-9]{1,5}([/?][^#\\s]*)?$") and (capture("^https?://(?:127\\.0\\.0\\.1|\\[::1\\]):(?<port>[0-9]+)").port|tonumber|.>=1 and .<=65535));
def draft:
  fields(["name","kind","argv","cwdRelative","previewUrl"];["id","timeoutSeconds"])
  and ((has("id")|not) or (.id|id("a")))
  and (.name|plain and length>=1 and length<=120)
  and (.kind=="command" or .kind=="service")
  and (.argv|type=="array" and length>=1 and length<=64 and all(.[];plain and length<=1024) and (map(utf8bytelength)|add)<=16384
    and (.[0]|length>0 and (startswith("/") or startswith("./") or (contains("/")|not))))
  and (.cwdRelative|relative) and (.previewUrl|url)
  and (if .kind=="command" then .previewUrl==null and ((.timeoutSeconds//300)|integer and .>=1 and .<=3600) and (.timeoutSeconds!=null or (has("timeoutSeconds")|not)) else .timeoutSeconds==null end);
def definition:
  fields(["id","projectId","name","kind","argv","cwdRelative","timeoutSeconds","previewUrl","revision","createdAt","updatedAt"];[])
  and (del(.projectId,.revision,.createdAt,.updatedAt)|draft) and (.projectId|id("p"))
  and (.revision|integer and .>0) and (.createdAt|integer) and (.updatedAt|integer and .>=0) and .updatedAt>=.createdAt;
def protected: .submissionUnconfirmed or (.processState=="pending" or .processState=="running" or .processState=="unconfirmed");
def observation:
  (.invocationId|invocation) and (.state=="accepted" or .state=="observing" or .state=="completed")
  and (.outcome==null or .outcome=="observed" or .outcome=="partial" or .outcome=="failed")
  and (.processState=="pending" or .processState=="running" or .processState=="succeeded" or .processState=="failed" or .processState=="stopped" or .processState=="unconfirmed")
  and (.readiness=="unknown" or .readiness=="reachable" or .readiness=="unreachable")
  and (.exitCode==null or (.exitCode|integer and .<=255)) and (.exitSignal==null or (.exitSignal|integer and .>=1 and .<=128))
  and (.error==null or (.error|fields(["code","message","recovery"];[]) and all(.[];plain and length>0 and length<=2048)))
  and (.stopRequested|type=="boolean") and (.submissionUnconfirmed|type=="boolean")
  and (if protected then true else .state=="completed" end);
def run:
  fields(["id","requestId","projectId","checkoutId","actionId","definitionRevision","definitionHash","definitionSnapshot","cwd","unitName","bootId","invocationId","createdAt","updatedAt","state","outcome","processState","readiness","exitCode","exitSignal","error","stopRequested","submissionUnconfirmed"];[])
  and (.id|id("r")) and (.requestId|id("req")) and (.projectId|id("p")) and (.checkoutId|id("c")) and (.actionId|id("a"))
  and (.definitionRevision|integer and .>0) and (.definitionHash|hash) and (.definitionSnapshot|definition)
  and .definitionSnapshot.id==.actionId and .definitionSnapshot.projectId==.projectId and .definitionSnapshot.revision==.definitionRevision
  and (.cwd|absolute) and .unitName==("aranea-project-"+(.id|ltrimstr("r-"))+".service") and (.bootId|uuid)
  and (.createdAt|integer) and (.updatedAt|integer) and .updatedAt>=.createdAt and observation;
def receipt: fields(["requestId","hash","runId","createdAt"];[]) and (.requestId|id("req")) and (.hash|hash) and (.runId|id("r")) and (.createdAt|integer);
def valid:
  fields(["schemaVersion","revision","definitions","runs","requests"];[]) and .schemaVersion==1 and (.revision|integer)
  and (.definitions|type=="array" and length<=200 and all(.[];definition) and (map(.id)|distinct) and (group_by(.projectId)|all(.[];length<=50)))
  and (.runs|type=="array" and all(.[];run) and (map(.id)|distinct) and ([.[]|select(protected)]|length)<=50 and ([.[]|select(protected|not)]|length)<=100
    and ([.[]|select(protected)|[.projectId,.checkoutId,.actionId]]|distinct))
  and (.requests|type=="array" and length<=512 and all(.[];receipt) and (map(.requestId)|distinct))
  and (.runs as $runs | all(.requests[];.runId as $id|any($runs[];.id==$id)))
  and (.requests as $requests | all(.runs[];.id as $id | .requestId as $req | any($requests[];.requestId==$req and .runId==$id)));
def patch:
  fields([];["invocationId","state","outcome","processState","readiness","exitCode","exitSignal","error","submissionUnconfirmed"])
  and length>0;
def request:
  fields(["action","args"];["expectedRevision"]) and ((has("expectedRevision")|not) or (.expectedRevision|integer))
  and (. as $r | .action as $op | .args |
    if $op=="configure" then fields(["projectId","definition"];[]) and (.projectId|id("p")) and (.definition|draft)
    elif $op=="remove" then fields(["projectId","actionId"];[]) and (.projectId|id("p")) and (.actionId|id("a"))
    elif $op=="reserve" then fields(["projectId","checkoutId","actionId","requestId","cwd","definitionRevision","definitionHash","bootId"];[])
      and (.projectId|id("p")) and (.checkoutId|id("c")) and (.actionId|id("a")) and (.requestId|id("req")) and (.cwd|absolute)
      and (.definitionRevision|integer and .>0) and (.definitionHash|hash) and (.bootId|uuid)
    elif $op=="observe" then ($r|has("expectedRevision")) and fields(["runId","expectedInvocationId","patch"];[])
      and (.runId|id("r")) and (.expectedInvocationId|invocation) and (.patch|patch)
    elif $op=="request-stop" then fields(["runId"];[]) and (.runId|id("r"))
    elif $op=="prune" then fields([];[]) else false end);
def initial: {schemaVersion:1,revision:0,definitions:[],runs:[],requests:[]};
def retain($now;$recent):
  .runs=([.runs[]|select(protected)]+([.runs[]|select(protected|not)|select(.updatedAt>=$now-604800)]|sort_by(.id==$recent,.updatedAt,.id)|.[-100:]))
  | .runs as $runs | .requests |= map(select(.runId as $id|any($runs[];.id==$id)))
  | .requests as $reqs | ([.runs[]|.requestId]+[.runs[]|select(protected)|.id as $id|$reqs[]|select(.runId==$id)|.requestId]) as $keep
  | (512-($keep|unique|length)) as $slots
  | .requests=([.requests[]|select(.requestId as $id|$keep|index($id))]+(if $slots>0 then [.requests[]|select(.requestId as $id|$keep|index($id)|not)]|sort_by(.createdAt,.requestId)|.[-$slots:] else [] end))
  | if (.requests|length)>512 then error("CAPACITY_EXCEEDED") else . end;
def retain($now): retain($now;null);
def mutate($r;$ctx):
  . as $before | $r.args as $a |
  if $r.action=="configure" then
    if $a.definition.id and (any(.definitions[];.id==$a.definition.id and .projectId==$a.projectId)|not) then error("ACTION_NOT_FOUND") else . end
    | ([.definitions[]|select(.id==$a.definition.id)][0]//null) as $old
    | ($a.definition+{id:($old.id//("a-"+$ctx.uuid)),projectId:$a.projectId,revision:(($old.revision//0)+1),createdAt:($old.createdAt//$ctx.now),updatedAt:$ctx.now,timeoutSeconds:(if $a.definition.kind=="command" then $a.definition.timeoutSeconds//300 else null end)}) as $d
    | .definitions=([.definitions[]|select(.id!=$d.id)]+[$d])
    | if (.definitions|length)>200 or ([.definitions[]|select(.projectId==$a.projectId)]|length)>50 then error("CAPACITY_EXCEEDED") else . end
  elif $r.action=="remove" then
    if any(.runs[];.actionId==$a.actionId and protected) then error("RUN_PROTECTED")
    elif any(.definitions[];.id==$a.actionId and .projectId==$a.projectId) then .definitions|=map(select(.id!=$a.actionId)) else error("ACTION_NOT_FOUND") end
  elif $r.action=="reserve" then
    ([.requests[]|select(.requestId==$a.requestId)][0]//null) as $receipt
    | if $receipt then if $receipt.hash!=$ctx.requestHash then error("REQUEST_CONFLICT") else . end
      else retain($ctx.now)
      | ([.runs[]|select(.projectId==$a.projectId and .checkoutId==$a.checkoutId and .actionId==$a.actionId and protected)][0]//null) as $existing
      | if $existing then . else
        if ([.runs[]|select(protected)]|length)>=50 then error("CAPACITY_EXCEEDED") else . end
        | ([.definitions[]|select(.id==$a.actionId and .projectId==$a.projectId)][0]//error("ACTION_NOT_FOUND")) as $d
        | .runs += [{id:("r-"+$ctx.uuid),requestId:$a.requestId,projectId:$a.projectId,checkoutId:$a.checkoutId,actionId:$a.actionId,
          definitionRevision:$d.revision,definitionHash:$a.definitionHash,definitionSnapshot:$d,cwd:$a.cwd,unitName:("aranea-project-"+$ctx.uuid+".service"),bootId:$a.bootId,
          invocationId:null,createdAt:$ctx.now,updatedAt:$ctx.now,state:"accepted",outcome:null,processState:"pending",readiness:"unknown",exitCode:null,exitSignal:null,error:null,stopRequested:false,submissionUnconfirmed:true}]
        end
      | .requests += [{requestId:$a.requestId,hash:$ctx.requestHash,runId:($existing.id//("r-"+$ctx.uuid)),createdAt:$ctx.now}]
      | retain($ctx.now)
      end
  elif $r.action=="observe" or $r.action=="request-stop" then
    if (any(.runs[];.id==$a.runId)|not) then error("RUN_NOT_FOUND") else . end
    | .runs |= map(if .id!=$a.runId then . else
      if $r.action=="request-stop" then .stopRequested=true | .updatedAt=$ctx.now
      elif .invocationId!=$a.expectedInvocationId or (.invocationId!=null and ($a.patch|has("invocationId")) and .invocationId!=$a.patch.invocationId) then error("RUN_IDENTITY_LOST")
      elif (protected|not) then error("RUN_TERMINAL")
      else .+$a.patch | .updatedAt=$ctx.now | if observation then . else error("INVALID_REQUEST") end end end)
    | retain($ctx.now;$a.runId)
  elif $r.action=="prune" then retain($ctx.now)
  else error("INVALID_REQUEST") end
  | if .!=$before then .revision+=1 else . end;
if $operation=="initial" then initial
elif $operation=="validate" then try valid catch false
elif $operation=="request" then try request catch false
elif $operation=="protected" then any(.runs[];protected)
elif $operation=="mutate" then mutate($action_request[0];$action_context[0])
else error("INVALID_OPERATION") end
