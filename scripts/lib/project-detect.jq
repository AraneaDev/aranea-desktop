# Pure detection rules. The shell owns every file read and helper process;
# values from repository files only ever leave here as JSON strings.
def plain: type=="string" and (test("[\\x00-\\x1f\\x7f]")|not);
def usable_name: plain and length>=1 and length<=100;
def service_script: test("\\A(dev|start|serve|preview|watch)([:-].*)?\\z");
def service_target: (["dev","serve","run","watch","start"]|index(.))!=null;
# Words of a command after leading VAR=value assignments.
def command_words: [splits("\\s+")|select(length>0)] | until((length==0) or (.[0]|test("\\A[A-Za-z_][A-Za-z0-9_]*=")|not); .[1:]);
# Explicit port evidence from command text only; config files are never parsed.
def evidence($body):
  ($body|tostring) as $b
  | ([$b|capture("(?:\\A|\\s)(?:--port[= ]|-p\\s+)(?<port>[0-9]{1,5})(?:\\s|\\z)")][0].port) as $flag
  | ([$b|splits("\\s+")|select(length>0)]) as $all
  | ($b|command_words) as $w
  | ([$all[:(($all|length)-($w|length))][]|capture("\\APORT=(?<port>[0-9]{1,5})\\z")][0].port) as $env
  | (if $flag then {port:($flag|tonumber),evidence:"Port set in the command"}
    elif $env then {port:($env|tonumber),evidence:"PORT set in the command"}
    elif $w[0]=="vite" and (($w|length)==1 or (["dev","serve"]|index($w[1]))!=null or ($w[1]|startswith("-"))) then {port:5173,evidence:"Vite default port"}
    elif $w[0:2]==["next","dev"] then {port:3000,evidence:"Next.js default port"}
    elif $w[0:2]==["astro","dev"] then {port:4321,evidence:"Astro default port"}
    elif $w[0:3]==["php","artisan","serve"] then {port:8000,evidence:"Laravel default port"}
    else null end)
  | if . != null and .port>=1 and .port<=65535 then . else null end;
# One inert configure draft plus presentation metadata.
def suggestion($source; $sourcePath; $cwd; $entry; $kind; $argv; $body):
  (if $kind=="service" then evidence($body) else null end) as $e
  | {key:([$source,$cwd,$entry]|join(":")),source:$source,sourcePath:$sourcePath,entry:$entry,
     label:(if $cwd=="." then $entry else $cwd+" · "+$entry end),
     definition:{name:((if $cwd=="." then $entry else ($cwd|split("/")|last)+": "+$entry end)|.[0:120]),
       kind:$kind,argv:$argv,cwdRelative:$cwd,timeoutSeconds:(if $kind=="command" then 300 else null end),
       previewUrl:(if $e then "http://127.0.0.1:\($e.port)/" else null end)},
     previewEvidence:($e.evidence // null),alreadySaved:false};

def package_manager:
  ((.packageManager // "")|tostring|split("@")[0]) as $declared
  | if (["npm","pnpm","yarn","bun"]|index($declared))!=null then $declared
    elif ($ctx.locks|index("pnpm-lock.yaml"))!=null then "pnpm"
    elif ($ctx.locks|index("yarn.lock"))!=null then "yarn"
    elif ($ctx.locks|index("bun.lock"))!=null or ($ctx.locks|index("bun.lockb"))!=null then "bun"
    else "npm" end;
def workspaces:
  (.workspaces | if type=="array" then . elif type=="object" then (.packages // []) else [] end)
  | .[] | select(type=="string" and plain);
def package_json:
  (.scripts // {}) as $s
  | $s | to_entries[]
  | select((.key|usable_name) and (.value|type)=="string")
  | .key as $k
  | select((["prepare","install","preinstall","postinstall","prepublish","prepublishOnly","prepack","postpack"]|index($k))==null)
  | select((($k|test("\\A(pre|post).")) and ($s|has($k|sub("\\A(pre|post)";""))))|not)
  | suggestion("package.json"; $ctx.path; $ctx.cwd; $k; (if $k|service_script then "service" else "command" end); [$ctx.pm,"run",$k]; .value);

# Deduplicate, cap at 100, mark saved and keep the most severe status per source.
def severity: {"invalid":4,"truncated":3,"unavailable":2,"found":1,"absent":0}[.status] // 0;
def assemble:
  (reduce .[] as $s ({seen:{},out:[]}; if .seen[$s.key] then . else .seen[$s.key]=true | .out+=[$s] end) | .out) as $all
  | ($all[100:]|map(.source)|unique) as $dropped
  | {suggestions:($all[:100]|map(. as $s | .alreadySaved=any($ctx.saved[]; .argv==$s.definition.argv and .cwdRelative==$s.definition.cwdRelative))),
     sources:(($ctx.sources + ($dropped|map({source:.,status:"truncated",reason:"More than 100 commands found; showing the first 100."})))
       | group_by(.source) | map(max_by(severity)))};

if $op=="package-manager" then package_manager
elif $op=="workspaces" then workspaces
elif $op=="package-json" then package_json
elif $op=="assemble" then assemble
else error("unknown op") end
