#!/usr/bin/env node
// Regenerates the QML-compatible JavaScript facade regions from focused source modules.
import fs from "node:fs"
import path from "node:path"

const root = process.cwd()

const specs = [
  ["plugins/araneadev.audio/AudioBridge.js", "plugins/araneadev.shared/ServiceRegistry.js"],
  ["plugins/araneadev.menu/DesktopSearchLogic.js", "plugins/araneadev.menu/MenuSearch.js"],
  [
    "plugins/araneadev.menu/DesktopSearchLogic.js",
    "plugins/araneadev.menu/DesktopSearchRanking.js"
  ],
  ["plugins/araneadev.menu/MenuModel.js", "plugins/araneadev.menu/MenuPresentation.js"],
  ["plugins/araneadev.menu/MenuModel.js", "plugins/araneadev.menu/MenuSearch.js"],
  ["plugins/araneadev.menu/MenuModel.js", "plugins/araneadev.menu/MenuTree.js"],
  ["plugins/araneadev.menu/MenuModel.js", "plugins/araneadev.menu/MenuAppRows.js"],
  ["plugins/araneadev.menu/MenuModel.js", "plugins/araneadev.menu/MenuItemParsing.js"],
  ["plugins/araneadev.menu/MenuModel.js", "plugins/araneadev.menu/MenuGuardScript.js"],
  [
    "plugins/araneadev.clipboard/ClipboardLogic.js",
    "plugins/araneadev.clipboard/ClipboardPresentation.js"
  ],
  [
    "plugins/araneadev.clipboard/ClipboardLogic.js",
    "plugins/araneadev.clipboard/ClipboardNormalization.js"
  ],
  ["plugins/araneadev.health/HealthLogic.js", "plugins/araneadev.health/HealthPresentation.js"],
  [
    "plugins/araneadev.notifications/NotificationLogic.js",
    "plugins/araneadev.notifications/NotificationPresentation.js"
  ],
  [
    "plugins/araneadev.notifications/NotificationLogic.js",
    "plugins/araneadev.notifications/NotificationSettings.js"
  ],
  ["plugins/araneadev.health/HealthBridge.js", "plugins/araneadev.shared/ServiceRegistry.js"],
  [
    "plugins/araneadev.notifications/ServiceBridge.js",
    "plugins/araneadev.shared/ServiceRegistry.js"
  ],
  ["plugins/araneadev.network/NetworkLogic.js", "plugins/araneadev.shared/CursorLogic.js"],
  ["plugins/araneadev.network/NetworkLogic.js", "plugins/araneadev.shared/NmcliTerse.js"],
  ["plugins/araneadev.notifications/InboxLogic.js", "plugins/araneadev.shared/CursorLogic.js"],
  ["plugins/araneadev.bluetooth/BluetoothLogic.js", "plugins/araneadev.shared/CursorLogic.js"],
  ["plugins/araneadev.health/HealthLogic.js", "plugins/araneadev.shared/CursorLogic.js"],
  ["plugins/araneadev.workspaces/WorkspaceModel.js", "plugins/araneadev.shared/CursorLogic.js"],
  ["plugins/araneadev.vpn/VpnLogic.js", "plugins/araneadev.shared/NmcliTerse.js"]
]

/** Returns the source region marker used by each facade. */
function marker(target, source) {
  return `/* @aranea-facade-start: ${source} */`
}

/** Reads a focused source module and wraps it as a generated facade region. */
function generatedRegion(target, source) {
  const sourceText = fs
    .readFileSync(path.join(root, source), "utf8")
    .replace(/^\/\*\* @typedef .* (?:MenuItem|ItemMap|ClipboardEntry) \*\/\n/gm, "")
    .trim()
  return `${marker(target, source)}\n${sourceText}\n/* @aranea-facade-end */`
}

/** Replaces one marked facade region with its canonical source. */
function render(target, source) {
  const file = path.join(root, target)
  const input = fs.readFileSync(file, "utf8")
  const start = marker(target, source)
  const begin = input.indexOf(start)
  if (begin < 0) throw new Error(`${target}: missing facade start marker for ${source}`)
  const endMarker = "/* @aranea-facade-end */"
  const end = input.indexOf(endMarker, begin)
  if (end < 0) throw new Error(`${target}: missing facade end marker for ${source}`)
  const before = input.slice(0, begin)
  const after = input.slice(end + endMarker.length)
  return before + generatedRegion(target, source) + after
}

/** Writes generated facades or checks that their regions are current. */
function main() {
  const write = process.argv.includes("--write")
  const check = process.argv.includes("--check")
  if (!write && !check) throw new Error("Usage: tools/js-facade-generator.mjs --write|--check")
  let changed = false
  for (const [target, source] of specs) {
    const file = path.join(root, target)
    const before = fs.readFileSync(file, "utf8")
    const after = render(target, source)
    if (before === after) continue
    changed = true
    if (write) fs.writeFileSync(file, after)
    else console.error(`${target}: generated facade is stale`)
  }
  if (check && changed) process.exitCode = 1
}

main()
