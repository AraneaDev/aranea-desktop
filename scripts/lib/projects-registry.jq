# Registry schema, request validation, and pure mutations. Filesystem/Git reads
# and opaque ID generation belong to the shell boundary, never this filter.
def text: type == "string" and length > 0 and (contains("\u0000")|not);
def path: text and startswith("/") and (test("[\\x00-\\x1f\\x7f]")|not);
def integer: type == "number" and . == floor;
def opaque($prefix): text and test("^" + $prefix + "-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$");
def mode: . == "dedicated" or . == "current";
def editor: . == null or . == "code" or . == "nvim";
def terminal: . == null or . == "alacritty" or . == "kitty" or . == "foot" or . == "ghostty";
def agent: . == null or . == "claude" or . == "codex";
def roles: type == "array" and length > 0 and all(.[]; . == "editor" or . == "terminal" or . == "agent")
  and (. as $r | ["editor","terminal","agent"] | map(select(. as $x | $r | index($x))) == $r);
def distinct: length == (unique|length);
def fields($required; $optional): type == "object" and ((keys - ($required + $optional))|length == 0) and ($required - keys|length == 0);
def checkout:
  fields(["id","path","branch","primary"];[]) and (.id|opaque("c")) and (.path|path)
  and (.branch == null or (.branch|text)) and (.primary|type == "boolean");
def tools:
  fields(["editorId","terminalId","agentId"];[]) and (.editorId|editor) and (.terminalId|terminal) and (.agentId|agent);
def profile_draft:
  fields(["name","roles","tools"];["id","revision"]) and (.name|text) and (.roles|roles) and (.tools|tools)
  and ((has("id")|not) or (.id|opaque("f")))
  and ((has("revision")|not) or (.revision|integer and . > 0));
def profile:
  profile_draft and has("id") and has("revision");
def workspace: integer and . > 0;
def environment:
  fields(["id","projectId","checkoutId","activationId","workspaceId","sessionId","createdAt","checkoutSnapshot","profileSnapshot","resolvedTools"];["mode","placedAt"])
  and ((has("mode")|not) or (.mode|mode)) and ((has("placedAt")|not) or (.placedAt|integer and . >= 0))
  and (.id|opaque("e")) and (.projectId|opaque("p")) and (.checkoutId|opaque("c")) and (.activationId|opaque("a"))
  and (.workspaceId|workspace) and (.sessionId|text) and (.createdAt|integer and . >= 0)
  and (.checkoutSnapshot|checkout) and (.profileSnapshot|profile) and (.resolvedTools|tools)
  and .checkoutSnapshot.id == .checkoutId;
def project($schema):
  fields(["id","name","commonDir","lastCheckoutId","workspaceMode","tools","checkouts","associations"] + (if $schema == 2 then ["profiles","lastProfileId","environments"] else [] end);["openRoles"])
  and (.id|opaque("p")) and (.name|text) and (.commonDir|path) and (.workspaceMode|mode)
  and ((has("openRoles")|not) or (.openRoles|roles))
  and (.tools|fields(["editorId","terminalId"];["agentId"]) and (.editorId|editor) and (.terminalId|terminal) and ((has("agentId")|not) or (.agentId|agent)))
  and (.checkouts|type == "array" and length > 0 and all(.[];checkout) and (map(.id)|distinct) and (map(.path)|distinct))
  and (.lastCheckoutId as $last | any(.checkouts[];.id == $last))
  and (.checkouts as $checkouts | .associations|type == "array" and all(.[];
    fields(["checkoutId","mode","workspaceId","separate"];["placedAt"]) and (.checkoutId as $id | any($checkouts[];.id == $id))
    and ((has("placedAt")|not) or (.placedAt|integer and . >= 0))
    and (.mode|mode) and (.workspaceId == null or (.workspaceId|integer and . > 0)) and (.separate|type == "boolean")))
  and ([.associations[]|if .separate then .checkoutId else "normal" end]|distinct)
  and (if $schema == 2 then
    (.profiles|type == "array" and all(.[];profile) and (map(.id)|distinct))
    and (.lastProfileId == null or (.lastProfileId as $id | any(.profiles[];.id == $id)))
    and (.id as $projectId | [.checkouts[].id] as $checkoutIds | .environments|type == "array" and all(.[];
      environment and .projectId == $projectId and (.checkoutId as $id | $checkoutIds | index($id) != null)) and (map(.id)|distinct))
  else true end);
