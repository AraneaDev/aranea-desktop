#!/usr/bin/env bash
# Read-only detection maps repository declarations to inert configure drafts.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
detector="$repo_root/scripts/aranea-project-detect"
work="$ARANEA_TEST_SANDBOX/work"
mkdir -p "$work"
# Fresh fixture checkout per case.
repo() {
  rm -rf -- "${work:?}/$1"
  mkdir -p "$work/$1"
  printf '%s\n' "$work/$1"
}
# Run the detector with optional saved definitions on stdin.
detect() {
  local dir=$1 saved=${2:-[]}
  shift 2 || shift $#
  printf '%s\n' "$saved" | "$detector" --root "$dir" "$@" >"$TMPDIR/out"
}
# Assert a jq predicate against the latest output, printing it on failure.
expect() {
  jq -e "$1" "$TMPDIR/out" >/dev/null || {
    echo "FAIL: $2" >&2
    jq . "$TMPDIR/out" >&2
    exit 1
  }
}
# One suggestion by key.
s() { printf '.suggestions[]|select(.key=="%s")' "$1"; }

# Usage errors exit 2 without output.
status=0
"$detector" --root </dev/null >/dev/null 2>&1 || status=$?
[[ $status == 2 ]]

# Empty checkout: every source absent, no suggestions.
r=$(repo empty)
detect "$r"
expect '.suggestions==[] and (.sources|map(select(.source=="package.json"))[0].status=="absent")' 'empty checkout'

# npm default, lifecycle and pre/post hooks skipped, service classification, evidence.
r=$(repo npm)
cat >"$r/package.json" <<'JSON'
{"scripts":{"test":"node --test","pretest":"lint","build":"tsc","postinstall":"x","prepare":"husky",
 "dev":"vite","dev:api":"node api.js --port 4000","start":"PORT=8080 node server.js","preview":"vite preview",
 "watch":"tsc -w","serve":"next dev","lint":"eslint ."}}
JSON
detect "$r"
expect "$(s 'package.json:.:test')|.definition==({name:\"test\",kind:\"command\",argv:[\"npm\",\"run\",\"test\"],cwdRelative:\".\",timeoutSeconds:300,previewUrl:null})" 'npm test command'
expect '[.suggestions[].entry]|index("pretest")==null and index("postinstall")==null and index("prepare")==null' 'lifecycle skipped'
expect "$(s 'package.json:.:dev')|.definition.kind==\"service\" and .definition.previewUrl==\"http://127.0.0.1:5173/\" and .previewEvidence==\"Vite default port\" and .definition.timeoutSeconds==null" 'vite default'
expect "$(s 'package.json:.:dev:api')|.definition.previewUrl==\"http://127.0.0.1:4000/\" and .previewEvidence==\"Port set in the command\"" 'explicit --port'
expect "$(s 'package.json:.:start')|.definition.previewUrl==\"http://127.0.0.1:8080/\" and .previewEvidence==\"PORT set in the command\"" 'PORT= prefix'
expect "$(s 'package.json:.:preview')|.definition.kind==\"service\" and .definition.previewUrl==null and .previewEvidence==null" 'vite preview has no evidence'
expect "$(s 'package.json:.:watch')|.definition.kind==\"service\" and .definition.previewUrl==null" 'watch service without port'
expect "$(s 'package.json:.:serve')|.definition.previewUrl==\"http://127.0.0.1:3000/\"" 'next dev default'
expect "$(s 'package.json:.:lint')|.definition.kind==\"command\" and .label==\"lint\"" 'lint command'
expect '.sources[]|select(.source=="package.json")|.status=="found"' 'package.json found'

# PORT=N counts only as a leading assignment.
r=$(repo portlate)
printf '{"scripts":{"start":"node server.js PORT=9","serve":"echo PORT=9"}}\n' >"$r/package.json"
detect "$r"
expect "($(s 'package.json:.:start')|.definition.previewUrl==null and .previewEvidence==null) and ($(s 'package.json:.:serve')|.definition.previewUrl==null)" 'trailing PORT= is not evidence'

