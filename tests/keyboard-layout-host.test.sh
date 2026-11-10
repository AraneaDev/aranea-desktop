#!/usr/bin/env bash
# Aranea consumes this keyboard widget from the host; it has no copied filter.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/qml-host.sh"
require_qml_host
node - "$qml_shell_dir/plugins/bar/widgets/KeyboardLayoutModel.js" <<'JS'
const assert = require("node:assert/strict")
const keyboard = require(process.argv[2])
for (const name of ["asus-wmi-hotkeys", "asus-wmi-hotkeys-2", "asus-wireless-radio-control", "asus-wireless-radio-control-12", "power-button", "hl-virtual-keyboard-1"]) {
  assert.equal(keyboard.isTypedKeyboard(name), false, name)
  assert.equal(keyboard.eventKeyboardName({data: name + ",English (US)"}), "", name + " event")
}
for (const name of ["at-translated-set-2-keyboard", "keychron-keychron-k2", "logitech-usb-keyboard", "asus-keyboard", "my-wmi-hotkeys-keyboard"]) {
  assert.equal(keyboard.isTypedKeyboard(name), true, name)
  assert.equal(keyboard.eventKeyboardName({data: name + ",English (US)"}), name, name + " event")
}
console.log("PASS: host keyboard filter keeps typing devices and excludes vendor hotkey devices (22 checks)")
JS