def navigation($ids):
  fields(["lastProjectId","pinnedProjectIds","visitedAt"];[])
  and (.lastProjectId == null or (.lastProjectId as $id | $ids | index($id) != null))
  and (.pinnedProjectIds|type == "array" and distinct and all(.[]; . as $id | $ids | index($id) != null))
  and (.visitedAt|type == "object" and all(to_entries[]; (.key as $id | $ids | index($id) != null) and (.value|integer and . >= 0)));
def valid:
  .schemaVersion as $schema |
  fields(["schemaVersion","revision","roots","ignored","projects"];["navigation"]) and ($schema == 1 or $schema == 2) and (.revision|integer and . >= 0)
  and (.roots|type == "array" and all(.[]; fields(["id","path"];[]) and (.id|opaque("r")) and (.path|path)) and (map(.id)|distinct) and (map(.path)|distinct))
  and (.ignored|type == "array" and all(.[]; fields(["path","commonDir"];[]) and (.path|path) and (.commonDir|path)) and (map(.path)|distinct))
  and (.projects|type == "array" and all(.[];project($schema)) and (map(.id)|distinct) and (map(.commonDir)|distinct))
  and (if $schema == 2 then ([.projects[].profiles[].id]|distinct) and ([.projects[].environments[].id]|distinct) and ([.projects[].environments[]|[.sessionId,.activationId]]|distinct) else true end)
  and ([.projects[].checkouts[].id]|distinct) and ([.projects[].checkouts[].path]|distinct)
  and ((has("navigation")|not) or ([.projects[].id] as $ids | .navigation | navigation($ids)));
