#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
command -v shellcheck >/dev/null 2>&1 || {
  echo "shellcheck unavailable; skipped"
  exit 0
}
# CI installs the version pinned in tools/install-shellcheck; a different
# local version can disagree with CI, so say so instead of drifting silently.
pinned="$(sed -n 's/^version="\(.*\)"$/\1/p' "$repo_root/tools/install-shellcheck")"
local_version="$(shellcheck --version | sed -n 's/^version: //p')"
if [[ -z "$pinned" || "$local_version" != "$pinned" ]]; then
  echo "shellcheck $local_version differs from the CI pin (${pinned:-missing}); update tools/install-shellcheck or your local shellcheck" >&2
  exit 1
fi
grep -Fq 'tools/install-shellcheck' "$repo_root/.github/workflows/ci.yml"
grep -Fq 'tools/install-shellcheck' "$repo_root/.github/workflows/release-please.yml"

# Same scope and flags as CI (.github/workflows/ci.yml): every shell script.
cd "$repo_root"
find scripts hooks tests tools .githooks -type f -print0 2>/dev/null |
  xargs -0 grep -lI '^#!.*sh' |
  xargs -r shellcheck -x
echo "shellcheck contract passed"
