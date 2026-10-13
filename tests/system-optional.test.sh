#!/usr/bin/env bash
# Run production Power with Display, Health, or both physically absent.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
for missing in monitor health both; do
  fixture_root="$ARANEA_TEST_SANDBOX/$missing"
  mkdir -p "$fixture_root/plugins" "$fixture_root/tests/qml"
  ln -s "$repo_root/tests/lib" "$fixture_root/tests/lib"
  ln -s "$repo_root/tests/qml/lib" "$fixture_root/tests/qml/lib"
  ln -s "$repo_root/tests/qml/fixtures" "$fixture_root/tests/qml/fixtures"
  python - "$repo_root/tests/qml/fixtures/system-optional.qml" "$fixture_root/tests/qml/system-optional.qml" "$missing" <<'PYFIXTURE'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
if sys.argv[3] in ('monitor', 'both'):
    source = source.replace('property bool expectDisplay: true', 'property bool expectDisplay: false')
if sys.argv[3] in ('health', 'both'):
    source = source.replace('property bool expectHealth: true', 'property bool expectHealth: false')
pathlib.Path(sys.argv[2]).write_text(source)
PYFIXTURE
  for plugin in "$repo_root"/plugins/araneadev.*; do
    name="${plugin##*/}"
    if [[ "$name" == araneadev.monitor && ("$missing" == monitor || "$missing" == both) ]] ||
      [[ "$name" == araneadev.health && ("$missing" == health || "$missing" == both) ]]; then
      continue
    fi
    ln -s "$plugin" "$fixture_root/plugins/$name"
  done
  python - "$repo_root/tests/qml-behaviour.test.sh" "$fixture_root/runner.sh" "$fixture_root" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
source = source.replace('repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"', 'repo_root="' + sys.argv[3] + '"')
source = source.replace('"$name" == system-embedded', '"$name" == system-embedded || "$name" == system-optional')
pathlib.Path(sys.argv[2]).write_text(source)
PY
  bash "$fixture_root/runner.sh" system-optional
  echo "system optional: $missing absent passed"
done
