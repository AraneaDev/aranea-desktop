# Registry schema, request validation, and pure mutations. Filesystem/Git reads
# and opaque ID generation belong to the shell boundary, never this filter.
def text: type == "string" and length > 0 and (contains("\u0000")|not);
def path: text and startswith("/") and (test("[\\x00-\\x1f\\x7f]")|not);
def integer: type == "number" and . == floor;
def opaque($prefix): text and test("^" + $prefix + "-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$");
def mode: . == "dedicated" or . == "current";
def editor: . == null or . == "code" or . == "nvim";
def terminal: . == null or . == "alacritty" or . == "kitty" or . == "foot" or . == "ghostty";
def distinct: length == (unique|length);
def fields($required; $optional): type == "object" and ((keys - ($required + $optional))|length == 0) and ($required - keys|length == 0);
def checkout:
  fields(["id","path","branch","primary"];[]) and (.id|opaque("c")) and (.path|path)
  and (.branch == null or (.branch|text)) and (.primary|type == "boolean");
def project:
  fields(["id","name","commonDir","lastCheckoutId","workspaceMode","tools","checkouts","associations"];[])
  and (.id|opaque("p")) and (.name|text) and (.commonDir|path) and (.workspaceMode|mode)
  and (.tools|fields(["editorId","terminalId"];[]) and (.editorId|editor) and (.terminalId|terminal))
  and (.checkouts|type == "array" and length > 0 and all(.[];checkout) and (map(.id)|distinct) and (map(.path)|distinct))
  and (.lastCheckoutId as $last | any(.checkouts[];.id == $last))
  and (.checkouts as $checkouts | .associations|type == "array" and all(.[];
    fields(["checkoutId","mode","workspaceId","separate"];[]) and (.checkoutId as $id | any($checkouts[];.id == $id))
    and (.mode|mode) and (.workspaceId == null or (.workspaceId|integer and . > 0)) and (.separate|type == "boolean")))
  and ([.associations[]|if .separate then .checkoutId else "normal" end]|distinct);
def valid:
  fields(["schemaVersion","revision","roots","ignored","projects"];[]) and .schemaVersion == 1 and (.revision|integer and . >= 0)
  and (.roots|type == "array" and all(.[]; fields(["id","path"];[]) and (.id|opaque("r")) and (.path|path)) and (map(.id)|distinct) and (map(.path)|distinct))
  and (.ignored|type == "array" and all(.[]; fields(["path","commonDir"];[]) and (.path|path) and (.commonDir|path)) and (map(.path)|distinct))
  and (.projects|type == "array" and all(.[];project) and (map(.id)|distinct) and (map(.commonDir)|distinct))
  and ([.projects[].checkouts[].id]|distinct) and ([.projects[].checkouts[].path]|distinct);
def request_valid:
  fields(["action","args"];["expectedRevision"]) and (.action|text) and (.args|type == "object")
  and ((has("expectedRevision")|not) or (.expectedRevision|integer and . >= 0))
  and (.action as $action | .args |
    if $action == "root-add" or $action == "ignore" or $action == "unignore" then fields(["path"];[]) and (.path|text)
    elif $action == "root-remove" then fields(["rootId"];[]) and (.rootId|text)
    elif $action == "register" then fields(["paths"];[]) and (.paths|type == "array" and length > 0 and all(.[];text))
    elif $action == "remove" then fields(["projectId"];[]) and (.projectId|text)
    elif $action == "configure" then fields(["projectId"];["name","editorId","terminalId","workspaceMode"]) and (.projectId|text)
      and ((has("name")|not) or (.name|text)) and ((has("editorId")|not) or (.editorId|editor))
      and ((has("terminalId")|not) or (.terminalId|terminal)) and ((has("workspaceMode")|not) or (.workspaceMode|mode))
    elif $action == "relocate" then fields(["projectId","checkoutId","path"];[]) and (.projectId|text) and (.checkoutId|text) and (.path|text)
    elif $action == "select-checkout" then fields(["projectId","checkoutId"];[]) and (.projectId|text) and (.checkoutId|text)
    elif $action == "associate" then fields(["projectId","checkoutId","mode","workspaceId","separate"];[]) and (.projectId|text) and (.checkoutId|text)
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
        workspaceMode:"dedicated",tools:{editorId:null,terminalId:null},checkouts:[($checkout|{id,path,branch,primary})],associations:[]}] end
      | .ignored |= map(select(.path != $checkout.path)))
  elif $r.action == "configure" then require_project($a.projectId) | .projects |= map(if .id == $a.projectId then
    (if $a|has("name") then .name = $a.name else . end)
    | (if $a|has("workspaceMode") then .workspaceMode = $a.workspaceMode else . end)
    | (if $a|has("editorId") then .tools.editorId = $a.editorId else . end)
    | (if $a|has("terminalId") then .tools.terminalId = $a.terminalId else . end) else . end)
  elif $r.action == "relocate" then require_checkout($a.projectId;$a.checkoutId)
    | if any(.projects[].checkouts[];.path == $a.path and .id != $a.checkoutId) then error("CHECKOUT_CONFLICT") else . end
    | .projects |= map(if .id == $a.projectId then .commonDir = $a.commonDir | .checkouts |= map(if .id == $a.checkoutId then .path = $a.path | .branch = $a.branch | .primary = $a.primary else . end) else . end)
  elif $r.action == "remove" then require_project($a.projectId) | .projects |= map(select(.id != $a.projectId))
  elif $r.action == "select-checkout" then require_checkout($a.projectId;$a.checkoutId) | .projects |= map(if .id == $a.projectId then .lastCheckoutId = $a.checkoutId else . end)
  elif $r.action == "associate" then require_checkout($a.projectId;$a.checkoutId) | .projects |= map(if .id == $a.projectId then
    .associations = ([.associations[]|select(if $a.separate then (.separate|not) or .checkoutId != $a.checkoutId else .separate end)]
      + [($a|{checkoutId,mode,workspaceId,separate})]) else . end)
  else error("INVALID_REQUEST") end) | .revision += 1;
if $operation == "validate" then try valid catch false
elif $operation == "request" then try request_valid catch false
elif $operation == "mutate" then mutate($request)
else error("INVALID_OPERATION") end
