#!/usr/bin/env bash
# qmltest stage for tools/check: the offscreen QML behaviour tests
# (tests/qml-behaviour.test.sh). Skipped without quickshell or the Omarchy
# shell; ARANEA_CHECK_REQUIRE_ALL=1 turns that skip into a failure.
check_root="${check_root:?tools/check sets check_root}"

# qmltest stage entry point.
stage_qmltest() {
  local out status=0
  if [[ ! -x "$check_root/tests/qml-behaviour.test.sh" ]]; then
    note_stage "no QML behaviour tests"
    return 0
  fi
  out="$(cd "$check_root" && ARANEA_CHECK_REQUIRE_ALL=0 tests/qml-behaviour.test.sh 2>&1)" || status=$?
  printf '%s\n' "$out"
  if grep -q '^SKIP:' <<<"$out"; then
    note_stage "no quickshell or Omarchy shell"
    return 77
  fi
  return "$status"
}
