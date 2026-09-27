#!/usr/bin/env bash
# Contract for tools/check: every stage fails on its planted problem, a clean
# tree passes, --staged reads the index, a crashing tool fails its stage.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# A scratch repository with the checker and a few clean files.
scratch="$(mktemp -d)"
cd "$scratch"
git init -q . && git config user.email t@example.invalid && git config user.name t
mkdir -p tools/lib tools/baselines docs
cp "$repo_root/tools/check" tools/
cp "$repo_root"/tools/lib/check-*.sh tools/lib/
cp "$repo_root/tools/check-docs" tools/
mkdir -p types && cp "$repo_root"/types/*.d.ts types/
cp "$repo_root/tools/baselines/em-dash-allow.txt" tools/baselines/
: >tools/baselines/qmllint.txt
: >tools/baselines/coverage.txt
for config in .prettierrc.json .prettierignore .editorconfig .qmlformat.ini eslint.config.js .markdownlint-cli2.jsonc tsconfig.json; do cp "$repo_root/$config" .; done
export ARANEA_CHECK_NODE_MODULES="$repo_root/node_modules"
ln -s "$repo_root/node_modules" node_modules # the configs resolve their plugins from here
printf 'node_modules\n' >.gitignore
printf '{"ok": true}\n' >data.json
printf 'a = 1\n' >conf.toml
printf '# Title\n\nSee [data](../data.json).\n' >docs/readme.md
git add -A && git commit -qm init

# Runs tools/check in the scratch repo, tests skipped, capturing combined output.
run_check() { ARANEA_CHECK_NO_TESTS=1 tools/check "$@" >"$ARANEA_TEST_SANDBOX/out" 2>&1; }

# Clean tree passes the validate stage.
run_check --only validate || {
  cat "$ARANEA_TEST_SANDBOX/out"
  exit 1
}

# Each planted problem fails validate with its own message (Review Focus 1).
plant() { # file content expected-message
  printf '%s' "$2" >"$1"
  git add -A
  if run_check --only validate; then
    echo "validate passed with a bad $1" >&2
    exit 1
  fi
  grep -Fq "$3" "$ARANEA_TEST_SANDBOX/out" || {
    cat "$ARANEA_TEST_SANDBOX/out"
    exit 1
  }
  git checkout -q -- . 2>/dev/null || true
  git reset -q --hard
}
plant data.json '{"ok": }' 'data.json'
plant conf.toml 'a = = 1' 'conf.toml'
plant docs/readme.md $'# Title\n\nSee [gone](missing.md).\n' 'missing.md'
plant docs/dash.md $'# A \xe2\x80\x94 B\n' 'em dash'

# --staged reads the index, not the working tree (Review Focus 2).
printf '{"ok": }' >data.json && git add data.json && printf '{"ok": true}\n' >data.json
if run_check --staged --only validate; then
  echo "--staged checked the working tree" >&2
  exit 1
fi
git reset -q --hard

# A stage whose tool crashes fails (not passes).
fake="$ARANEA_TEST_SANDBOX/fake-bin"
mkdir -p "$fake"
printf '#!/usr/bin/env bash\nexit 99\n' >"$fake/jq"
chmod +x "$fake/jq"
if PATH="$fake:$PATH" run_check --only validate; then
  echo "crashing jq passed" >&2
  exit 1
fi

# Unknown stage and unknown option are usage errors.
if tools/check --only nope >/dev/null 2>&1; then exit 1; fi
if tools/check --bogus >/dev/null 2>&1; then exit 1; fi

# format: unformatted shell, JSON and QML fail; --fix repairs them.
printf '#!/usr/bin/env bash\nif true;then\necho x\nfi\n' >s.sh
printf '{"a":1,\n"b":2}\n' >f.json
git add -A
if run_check --only format; then
  echo "format passed unformatted files" >&2
  exit 1
fi
grep -Fq 's.sh' "$ARANEA_TEST_SANDBOX/out" && grep -Fq 'f.json' "$ARANEA_TEST_SANDBOX/out"
run_check --only format --fix
git add -A
run_check --only format || {
  cat "$ARANEA_TEST_SANDBOX/out"
  exit 1
}
git reset -q --hard
# --fix together with --staged is refused (it would only write a snapshot).
if tools/check --staged --fix --only format >/dev/null 2>&1; then
  echo "--staged --fix accepted" >&2
  exit 1
fi
# lint: an undefined JS name, a markdown heading jump and a workflow typo fail.
mkdir -p plugins/x .github/workflows
printf 'function f() {\n  return missingName\n}\n' >plugins/x/a.js
printf '# T\n\n### Jump\n' >docs/jump.md
cat >.github/workflows/w.yml <<'EOF'
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ matrix.nope }}
EOF
git add -A
if run_check --only lint; then
  echo "lint passed bad files" >&2
  exit 1
fi
for needle in plugins/x/a.js docs/jump.md w.yml; do grep -Fq "$needle" "$ARANEA_TEST_SANDBOX/out" || {
  cat "$ARANEA_TEST_SANDBOX/out"
  exit 1
}; done
git reset -q --hard
# qml: a syntax error always fails.
mkdir -p plugins/q
printf 'import QtQuick\nItem {\n  width: 10 +\n}\n' >plugins/q/Bad.qml
git add -A
if run_check --only qml; then
  echo "qml passed a syntax error" >&2
  exit 1
fi
grep -Fq 'plugins/q/Bad.qml' "$ARANEA_TEST_SANDBOX/out" || {
  cat "$ARANEA_TEST_SANDBOX/out"
  exit 1
}
git reset -q --hard
# The baseline needs strict mode (Omarchy Commons/Ui and Quickshell present).
if [[ -f /usr/share/omarchy/shell/Commons/qmldir && -d /usr/lib/qt6/qml/Quickshell ]]; then
  mkdir -p plugins/q
  printf 'import QtQuick\nItem {\n  property int a: undefinedName\n}\n' >plugins/q/Warn.qml
  git add -A
  # A new warning fails, and --update-baselines refuses to add it.
  if run_check --only qml; then
    echo "qml passed a new warning" >&2
    exit 1
  fi
  grep -Fq 'new warning' "$ARANEA_TEST_SANDBOX/out" || {
    cat "$ARANEA_TEST_SANDBOX/out"
    exit 1
  }
  if run_check --only qml --update-baselines; then
    echo "--update-baselines accepted a new warning" >&2
    exit 1
  fi
  [[ ! -s tools/baselines/qmllint.txt ]] || {
    echo "--update-baselines added an entry" >&2
    exit 1
  }
  # A hand-added baseline entry makes it pass (Review Focus 3: moving the
  # code to another line keeps the same entry).
  grep -F 'new warning' "$ARANEA_TEST_SANDBOX/out" | sed 's/^new warning: //' >tools/baselines/qmllint.txt
  run_check --only qml || {
    cat "$ARANEA_TEST_SANDBOX/out"
    exit 1
  }
  printf 'import QtQuick\nItem {\n\n\n  property int a: undefinedName\n}\n' >plugins/q/Warn.qml
  git add -A
  run_check --only qml || {
    echo "a moved warning counted as new" >&2
    cat "$ARANEA_TEST_SANDBOX/out"
    exit 1
  }
  # Fixing it leaves a stale entry, which fails until the baseline shrinks.
  printf 'import QtQuick\nItem {\n  property int a: 1\n}\n' >plugins/q/Warn.qml
  git add -A
  if run_check --only qml; then
    echo "stale baseline entry passed" >&2
    exit 1
  fi
  run_check --only qml --update-baselines
  [[ ! -s tools/baselines/qmllint.txt ]] || {
    echo "baseline did not shrink" >&2
    exit 1
  }
  # An entry for a file that no longer exists is stale too, and a full
  # --update-baselines removes it.
  printf '1\tplugins/q/Gone.qml:unqualified:Unqualified access\n' >tools/baselines/qmllint.txt
  if run_check --only qml; then
    echo "entry of a deleted file passed" >&2
    exit 1
  fi
  run_check --only qml --update-baselines
  [[ ! -s tools/baselines/qmllint.txt ]] || {
    echo "deleted file entry kept" >&2
    exit 1
  }
  git reset -q --hard
else
  echo "SKIP: qmllint baseline cases need Omarchy's shell and Quickshell"
fi
# test: a failing node:test fails the stage; a module below its coverage
# floor fails it; --update-baselines raises floors but never lowers them.
mkdir -p tests/js plugins/cov
cat >plugins/cov/Mod.js <<'EOF'
function used() { return 1 }
function unused() { return 2 }
if (typeof module !== "undefined") module.exports = { used: used, unused: unused }
EOF
cat >tests/js/mod.test.js <<'EOF'
const { test } = require("node:test")
const assert = require("node:assert/strict")
const m = require("../../plugins/cov/Mod.js")
test("used", () => assert.equal(m.used(), 1))
EOF
git add -A
unset ARANEA_CHECK_NO_TESTS
run_check --only test || {
  echo "clean test stage failed" >&2
  cat "$ARANEA_TEST_SANDBOX/out"
  exit 1
}
printf 'plugins/cov/Mod.js 100\n' >tools/baselines/coverage.txt
if run_check --only test; then
  echo "coverage below its floor passed" >&2
  exit 1
fi
grep -Fq 'plugins/cov/Mod.js' "$ARANEA_TEST_SANDBOX/out" || {
  cat "$ARANEA_TEST_SANDBOX/out"
  exit 1
}
printf 'plugins/cov/Mod.js 10\n' >tools/baselines/coverage.txt
run_check --only test --update-baselines
[[ "$(<tools/baselines/coverage.txt)" == "plugins/cov/Mod.js 50" ]] || {
  echo "floor not raised: $(<tools/baselines/coverage.txt)" >&2
  exit 1
}
printf 'test("fails", () => assert.equal(1, 2))\n' >>tests/js/mod.test.js
git add -A
if run_check --only test; then
  echo "a failing node test passed" >&2
  exit 1
fi
git reset -q --hard
export ARANEA_CHECK_NO_TESTS=1
# smoke: without Omarchy's shell it reports SKIP (exit 0); the Arch CI job
# sets ARANEA_CHECK_REQUIRE_ALL=1, which turns that skip into a failure
# (Review Focus 5).
ARANEA_QML_SHELL_DIR=/nonexistent run_check --only smoke || {
  cat "$ARANEA_TEST_SANDBOX/out"
  exit 1
}
grep -Fq 'SKIP: runtime QML smoke needs' "$ARANEA_TEST_SANDBOX/out"
grep -Fq 'smoke: skipped' "$ARANEA_TEST_SANDBOX/out"
if ARANEA_QML_SHELL_DIR=/nonexistent ARANEA_CHECK_REQUIRE_ALL=1 run_check --only smoke; then
  echo "a required smoke stage was allowed to skip" >&2
  exit 1
fi
grep -Fq 'smoke: FAILED (skip not allowed)' "$ARANEA_TEST_SANDBOX/out"
# --fast drops the smoke stage (unless named with --only).
run_check --fast --skip format,lint,qml,test
if grep -Fq 'smoke:' "$ARANEA_TEST_SANDBOX/out"; then
  echo "--fast ran smoke" >&2
  exit 1
fi
# --- final review fixes
# Critical 1: --staged checks staged files in the context of the whole index:
# repo configs, siblings and link targets are all there.
mkdir -p docs/nested plugins/w
printf '# Nested\n\nSee the [readme](../readme.md).\n' >docs/nested/note.md
printf 'function f() {\n  return 1\n}\n\nif (typeof module !== "undefined") module.exports = { f: f }\n' >plugins/w/a.js
git add -A && git commit -qm context
printf 'More.\n' >>docs/nested/note.md
printf '// changed\n' >>plugins/w/a.js
git add -A
run_check --staged --only format,lint,validate || {
  echo "--staged lost the repo context" >&2
  cat "$ARANEA_TEST_SANDBOX/out"
  exit 1
}
git reset -q --hard HEAD~1
# Important 2: a failing git is a failure, not "no files".
if GIT_DIR=/nonexistent run_check --only validate; then
  echo "git failure passed" >&2
  exit 1
fi
# Important 3: a missing stage library fails.
mv tools/lib/check-lint.sh "$ARANEA_TEST_SANDBOX/lint.sh.away"
if run_check --only lint; then
  echo "missing stage library passed" >&2
  exit 1
fi
mv "$ARANEA_TEST_SANDBOX/lint.sh.away" tools/lib/check-lint.sh
# Important 4: bare QML is not allowed where everything is required.
mkdir -p plugins/ok && printf 'import QtQuick\nItem {}\n' >plugins/ok/Ok.qml && git add -A
if ARANEA_QML_SHELL_DIR=/nonexistent ARANEA_CHECK_REQUIRE_ALL=1 run_check --only qml; then
  echo "bare qml accepted under REQUIRE_ALL" >&2
  exit 1
fi
git reset -q --hard
# Important 8: non-ASCII file names are checked too.
printf '{"a": 1,}\n' >"docs/naïve.json"
git add -A
if run_check --only validate; then
  echo "non-ASCII file skipped" >&2
  exit 1
fi
grep -Fq 'naïve.json' "$ARANEA_TEST_SANDBOX/out"
git reset -q --hard
# The smoke stage sees a plugin that throws at load (where sway can run).
mkdir -p plugins/s
printf '{"id": "t.s", "kinds": ["service"], "entryPoints": {"service": "Bad.qml"}}\n' >plugins/s/manifest.json
printf 'import QtQuick\nItem {\n  Component.onCompleted: undefinedThing.x = 1\n}\n' >plugins/s/Bad.qml
git add -A
if run_check --only smoke; then
  if grep -Fq 'smoke: skipped' "$ARANEA_TEST_SANDBOX/out"; then
    echo "SKIP: smoke sensitivity (no quickshell/sway/Omarchy here)"
  else
    echo "smoke missed a runtime error" >&2
    cat "$ARANEA_TEST_SANDBOX/out"
    exit 1
  fi
elif grep -Fq 'smoke harness did not run' "$ARANEA_TEST_SANDBOX/out"; then
  echo "SKIP: smoke sensitivity (the headless compositor cannot run here)"
else
  grep -Fq 'new runtime problem' "$ARANEA_TEST_SANDBOX/out" || {
    cat "$ARANEA_TEST_SANDBOX/out"
    exit 1
  }
fi
git reset -q --hard
# docs: undocumented code fails, documented code passes.
mkdir -p plugins/d scripts
cat >plugins/d/Logic.js <<'EOF'
// Scratch logic module.

/**
 * Adds two numbers.
 * @param {number} a - first
 * @param {number} b - second
 * @returns {number} the sum
 */
