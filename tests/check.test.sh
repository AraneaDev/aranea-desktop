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
cp "$repo_root/tools/baselines/em-dash-allow.txt" tools/baselines/
: >tools/baselines/qmllint.txt
: >tools/baselines/coverage.txt
for config in .prettierrc.json .prettierignore .editorconfig .qmlformat.ini eslint.config.js .markdownlint-cli2.jsonc; do cp "$repo_root/$config" .; done
export ARANEA_CHECK_NODE_MODULES="$repo_root/node_modules"
ln -s "$repo_root/node_modules" node_modules # the configs resolve their plugins from here
printf 'node_modules\n' >.gitignore
printf '{"ok": true}\n' >data.json
printf 'a = 1\n' >conf.toml
printf '# Title\n\nSee [data](../data.json).\n' >docs/readme.md
git add -A && git commit -qm init

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
echo "check contract passed"
