#!/usr/bin/env bash
# Exercise the real QML calendar in a zone whose DST skips local midnight.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

for zone in America/Santiago America/Havana; do
  ARANEA_QML_SHELL_DIR="$(sandbox_inherited_value ARANEA_QML_SHELL_DIR)" \
  ARANEA_CHECK_REQUIRE_ALL="$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)" \
  TZ="$zone" "$repo_root/tests/qml-behaviour.test.sh" clock-civil-dates
done