function add(a, b) {
  return a + b
}

if (typeof module !== "undefined") module.exports = { add: add }
EOF
cat >plugins/d/View.qml <<'EOF'
// Scratch view.
import QtQuick

Item {
  // The label text; braces in "{strings}" and // comments { do not count.
  property string label: "{"
  property int _internal: 0

  // Emitted when picked.
  signal picked

  // Clears the label.
  function clear() {
    label = ""
  }
}
EOF
cat >scripts/tool <<'EOF'
#!/usr/bin/env bash
# Scratch tool: prints hello.
# Usage: scripts/tool
set -euo pipefail

# Prints the greeting.
greet() {
  cat >"$1" <<'STUB'
undocumented_inside_heredoc() { :; }
STUB
  echo hello
}
greet /dev/null
EOF
chmod +x scripts/tool
git add -A
run_check --only docs || {
  cat "$ARANEA_TEST_SANDBOX/out" >&2
  exit 1
}
git commit -qm "documented fixtures"
# Each planted gap fails with its own message.
plant_docs() { # file content expected
  printf '%s' "$2" >"$1"
  git add -A
  if run_check --only docs; then
    echo "docs passed: $3" >&2
    exit 1
  fi
  grep -Fq "$3" "$ARANEA_TEST_SANDBOX/out" || {
    cat "$ARANEA_TEST_SANDBOX/out" >&2
    exit 1
  }
  git reset -q --hard
}
plant_docs plugins/d/Bare.js $'// h\nfunction f(a) {\n  return a\n}\nif (typeof module !== "undefined") module.exports = { f: f }\n' 'Missing JSDoc'
plant_docs plugins/d/Name.js $'// h\n/**\n * F.\n * @param {number} b - x\n * @returns {number} y\n */\nfunction f(a) {\n  return a\n}\nif (typeof module !== "undefined") module.exports = { f: f }\n' 'check-param-names'
plant_docs plugins/d/Type.js $'// h\n/**\n * F.\n * @param {number} a - x\n * @returns {number} y\n */\nfunction f(a) {\n  return a.toUpperCase()\n}\nif (typeof module !== "undefined") module.exports = { f: f }\n' 'toUpperCase'
plant_docs scripts/nohead $'#!/usr/bin/env bash\nset -euo pipefail\necho x\n' 'scripts/nohead:3: missing header comment'
plant_docs scripts/fn $'#!/usr/bin/env bash\n# Tool.\n# Usage: scripts/fn\nhelper() {\n  :\n}\n' 'scripts/fn:4: missing comment for function helper'
plant_docs plugins/d/NoHead.qml $'import QtQuick\nItem {}\n' 'plugins/d/NoHead.qml:1: missing header comment'
plant_docs plugins/d/Prop.qml $'// h\nimport QtQuick\nItem {\n  property int count: 0\n}\n' 'plugins/d/Prop.qml:4: missing comment for property count'
plant_docs plugins/d/Gap.qml $'// h\nimport QtQuick\nItem {\n  // Count.\n\n  property int count: 0\n}\n' 'plugins/d/Gap.qml:6: missing comment for property count'
# docs, final review: parse failures are loud, never silent.
plant_docs scripts/digits $'#!/usr/bin/env bash\n# Tool.\n# Usage: scripts/digits\ncat <<EOF2\ndata\nEOF2\nundoc() {\n  :\n}\n' 'scripts/digits:7: missing comment for function undoc'
plant_docs scripts/arith $'#!/usr/bin/env bash\n# Tool.\n# Usage: scripts/arith\necho $((1<<2))\n# cat <<EOF\necho "a << b"\nundoc() {\n  :\n}\n' 'scripts/arith:7: missing comment for function undoc'
plant_docs scripts/open $'#!/usr/bin/env bash\n# Tool.\n# Usage: scripts/open\ncat <<EOF\nnever closed\n' 'unterminated heredoc'
plant_docs scripts/kw $'#!/usr/bin/env bash\n# Tool.\n# Usage: scripts/kw\nfunction helper {\n  :\n}\n' 'scripts/kw:4: missing comment for function helper'
printf '#!/usr/bin/env bash\n# Tool without usage.\necho x\n' >scripts/nousage && chmod +x scripts/nousage && git add -A
if run_check --only docs; then
  echo "missing Usage passed" >&2
  exit 1
