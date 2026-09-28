#!/usr/bin/env bash
# Assertion helpers for the bash contract tests. Sourced after
# tests/lib/sandbox.sh.

# code_grep FILE TEXT: true when TEXT appears in FILE outside whole-line
# comments (// or #), so a commented-out line never satisfies a contract.
code_grep() {
  sed -E '/^[[:space:]]*(\/\/|#)/d' "$1" | grep -Fq -- "$2"
}

# block_grep FILE START TEXT: true when TEXT appears within the 15 lines that
# follow the first line containing START (e.g. an object's "id: card").
block_grep() {
  grep -F -A15 -- "$2" "$1" | sed -E '/^[[:space:]]*(\/\/|#)/d' | grep -Fq -- "$3"
}

# skip REASON: reports a skipped check (never skip silently).
skip() {
  printf 'SKIP: %s\n' "$1"
}