# Package manager: packageManager field beats lockfiles; lockfiles pick pnpm/yarn/bun.
r=$(repo pm)
printf '{"scripts":{"test":"x"}}\n' >"$r/package.json"
for case in pnpm-lock.yaml:pnpm yarn.lock:yarn bun.lock:bun bun.lockb:bun; do
  rm -f "$r"/*.lock* "$r"/pnpm-lock.yaml
  touch "$r/${case%%:*}"
  detect "$r"
  expect "$(s 'package.json:.:test')|.definition.argv[0]==\"${case##*:}\"" "lockfile ${case%%:*}"
done
printf '{"packageManager":"yarn@4.1.0","scripts":{"test":"x"}}\n' >"$r/package.json"
detect "$r"
expect "$(s 'package.json:.:test')|.definition.argv[0]==\"yarn\"" 'packageManager precedence'

# Workspaces: object form, dir/* expansion, literal folders, pnpm yaml, escapes ignored.
r=$(repo mono)
mkdir -p "$r/apps/web" "$r/apps/docs" "$r/packages/ui" "$r/tools/cli" "$work/outside"
printf '{"workspaces":{"packages":["apps/*","tools/cli","../outside","/abs","packages/**","!apps/docs"]},"scripts":{"test":"x"}}\n' >"$r/package.json"
printf '{"scripts":{"dev":"vite --port 5174"}}\n' >"$r/apps/web/package.json"
printf '{"scripts":{"build":"x"}}\n' >"$r/apps/docs/package.json"
printf '{"scripts":{"build":"x"}}\n' >"$r/tools/cli/package.json"
printf '{"scripts":{"test":"x"}}\n' >"$r/packages/ui/package.json"
printf '{"scripts":{"evil":"x"}}\n' >"$work/outside/package.json"
ln -s "$work/outside" "$r/apps/linked"
touch "$r/pnpm-lock.yaml"
detect "$r"
expect "$(s 'package.json:apps/web:dev')|.definition==({name:\"web: dev\",kind:\"service\",argv:[\"pnpm\",\"run\",\"dev\"],cwdRelative:\"apps/web\",timeoutSeconds:null,previewUrl:\"http://127.0.0.1:5174/\"}) and .label==\"apps/web · dev\" and .sourcePath==\"apps/web/package.json\"" 'workspace package'
expect "$(s 'package.json:tools/cli:build')|.definition.cwdRelative==\"tools/cli\"" 'literal workspace folder'
expect '[.suggestions[].key]|map(select(test("outside|linked|packages/ui")))==[]' 'workspace escape'
expect "$(s 'package.json:apps/docs:build')|.definition.cwdRelative==\"apps/docs\"" 'negations ignored, not applied'
printf '{"scripts":{"test":"x"}}\n' >"$r/package.json"
printf 'packages:\n  - "packages/*"   # shared\n  - '"'"'apps/web'"'"'\nother: 1\n' >"$r/pnpm-workspace.yaml"
detect "$r"
expect "($(s 'package.json:packages/ui:test')|.definition.argv[0]==\"pnpm\") and ([.suggestions[].key]|index(\"package.json:apps/docs:build\")==null)" 'pnpm-workspace.yaml'

# Workspace limit: 33 packages → first 32 and truncated.
r=$(repo many)
printf '{"workspaces":["p/*"],"scripts":{}}\n' >"$r/package.json"
for i in $(seq -w 1 33); do
  mkdir -p "$r/p/$i"
  printf '{"scripts":{"t":"x"}}\n' >"$r/p/$i/package.json"
done
detect "$r"
expect '([.suggestions[]|select(.source=="package.json")]|length)==32 and (.sources[]|select(.source=="package.json")|.status=="truncated")' 'workspace limit'

# Suggestion limit: 101 scripts → 100 and truncated.
r=$(repo big)
jq -n '{scripts:([range(101)]|map({key:"s\(.)",value:"x"})|from_entries)}' >"$r/package.json"
detect "$r"
expect '(.suggestions|length)==100 and (.sources[]|select(.source=="package.json")|.status=="truncated")' 'suggestion limit'

# Hostile script bodies stay literal and never run.
r=$(repo hostile)
# shellcheck disable=SC2016
jq -n '{scripts:{"dev":"$(touch PWNED) `touch PWNED2` \"q\" --port 3001\nsecond","bad\u0001name":"x"}}' >"$r/package.json"
detect "$r"
[[ ! -e $r/PWNED && ! -e $r/PWNED2 ]]
expect "$(s 'package.json:.:dev')|.definition.argv==[\"npm\",\"run\",\"dev\"] and .definition.previewUrl==\"http://127.0.0.1:3001/\"" 'hostile script literal'
expect '[.suggestions[].entry]|map(select(test("bad")))==[]' 'control characters skipped'

# Malformed, oversized and symlinked package.json.
r=$(repo malformed)
printf '{"scripts":' >"$r/package.json"
detect "$r"
expect '.suggestions==[] and (.sources[]|select(.source=="package.json")|.status=="invalid" and .reason=="package.json could not be read.")' 'malformed json'
r=$(repo oversized)
head -c 1048577 /dev/zero | tr '\0' ' ' >"$r/package.json"
detect "$r"
expect '.sources[]|select(.source=="package.json")|.status=="truncated" and (.reason|test("larger than 1 MiB"))' 'oversized file'
r=$(repo linked)
printf '{"scripts":{"evil":"x"}}\n' >"$work/outside/real.json"
ln -s "$work/outside/real.json" "$r/package.json"
detect "$r"
expect '.suggestions==[] and (.sources[]|select(.source=="package.json")|.status=="invalid")' 'symlinked file refused'

# alreadySaved compares argv and cwdRelative only.
r=$(repo saved)
printf '{"scripts":{"test":"x","build":"y"}}\n' >"$r/package.json"
detect "$r" '[{"argv":["npm","run","test"],"cwdRelative":"."},{"argv":["npm","run","build"],"cwdRelative":"sub"}]'
expect "($(s 'package.json:.:test')|.alreadySaved) and ($(s 'package.json:.:build')|.alreadySaved|not)" 'alreadySaved'
# Make edge cases: phony first, assignments, patterns, specials, define blocks, file targets.
r=$(repo make)
cat >"$r/Makefile" <<'MAKE'
CC := gcc
X ::= y
Y ?= z
build: main.o
	$(CC) -o app main.o
main.o: main.c
%.o: %.c
.SUFFIXES:
define RECIPE
fake: target
endef
dev serve: build
lint: CFLAGS=-Wall
-include extra.mk
.PHONY: test lint build.release
test:
build.release:
MAKE
detect "$r"
expect '[.suggestions[]|select(.source=="makefile")|.entry]==["lint","test","build.release","build","dev","serve"]' 'make edge cases'
expect "$(s 'makefile:.:dev')|.definition.kind==\"service\" and .definition.argv==[\"make\",\"dev\"] and .sourcePath==\"Makefile\"" 'make service'
expect '.sources[]|select(.source=="makefile")|.status=="found"' 'make found'
r=$(repo gnumake)
printf 'a:\n' >"$r/GNUmakefile"
printf 'b:\n' >"$r/Makefile"
detect "$r"
expect '[.suggestions[]|select(.source=="makefile")|.entry]==["a"]' 'GNUmakefile wins'

# justfile through a fake just: public recipes without required parameters.
r=$(repo just)
printf 'test:\n\techo hi\n' >"$r/justfile"
fake_just="$ARANEA_TEST_SANDBOX/bin/just"
mkdir -p "$(dirname "$fake_just")"
cat >"$fake_just" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ARANEA_TEST_SANDBOX:?}/just-args"
cat <<'JSON'
{"recipes":{"test":{"name":"test","private":false,"attributes":[],"parameters":[]},
"_hidden":{"name":"_hidden","private":false,"attributes":[],"parameters":[]},
"secret":{"name":"secret","private":false,"attributes":["private"],"parameters":[]},
"deploy":{"name":"deploy","private":false,"attributes":[],"parameters":[{"name":"env","default":null,"kind":"singular"}]},
"fmt":{"name":"fmt","private":false,"attributes":[],"parameters":[{"name":"args","default":null,"kind":"star"}]},
"serve":{"name":"serve","private":false,"attributes":[],"parameters":[{"name":"port","default":"8000","kind":"singular"}]}}}
JSON
SH
chmod +x "$fake_just"
detect "$r" '[]' --just "$fake_just"
expect '[.suggestions[]|select(.source=="justfile")|.entry]==["test","fmt","serve"]' 'just recipes'
expect "$(s 'justfile:.:serve')|.definition.kind==\"service\" and .definition.argv==[\"just\",\"serve\"]" 'just service'
grep -q -- '--dump --dump-format json' "$ARANEA_TEST_SANDBOX/just-args"
detect "$r"
expect '.sources[]|select(.source=="justfile")|.status=="unavailable" and .reason=="Needs just"' 'just missing'
printf '#!/usr/bin/env bash\necho nope\n' >"$fake_just"
detect "$r" '[]' --just "$fake_just"
expect '.sources[]|select(.source=="justfile")|.status=="invalid"' 'just dump unreadable'

# A rule error on valid JSON of an unexpected shape marks only that source invalid.
printf '{"scripts":{"test":"x"},"workspaces":{"packages":5}}\n' >"$r/package.json"
printf '#!/usr/bin/env bash\necho '"'"'{"recipes":{"a":"x"}}'"'"'\n' >"$fake_just"
detect "$r" '[]' --just "$fake_just"
expect '.sources[]|select(.source=="justfile")|.status=="invalid"' 'just odd shape invalid'
expect '[.suggestions[]|select(.source=="justfile")]==[] and ([.suggestions[]|select(.source=="package.json")|.entry]==["test"])' 'odd just keeps other sources'
echo 'project-detect: ok'