fi
grep -Fq 'Usage: line in the header' "$ARANEA_TEST_SANDBOX/out" || {
  cat "$ARANEA_TEST_SANDBOX/out" >&2
  exit 1
}
git reset -q --hard
# A shellcheck directive before the header is not the header.
printf '#!/usr/bin/env bash\n# shellcheck shell=bash\n# Tool.\n# Usage: scripts/sc\necho x\n' >scripts/sc && chmod +x scripts/sc && git add -A
run_check --only docs || {
  echo "shellcheck-first header rejected" >&2
  cat "$ARANEA_TEST_SANDBOX/out" >&2
  exit 1
}
git reset -q --hard
plant_docs plugins/d/Block.qml $'// h\nimport QtQuick\nItem {\n  /* { */\n\n  property int count: 0\n}\n' 'plugins/d/Block.qml:6: missing comment for property count'
plant_docs plugins/d/Trail.qml $'// h\nimport QtQuick\nItem {\n  // A.\n  property int a: 0 /* x */\n  property int b: 0\n}\n' 'plugins/d/Trail.qml:6: missing comment for property b'
plant_docs plugins/d/Same.qml $'// h\nimport QtQuick\nItem { property int a: 0\n}\n' 'plugins/d/Same.qml:3: missing comment for property a'
# --- 4d: --only / --skip without a value print the usage and exit 2
rc=0
out="$("$repo_root/tools/check" --only 2>&1)" || rc=$?
[[ $rc -eq 2 ]] || exit 1
grep -Fq 'Usage:' <<<"$out"
rc=0
out="$("$repo_root/tools/check" --skip 2>&1)" || rc=$?
[[ $rc -eq 2 ]] || exit 1
grep -Fq 'Usage:' <<<"$out"

