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
printf '{"ok": true}\n' > data.json
printf 'a = 1\n' > conf.toml
printf '# Title\n\nSee [data](../data.json).\n' > docs/readme.md
git add -A && git commit -qm init

run_check() { ARANEA_CHECK_NO_TESTS=1 tools/check "$@" >"$ARANEA_TEST_SANDBOX/out" 2>&1; }

# Clean tree passes the validate stage.
run_check --only validate || { cat "$ARANEA_TEST_SANDBOX/out"; exit 1; }

# Each planted problem fails validate with its own message (Review Focus 1).
plant() { # file content expected-message
  printf '%s' "$2" > "$1"; git add -A
  if run_check --only validate; then echo "validate passed with a bad $1" >&2; exit 1; fi
  grep -Fq "$3" "$ARANEA_TEST_SANDBOX/out" || { cat "$ARANEA_TEST_SANDBOX/out"; exit 1; }
  git checkout -q -- . 2>/dev/null || true; git reset -q --hard
}
plant data.json '{"ok": }' 'data.json'
plant conf.toml 'a = = 1' 'conf.toml'
plant docs/readme.md $'# Title\n\nSee [gone](missing.md).\n' 'missing.md'
plant docs/dash.md $'# A \xe2\x80\x94 B\n' 'em dash'

# --staged reads the index, not the working tree (Review Focus 2).
printf '{"ok": }' > data.json && git add data.json && printf '{"ok": true}\n' > data.json
if run_check --staged --only validate; then echo "--staged checked the working tree" >&2; exit 1; fi
git reset -q --hard

# A stage whose tool crashes fails (not passes).
fake="$ARANEA_TEST_SANDBOX/fake-bin"; mkdir -p "$fake"
printf '#!/usr/bin/env bash\nexit 99\n' > "$fake/jq"; chmod +x "$fake/jq"
if PATH="$fake:$PATH" run_check --only validate; then echo "crashing jq passed" >&2; exit 1; fi

# Unknown stage and unknown option are usage errors.
if tools/check --only nope >/dev/null 2>&1; then exit 1; fi
if tools/check --bogus >/dev/null 2>&1; then exit 1; fi

echo "check contract passed"
