#!/usr/bin/env bash
# test stage for tools/check: the sandboxed bash contract tests (tests/run)
# and the node:test logic suites (tests/js), with per-module function
# coverage floors from tools/baselines/coverage.txt ("path percent" lines)
# that can only rise. --fast skips the slow bash tests.
check_root="${check_root:?tools/check sets check_root}"
repo_root="${repo_root:?tools/check sets repo_root}"
update_baselines="${update_baselines:-0}"
fast="${fast:-0}"
staged="${staged:-0}"

# Prints "path percent" (function coverage, rounded down) per plugin module
# from an lcov file.
coverage_by_module() {
  awk -F: '
    /^SF:/ { file = $2 }
    /^FNF:/ { found = $2 }
    /^FNH:/ { if (file ~ /^plugins\//) printf "%s %d\n", file, (found > 0 ? int(100 * $2 / found) : 100) }
  ' "$1" | LC_ALL=C sort
}

# Compares CURRENT coverage with the FLOORS file; prints each module below
# its floor or missing. Returns 1 when there is any.
coverage_compare() {
  awk '
    FILENAME == ARGV[1] { floor[$1] = $2; next }
    { cur[$1] = $2 }
    END {
      bad = 0
      for (m in floor) {
        if (!(m in cur)) { print "coverage: " m " is no longer tested (floor " floor[m] "%)"; bad = 1 }
        else if (cur[m] + 0 < floor[m] + 0) { print "coverage: " m " " cur[m] "% is below its floor " floor[m] "%"; bad = 1 }
      }
      exit bad
    }' "$2" "$1"
}

# Prints the floors raised to CURRENT (never lowered); modules without a
# floor get one.
coverage_raised() {
  awk '
    FILENAME == ARGV[1] { floor[$1] = $2; next }
    {
      m = $1
      n = $2
      if ((m in floor) && floor[m] + 0 > n + 0) n = floor[m]
      seen[m] = 1
      print m, n
    }
    END { for (m in floor) if (!(m in seen)) print m, floor[m] }' "$2" "$1" | LC_ALL=C sort
}

# test stage entry point.
stage_test() {
  local status=0
  # With --staged, tests run only when something they cover is staged.
  if ((staged)) && ! check_files '^(tests|scripts|hooks|tools)/' '\.(js|qml|sh)$' '^package(-lock)?\.json$' | grep -q .; then
    echo "no tests, scripts or plugin code staged"
    note_stage "nothing to test"
    return 0
  fi
  command -v node >/dev/null || {
    echo "node is required (see .nvmrc)"
    return 1
  }
  if [[ "${ARANEA_CHECK_NO_TESTS:-0}" != 1 && -x "$check_root/tests/run" ]]; then
    # js, qml-types and qml-behaviour duplicate this stage's node run and the
    # qml and qmltest stages.
    local skip_list="js,qml-types,qml-behaviour"
    ((fast)) && skip_list="js,qml-types,qml-behaviour,hooks,screenshot-coverage,capture-batch"
    (cd "$check_root" && ARANEA_TESTS_SKIP="$skip_list" tests/run) || status=1
  fi
  if [[ -d "$check_root/tests/js" ]]; then
    local lcov floors="$repo_root/tools/baselines/coverage.txt" current
    lcov="$(mktemp)"
    current="$(mktemp)"
    (cd "$check_root" && node --test --test-concurrency=1 --experimental-test-coverage \
      --test-reporter=spec --test-reporter-destination=stdout \
      --test-reporter=lcov --test-reporter-destination="$lcov" tests/js/) || status=1
    coverage_by_module "$lcov" >"$current"
    touch "$floors"
    if ((update_baselines)); then
      coverage_raised "$current" "$floors" >"$floors.new"
      mv "$floors.new" "$floors"
    fi
    coverage_compare "$current" "$floors" || status=1
    rm -f "$lcov" "$current"
  fi
  return "$status"
}