# --- 4f: the qmltest stage runs the offscreen QML behaviour tests
mkdir -p tests/lib tests/qml/lib
cp "$repo_root/tests/qml-behaviour.test.sh" tests/
cp "$repo_root"/tests/lib/*.sh tests/lib/
cp "$repo_root"/tests/qml/lib/* tests/qml/lib/
cp -r "$repo_root/tests/guard-bin" tests/
printf '// Always fails.\nimport QtQuick\nimport Quickshell\nimport "lib"\nShellRoot {\n  QmlTest {\n    id: t\n    Component.onCompleted: {\n      t.check(false, "planted")\n      t.done()\n    }\n  }\n}\n' >tests/qml/fail.qml
git add -A
if ARANEA_QML_SHELL_DIR=/nonexistent run_check --only qmltest; then
  grep -Fq 'qmltest: skipped' "$ARANEA_TEST_SANDBOX/out"
else
  echo "qmltest must skip without the Omarchy shell" >&2
  exit 1
fi
if ARANEA_QML_SHELL_DIR=/nonexistent ARANEA_CHECK_REQUIRE_ALL=1 run_check --only qmltest; then
  echo "a required qmltest stage was allowed to skip" >&2
  exit 1
fi
if command -v quickshell >/dev/null && [[ -d /usr/share/omarchy/shell/Commons ]]; then
  if run_check --only qmltest; then
    echo "qmltest missed a failing check" >&2
    exit 1
  fi
  grep -Fq 'QMLTEST FAIL planted' "$ARANEA_TEST_SANDBOX/out"
  printf 'import QtQuick\nShellRoot {\n  this is not qml\n}\n' >tests/qml/fail.qml
  git add -A
  if run_check --only qmltest; then
    echo "qmltest passed a test that does not load" >&2
    exit 1
  fi
  grep -Fq 'did not load' "$ARANEA_TEST_SANDBOX/out"
else
  echo "SKIP: qmltest sensitivity (no quickshell or Omarchy shell here)"
fi
git reset -q --hard
git clean -qfd tests

echo "check contract passed"
