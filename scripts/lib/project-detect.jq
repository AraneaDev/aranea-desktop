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

# One target name per input line, already filtered by the shell's awk reader.
def make: select(usable_name) | suggestion("makefile"; $ctx.path; "."; .; (if service_target then "service" else "command" end); ["make", .]; "");
# `just --dump --dump-format json`: public recipes whose parameters all have defaults or are variadic-star.
def just:
  (.recipes // {}) | to_entries[] | .key as $k | .value as $r
  | select(($k|usable_name) and ($k|startswith("_")|not) and ($r.private != true) and ((($r.attributes // [])|index("private"))==null))
  | select(($r.parameters // []) | all(.default != null or .kind == "star"))
  | suggestion("justfile"; $ctx.path; "."; $k; (if $k|service_target then "service" else "command" end); ["just", $k]; "");

# `cargo`: workspace roots get --workspace commands; packages get run only with a binary.
def cargo:
  if has("workspace") then
    (["test","build","clippy"][] as $c | suggestion("cargo"; "Cargo.toml"; "."; $c; "command"; ["cargo",$c,"--workspace"]; ""))
  elif has("package") then
    (["test","build","clippy"][] as $c | suggestion("cargo"; "Cargo.toml"; "."; $c; "command"; ["cargo",$c]; "")),
    (if (((.bin // [])|length) > 0) or $ctx.main then suggestion("cargo"; "Cargo.toml"; "."; "run"; "command"; ["cargo","run"]; "") else empty end)
  else empty end;
# Declared dependency strings across PEP 621, PEP 735 and poetry tables.
def python_deps:
  [ (.project.dependencies // [])[],
    ((.project["optional-dependencies"] // {})|.[]?|arrays|.[]),
    ((.["dependency-groups"] // {})|.[]?|arrays|.[]),
    ((.tool.poetry.group // {})|.[]?|(.dependencies // {})|keys[]),
    ((.tool.poetry["dev-dependencies"] // {})|keys[]) ] | map(select(type=="string"));
def python:
  (if $ctx.uv or (.tool.uv != null) then ["uv","run"] elif $ctx.poetry or (.tool.poetry != null) then ["poetry","run"] else [] end) as $run
  | (if (.tool.pytest != null) or (python_deps|any(test("\\Apytest(\\z|[^A-Za-z0-9_.-])"; "i")))
     then suggestion("python"; "pyproject.toml"; "."; "pytest"; "command"; $run+["pytest"]; "") else empty end),
    ((.project.scripts // {})|keys_unsorted[]|select(usable_name)|suggestion("python"; "pyproject.toml"; "."; .; "command"; $run+[.]; ""));

# `composer.json`: scripts without event hooks; Laravel adds artisan test/serve.
def composer:
  ((.scripts // {})|to_entries[]
    | select((.key|usable_name) and (.key|test("\\A(pre|post)-")|not))
    | (.value|if type=="array" then map(tostring)|join(" && ") else tostring end) as $body
    | suggestion("composer"; "composer.json"; "."; .key; (if .key|service_script then "service" else "command" end); ["composer","run-script",.key]; $body)),
  (if $ctx.artisan and ((.require // {})|has("laravel/framework")) then
     suggestion("composer"; "composer.json"; "."; "artisan test"; "command"; ["php","artisan","test"]; ""),
     suggestion("composer"; "composer.json"; "."; "artisan serve"; "service"; ["php","artisan","serve"]; "php artisan serve")
   else empty end);

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
elif $op=="composer" then composer
elif $op=="make" then make
elif $op=="just" then just
elif $op=="cargo" then cargo
elif $op=="python" then python
elif $op=="assemble" then assemble
else error("unknown op") end
