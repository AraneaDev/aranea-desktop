#!/usr/bin/env bash
# Source assertions consume their pipelines under pipefail, including large matches.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/assert.sh"
fixture="$TMPDIR/source"
awk 'BEGIN { print "needle"; for (i=0; i<20000; i++) print "a long source body that must be consumed after the first matching line" }' >"$fixture"
code_grep "$fixture" needle
printf '# comment-only\n// comment-only\nreal code\n' >"$fixture"
if code_grep "$fixture" comment-only; then
  echo 'comment-only source was accepted' >&2
  exit 1
fi
if code_grep "$fixture" missing; then
  echo 'missing source was accepted' >&2
  exit 1
fi
awk 'BEGIN { print "start needle"; for(i=0; i<15; i++) { for(j=0;j<4096;j++) printf "body "; print "" } }' >"$fixture"
block_grep "$fixture" start needle
if block_grep "$fixture" start missing; then
  echo 'missing block source was accepted' >&2
  exit 1
fi
echo 'source assertion pipelines passed'
