// A row going away under a shown outline hides the outline (rule 1: the
// outline marks what Enter acts on, so it never stays on a row Enter would
// refuse). Each scenario walks the host's own steps with the shared logic
// (CursorLogic.followShown, pressIntent, cursorConfirmed and Network's
// revealTarget/pressOutcome): the row drops, so no outline; Enter reveals;
// the next Enter acts. The hosts' wiring is checked in their source.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { test } = require("node:test")

const root = path.join(__dirname, "..", "..")
const cursor = require(path.join(root, "plugins/araneadev.shared/CursorLogic.js"))
const network = require(path.join(root, "plugins/araneadev.network/NetworkLogic.js"))

/**
 * Reads a plugin file from the repository.
 * @param {string} relative - the path under plugins/
 * @returns {string} the file's text
 */
function source(relative) {
  return fs.readFileSync(path.join(root, "plugins", relative), "utf8")
}

/**
 * The host steps shared by VPN, Power and Displays: a shown outline on
 * KEY at INDEX; ROWS change; then Enter twice (reveal, then act on the
 * revealed row, as their revealCursor confirms it).
 * @param {Array<{key: string}>} before - the rows the outline was shown on
 * @param {Array<{key: string}>} after - the rows after the change
 * @param {string} key - the outlined row's key
 * @param {number} index - its index before
 * @returns {Array<string>} what each step saw: the outline, then the two Enters
 */
function dropThenEnterTwice(before, after, key, index) {
  assert.equal(cursor.cursorConfirmed(before, key, index), true)
  const next = cursor.followShown(after, key, index, true)
  const seen = [next.keyboard ? "outline" : "no outline"]
  let keyboard = next.keyboard
  let chosen = next.key
  // Enter 1: a hidden cursor only reveals, adopting the row it now shows.
  if (cursor.pressIntent(true, keyboard) === "reveal") {
    keyboard = true
    chosen = after[Math.max(0, next.index)].key
    seen.push("revealed " + chosen)
  }
  // Enter 2: acts on the outlined row.
  seen.push(
    cursor.pressIntent(true, keyboard) === "act" &&
      cursor.cursorConfirmed(after, chosen, Math.max(0, next.index))
      ? "acts on " + chosen
      : "refused"
  )
  return seen
}

test("VPN: a connection vanishing under the outline hides it; Enter reveals, Enter acts", () => {
  const before = [{ key: "office" }, { key: "azure" }, { key: "home" }]
  const after = [{ key: "office" }, { key: "home" }]
  assert.deepEqual(dropThenEnterTwice(before, after, "azure", 1), [
    "no outline",
    "revealed home",
    "acts on home"
  ])
  const panel = source("araneadev.vpn/Panel.qml")
  assert.match(panel, /CursorLogic\.followShown\(flatRows, cursorKey, cursorFlat, keyboardCursor\)/)
  assert.match(panel, /keyboardCursor = next\.keyboard/)
})

test("Power: a profile vanishing under the outline hides it; Enter reveals, Enter acts", () => {
  const before = [{ key: "power-saver" }, { key: "balanced" }, { key: "performance" }]
  const after = [{ key: "power-saver" }, { key: "balanced" }]
  assert.deepEqual(dropThenEnterTwice(before, after, "performance", 2), [
    "no outline",
    "revealed balanced",
    "acts on balanced"
  ])
  const panel = source("araneadev.power/Panel.qml")
  assert.match(
    panel,
    /CursorLogic\.followShown\(profileKeyRows\(\), profileKey, profileIndex, keyboardCursor\)/
  )
  assert.match(panel, /keyboardCursor = next\.keyboard/)
})

test("Displays: a display vanishing, or its section hiding, under the outline hides it", () => {
  const before = [{ key: "eDP-1" }, { key: "DP-2" }]
  const after = [{ key: "eDP-1" }]
  assert.deepEqual(dropThenEnterTwice(before, after, "DP-2", 1), [
    "no outline",
    "revealed eDP-1",
    "acts on eDP-1"
  ])
  const panel = source("araneadev.monitor/Panel.qml")
  assert.match(panel, /CursorLogic\.followShown\(rows, cursorKey, selectedIndex, keyboardCursor\)/)
  const hidden = panel.slice(
    panel.indexOf("function clampCursor()"),
    panel.indexOf("var rows = sectionRows(focusSection)")
  )
  assert.match(
    hidden,
    /cursorKey = ""\s+keyboardCursor = false/,
    "a hiding section drops the outline"
  )
})

test("Network: a Wi-Fi row vanishing under the outline hides it; joining still takes two Enters", () => {
  const before = [{ key: "Home" }, { key: "Cafe" }, { key: "Stranger" }]
  const after = [{ key: "Home" }, { key: "Stranger" }]
  assert.equal(cursor.cursorConfirmed(before, "Cafe", 1), true)
  const next = cursor.followShown(after, "Cafe", 1, true)
  assert.equal(next.keyboard, false, "no outline on the row that slid in")
  const target = { section: "wifi", chosen: "wifi", rows: after, key: next.key, index: next.index }
  // Enter 1 only reveals (the host applies revealTarget)...
  assert.equal(network.pressOutcome(target, true, next.keyboard), "reveal")
  const revealed = network.revealTarget(target)
  assert.equal(revealed.key, "Stranger")
  // ...and only Enter 2, on the visible outline, joins.
  assert.equal(network.pressOutcome(revealed, true, true), "act")
  const panel = source("araneadev.network/Panel.qml")
  assert.match(
    panel,
    /CursorLogic\.followShown\(root\.wifiKeyRows\(\), key, root\.selectedIndex, root\.keyboardCursor\)/
  )
  assert.match(panel, /CursorLogic\.followShown\(root\.savedRows, root\.savedCursorKey/)
  assert.match(panel, /CursorLogic\.followShown\(headerKeyRows\(\), headerCursorKey/)
  assert.match(panel, /cursorChosenSection === "wifi"\)\s+root\.keyboardCursor = false/)
})