# Pure migration: the shell supplies opaque profile IDs under the store lock.
def migrate_v1($profileIds):
  if .schemaVersion != 1 then error("REGISTRY_INVALID") else
    .projects |= map(. + {profiles:[{id:$profileIds[.id],name:"Default",revision:1,
      roles:(.openRoles // ["editor","terminal"]),tools:(.tools + {agentId:(.tools.agentId // null)})}],
      lastProfileId:$profileIds[.id],environments:[]})
    | .schemaVersion = 2 | .revision += 1
  end;
def request_valid:
  fields(["action","args"];["expectedRevision"]) and (.action|text) and (.args|type == "object")
  and ((has("expectedRevision")|not) or (.expectedRevision|integer and . >= 0))
  and (if .action == "environment-associate" then has("expectedRevision") else true end)
  and (.action as $action | .args |
    if $action == "root-add" or $action == "ignore" or $action == "unignore" then fields(["path"];[]) and (.path|text)
    elif $action == "root-remove" then fields(["rootId"];[]) and (.rootId|text)
    elif $action == "register" then fields(["paths"];[]) and (.paths|type == "array" and length > 0 and all(.[];text))
    elif $action == "remove" then fields(["projectId"];[]) and (.projectId|text)
    elif $action == "navigation-set" then
      (fields(["projectId","visit"];[]) and (.projectId|text) and .visit == true)
      or (fields(["projectId","pinned"];[]) and (.projectId|text) and (.pinned|type == "boolean"))
    elif $action == "profile-save" then
      fields(["projectId","profile"];["expectedProfileRevision"]) and (.projectId|opaque("p")) and (.profile|profile_draft)
      and ((has("expectedProfileRevision")|not) or (.expectedProfileRevision|integer and . > 0))
    elif $action == "profile-remove" then
      fields(["projectId","profileId","expectedProfileRevision"];[]) and (.projectId|opaque("p")) and (.profileId|opaque("f"))
      and (.expectedProfileRevision|integer and . > 0)
    elif $action == "environment-register" then
      fields(["projectId","environment"];[]) and (.projectId|opaque("p")) and (.environment | if has("id") then environment else . + {id:"e-00000000-0000-4000-8000-000000000000"} | environment end) and .environment.projectId == .projectId
    elif $action == "environment-associate" then
      fields(["projectId","environmentId","previousWorkspaceId","workspaceId"];["placedAt"]) and (.projectId|opaque("p")) and (.environmentId|opaque("e"))
      and (.previousWorkspaceId|workspace) and (.workspaceId|workspace) and ((has("placedAt")|not) or (.placedAt|integer and . >= 0))
    elif $action == "environment-forget" then
      fields(["projectId","environmentId"];[]) and (.projectId|opaque("p")) and (.environmentId|opaque("e"))
    elif $action == "configure" then fields(["projectId"];["name","editorId","terminalId","workspaceMode","openRoles","agentId"]) and (.projectId|text)
      and ((has("name")|not) or (.name|text)) and ((has("editorId")|not) or (.editorId|editor))
      and ((has("terminalId")|not) or (.terminalId|terminal)) and ((has("workspaceMode")|not) or (.workspaceMode|mode))
      and ((has("openRoles")|not) or (.openRoles|roles)) and ((has("agentId")|not) or (.agentId|agent))
    elif $action == "relocate" then fields(["projectId","checkoutId","path"];[]) and (.projectId|text) and (.checkoutId|text) and (.path|text)
    elif $action == "select-checkout" then fields(["projectId","checkoutId"];[]) and (.projectId|text) and (.checkoutId|text)
    elif $action == "associate" then fields(["projectId","checkoutId","mode","workspaceId","separate"];["placedAt"]) and (.projectId|text) and (.checkoutId|text)
      and ((has("placedAt")|not) or (.placedAt|integer and . >= 0))
      and (.mode|mode) and (.workspaceId == null or (.workspaceId|integer and . > 0)) and (.separate|type == "boolean")
    else false end);
def require_project($id): if any(.projects[];.id == $id) then . else error("PROJECT_NOT_FOUND") end;
def require_checkout($p;$c): require_project($p) | if any(.projects[]|select(.id == $p)|.checkouts[];.id == $c) then . else error("CHECKOUT_NOT_FOUND") end;
def mutate($r):
  $r.args as $a |
  (if $r.action == "root-add" then
    if any(.roots[];.path == $a.path) then . else .roots += [{id:$a.id,path:$a.path}] end
  elif $r.action == "root-remove" then
    if any(.roots[];.id == $a.rootId) then .roots |= map(select(.id != $a.rootId)) else error("ROOT_NOT_FOUND") end
  elif $r.action == "ignore" then .ignored = ([.ignored[]|select(.path != $a.path)] + [{path:$a.path,commonDir:$a.commonDir}])
  elif $r.action == "unignore" then .ignored |= map(select(.path != $a.path))
  elif $r.action == "register" then
    reduce $a.checkouts[] as $checkout (.;
      if any(.projects[]|select(.commonDir != $checkout.commonDir)|.checkouts[];.path == $checkout.path) then error("CHECKOUT_CONFLICT")
      elif any(.projects[];.commonDir == $checkout.commonDir) then
        .projects |= map(if .commonDir == $checkout.commonDir and (any(.checkouts[];.path == $checkout.path)|not)
          then .checkouts += [($checkout|{id,path,branch,primary})] else . end)
      else .projects += [{id:$checkout.projectId,name:$checkout.name,commonDir:$checkout.commonDir,lastCheckoutId:$checkout.id,
        workspaceMode:"dedicated",tools:{editorId:null,terminalId:null},checkouts:[($checkout|{id,path,branch,primary})],associations:[],profiles:[],lastProfileId:null,environments:[]}] end
      | .ignored |= map(select(.path != $checkout.path)))
  elif $r.action == "profile-save" then require_project($a.projectId)
    | if any(.projects[]|select(.id != $a.projectId)|.profiles[];.id == $a.profile.id) then error("PROFILE_CONFLICT") else . end
    | .projects |= map(if .id == $a.projectId then
      ([.profiles[]|select(.id == $a.profile.id)][0]) as $old
      | if $old != null then
          if $a.expectedProfileRevision != $old.revision or (($a.profile|has("revision")) and $a.profile.revision != $old.revision)
          then error("PROFILE_CONFLICT") else .profiles |= map(if .id == $a.profile.id then $a.profile + {revision:($old.revision + 1)} else . end) end
        elif ($a|has("expectedProfileRevision")) or (($a.profile|has("revision")) and $a.profile.revision != 1) then error("PROFILE_CONFLICT")
        else .profiles += [($a.profile + {revision:1})] end
      else . end)
  elif $r.action == "profile-remove" then require_project($a.projectId) | .projects |= map(if .id == $a.projectId then
      ([.profiles[]|select(.id == $a.profileId)][0]) as $old
      | if $old == null then error("PROFILE_NOT_FOUND") elif $old.revision != $a.expectedProfileRevision then error("PROFILE_CONFLICT")
        else .profiles |= map(select(.id != $a.profileId))
          | if .lastProfileId == $a.profileId then .lastProfileId = (.profiles[0].id // null) else . end end
      else . end)
  # Branch records fresh launch context; exact ID/path/primary still guard checkout identity.
  elif $r.action == "environment-register" then require_checkout($a.projectId;$a.environment.checkoutId)
    | if any(.projects[].environments[];.id == $a.environment.id or (.sessionId == $a.environment.sessionId and .activationId == $a.environment.activationId)) then error("ENVIRONMENT_CONFLICT") else . end
    | .projects |= map(if .id == $a.projectId then
        if any(.checkouts[];.id == $a.environment.checkoutId and .id == $a.environment.checkoutSnapshot.id and .path == $a.environment.checkoutSnapshot.path and .primary == $a.environment.checkoutSnapshot.primary) then
          .environments += [$a.environment]
          | if any(.profiles[];.id == $a.environment.profileSnapshot.id) then .lastProfileId = $a.environment.profileSnapshot.id else . end
        else error("CHECKOUT_CONFLICT") end
      else . end)
  elif $r.action == "environment-associate" or $r.action == "environment-forget" then require_project($a.projectId)
    | .projects |= map(if .id == $a.projectId then
        if any(.environments[];.id == $a.environmentId) then
          if $r.action == "environment-forget" then .environments |= map(select(.id != $a.environmentId))
          else .environments |= map(if .id == $a.environmentId then
            if .workspaceId == $a.previousWorkspaceId then .workspaceId = $a.workspaceId | (if $a|has("placedAt") then .placedAt = $a.placedAt else . end) else error("ENVIRONMENT_CONFLICT") end
            else . end) end
        else error("ENVIRONMENT_NOT_FOUND") end
      else . end)
  elif $r.action == "configure" then require_project($a.projectId) | .projects |= map(if .id == $a.projectId then
    (if $a|has("name") then .name = $a.name else . end)
    | (if $a|has("workspaceMode") then .workspaceMode = $a.workspaceMode else . end)
    | (if $a|has("editorId") then .tools.editorId = $a.editorId else . end)
    | (if $a|has("terminalId") then .tools.terminalId = $a.terminalId else . end)
    | (if $a|has("openRoles") then .openRoles = $a.openRoles else . end)
    | (if $a|has("agentId") then .tools.agentId = $a.agentId else . end) else . end)
  elif $r.action == "relocate" then require_checkout($a.projectId;$a.checkoutId)
    | if any(.projects[].checkouts[];.path == $a.path and .id != $a.checkoutId) then error("CHECKOUT_CONFLICT") else . end
    | .projects |= map(if .id == $a.projectId then .commonDir = $a.commonDir | .checkouts |= map(if .id == $a.checkoutId then .path = $a.path | .branch = $a.branch | .primary = $a.primary else . end) else . end)
  elif $r.action == "navigation-set" then require_project($a.projectId)
    | .navigation //= {lastProjectId:null,pinnedProjectIds:[],visitedAt:{}}
    | if $a.visit == true then .navigation.lastProjectId = $a.projectId | .navigation.visitedAt[$a.projectId] = $a.visitedAt
      elif $a.pinned then .navigation.pinnedProjectIds = (.navigation.pinnedProjectIds + [$a.projectId] | unique)
      else .navigation.pinnedProjectIds |= map(select(. != $a.projectId)) end
  elif $r.action == "remove" then require_project($a.projectId) | .projects |= map(select(.id != $a.projectId))
    | if has("navigation") then
        .navigation |= (if .lastProjectId == $a.projectId then .lastProjectId = null else . end
          | .pinnedProjectIds |= map(select(. != $a.projectId)) | del(.visitedAt[$a.projectId]))
      else . end
  elif $r.action == "select-checkout" then require_checkout($a.projectId;$a.checkoutId) | .projects |= map(if .id == $a.projectId then .lastCheckoutId = $a.checkoutId else . end)
  elif $r.action == "associate" then require_checkout($a.projectId;$a.checkoutId) | .projects |= map(if .id == $a.projectId then
    .associations = ([.associations[]|select(if $a.separate then (.separate|not) or .checkoutId != $a.checkoutId else .separate end)]
      + [($a|{checkoutId,mode,workspaceId,separate} + (if has("placedAt") then {placedAt} else {} end))]) else . end)
  else error("INVALID_REQUEST") end) | .revision += 1;
if $operation == "validate" then try valid catch false
elif $operation == "migrate" then migrate_v1($request)
elif $operation == "request" then try request_valid catch false
elif $operation == "mutate" then mutate($request)
else error("INVALID_OPERATION") end
