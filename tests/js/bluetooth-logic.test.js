// Logic contract for the Aranea Bluetooth dropdown (BluetoothLogic.js).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(
  path.join(__dirname, "..", "..", "plugins/araneadev.bluetooth/BluetoothLogic.js")
)
const g = (cp) => String.fromCodePoint(cp)

test("device types map to their glyphs", () => {
  assert.equal(logic.deviceGlyph("audio-headset", false), g(0xf02cb))
  assert.equal(logic.deviceGlyph("audio-headphones", true), g(0xf02cb))
  assert.equal(logic.deviceGlyph("audio-card", false), g(0xf04c3))
  assert.equal(logic.deviceGlyph("input-mouse", false), g(0xf037d))
  assert.equal(logic.deviceGlyph("input-keyboard", false), g(0xf030c))
  assert.equal(logic.deviceGlyph("input-gaming", false), g(0xf0297))
  assert.equal(logic.deviceGlyph("phone", false), g(0xf03f2))
  assert.equal(logic.deviceGlyph("computer", false), g(0xf07c0))
})

test("unknown types fall back to the Bluetooth glyph, connected or not", () => {
  assert.equal(logic.deviceGlyph("", false), g(0xf00af))
  assert.equal(logic.deviceGlyph(undefined, true), g(0xf00b1))
  assert.equal(logic.deviceGlyph("printer", false), g(0xf00af))
})

test("signal strength has three levels and none", () => {
  assert.equal(logic.signalLevel(-50), 3)
  assert.equal(logic.signalLevel(-60), 3)
  assert.equal(logic.signalLevel(-61), 2)
  assert.equal(logic.signalLevel(-75), 2)
  assert.equal(logic.signalLevel(-76), 1)
  assert.equal(logic.signalLevel(-90), 1)
  assert.equal(logic.signalLevel(-91), 0)
  assert.equal(logic.signalLevel(undefined), 0)
  assert.equal(logic.signalLevel(NaN), 0)
})

const managed = JSON.stringify({
  type: "a{oa{sa{sv}}}",
  data: [
    {
      "/org/bluez/hci0": {
        "org.bluez.Adapter1": { Address: { type: "s", data: "3C:95:09:5C:CE:70" } }
      },
      "/org/bluez/hci0/dev_AA_BB": {
        "org.bluez.Device1": {
          Address: { type: "s", data: "aa:bb:cc:dd:ee:ff" },
          RSSI: { type: "n", data: -63 }
        }
      },
      "/org/bluez/hci0/dev_11_22": {
        "org.bluez.Device1": { Address: { type: "s", data: "11:22:33:44:55:66" } }
      }
    }
  ]
})

test("RSSI is read per device address from BlueZ's managed objects", () => {
  assert.deepEqual(logic.parseRssi(managed), { "AA:BB:CC:DD:EE:FF": -63 })
})

test("bad or empty poll output gives no readings", () => {
  assert.deepEqual(logic.parseRssi(""), {})
  assert.deepEqual(logic.parseRssi("not json"), {})
  assert.deepEqual(logic.parseRssi('{"data":[]}'), {})
  assert.deepEqual(logic.parseRssi(undefined), {})
})

test("the empty text follows the adapter first, as stock's does", () => {
  assert.equal(logic.emptyText(false, false, false), "No Bluetooth adapter")
  assert.equal(logic.emptyText(false, false, true), "No Bluetooth adapter")
  assert.equal(logic.emptyText(true, false, false), "Turn Bluetooth on to scan")
  assert.equal(logic.emptyText(true, true, false), "Scanning for devices…")
  assert.equal(logic.emptyText(true, false, true), "")
  assert.equal(logic.emptyText(true, true, true), "")
})

test("RSSI readings count as changed only when a value or address differs", () => {
  assert.equal(logic.rssiChanged({ A: -50 }, { A: -50 }), false)
  assert.equal(logic.rssiChanged({}, {}), false)
  assert.equal(logic.rssiChanged({ A: -50 }, { A: -51 }), true)
  assert.equal(logic.rssiChanged({ A: -50 }, { A: -50, B: -70 }), true)
  assert.equal(logic.rssiChanged({ A: -50, B: -70 }, { A: -50 }), true)
  assert.equal(logic.rssiChanged(undefined, {}), false)
  assert.equal(logic.rssiChanged({}, undefined), false)
})

// --- Power switch: pending, echo, queue ------------------------------------

test("power: a click shows the new state at once and pulses until the echo", () => {
  const idle = logic.powerIdle()
  assert.deepEqual(idle, { target: null, queued: null })
  assert.deepEqual(logic.powerView(idle, false), { on: false, busy: false })
  assert.deepEqual(logic.powerView(null, true), { on: true, busy: false })

  let r = logic.powerClick(idle, false)
  assert.equal(r.send, true)
  assert.deepEqual(r.state, { target: true, queued: null })
  assert.deepEqual(logic.powerView(r.state, false), { on: true, busy: true })

  // An echo of the old state keeps waiting; the target's echo settles.
  assert.deepEqual(logic.powerEcho(r.state, false), { state: r.state, send: null })
  const done = logic.powerEcho(r.state, true)
  assert.deepEqual(done, { state: { target: null, queued: null }, send: null })
  assert.deepEqual(logic.powerView(done.state, true), { on: true, busy: false })
  // An echo while idle changes nothing.
  assert.deepEqual(logic.powerEcho(null, true), { state: logic.powerIdle(), send: null })
})

test("power: clicks while busy queue, the last one wins", () => {
  let r = logic.powerClick(null, true) // turning off
  assert.equal(r.send, false)
  r = logic.powerClick(r.state, true) // back on: queued
  assert.equal(r.send, null)
  assert.deepEqual(r.state, { target: false, queued: true })
  assert.deepEqual(logic.powerView(r.state, true), { on: true, busy: true })
  // A third click returns to the in-flight state: the queue empties.
  const third = logic.powerClick(r.state, true)
  assert.deepEqual(third.state, { target: false, queued: null })
  assert.equal(third.send, null)
  // With "on" queued, the "off" echo sends it next.
  const next = logic.powerEcho(r.state, false)
  assert.deepEqual(next, { state: { target: true, queued: null }, send: true })
  // And its echo settles to the last click's state.
  assert.deepEqual(logic.powerEcho(next.state, true).state, logic.powerIdle())
})

test("power: a timeout (powerIdle) falls back to the real state", () => {
  const r = logic.powerClick(null, false)
  assert.deepEqual(logic.powerView(logic.powerIdle(), false), { on: false, busy: false })
  assert.equal(logic.powerView(r.state, false).on, true)
})

// --- Device actions: intents, in-flight, queue -------------------------------

test("row actions resolve to an intent as the panel's handler did", () => {
  assert.equal(logic.rowIntent("primary", true, "connected"), "disconnect")
  assert.equal(logic.rowIntent("primary", false, "known"), "connect")
  assert.equal(logic.rowIntent("primary", false, "discovered"), "connect")
  assert.equal(logic.rowIntent("secondary", true, "connected"), "disconnect")
  assert.equal(logic.rowIntent("secondary", false, "known"), "forget")
  assert.equal(logic.rowIntent("secondary", false, "discovered"), "")
  assert.equal(logic.rowIntent("forget", true, "connected"), "forget")
  assert.equal(logic.rowIntent("hover", false, "known"), "")
})

test("the intent in flight comes from the pending action, then BlueZ's state", () => {
  assert.equal(logic.inFlightIntent("connecting", -1, false), "connect")
  assert.equal(logic.inFlightIntent("disconnecting", -1, false), "disconnect")
  assert.equal(logic.inFlightIntent("forgetting", 3, false), "forget")
  assert.equal(logic.inFlightIntent("", 3, false), "connect")
  assert.equal(logic.inFlightIntent(undefined, -1, true), "connect")
  assert.equal(logic.inFlightIntent("", 2, false), "disconnect")
  assert.equal(logic.inFlightIntent("", 1, false), "")
  assert.equal(logic.inFlightIntent("", undefined, undefined), "")
})

test("device clicks: idle runs, busy queues (last wins), equal to in-flight drops", () => {
  // Idle: runs at once, and clears any stale queue entry.
  let r = logic.deviceClick({ A: "forget" }, "A", "connect", "")
  assert.deepEqual(r, { queue: {}, run: "connect" })
  // Busy: queued.
  r = logic.deviceClick({}, "A", "forget", "connect")
  assert.deepEqual(r, { queue: { A: "forget" }, run: "" })
  // Last one wins.
  r = logic.deviceClick(r.queue, "A", "disconnect", "connect")
  assert.deepEqual(r, { queue: { A: "disconnect" }, run: "" })
  // Equal to the action in flight: dropped (and the queue emptied).
  r = logic.deviceClick(r.queue, "A", "connect", "connect")
  assert.deepEqual(r, { queue: {}, run: "" })
  // Other devices' entries are untouched; the input is never mutated.
  const q = { B: "forget" }
  r = logic.deviceClick(q, "A", "forget", "connect")
  assert.deepEqual(r.queue, { B: "forget", A: "forget" })
  assert.deepEqual(q, { B: "forget" })
  // No intent or no key: nothing.
  assert.deepEqual(logic.deviceClick(null, "A", "", ""), { queue: {}, run: "" })
  assert.deepEqual(logic.deviceClick({}, "", "connect", ""), { queue: {}, run: "" })
})

test("queued device actions run once their device is idle; a gone device drops them", () => {
  const queue = { A: "forget", B: "connect", C: "disconnect" }
  const r = logic.takeReady(queue, { A: "", B: "connect" })
  assert.deepEqual(r.run, [{ key: "A", intent: "forget" }])
  assert.deepEqual(r.queue, { B: "connect" })
  assert.deepEqual(queue, { A: "forget", B: "connect", C: "disconnect" })
  assert.deepEqual(logic.takeReady(null, null), { queue: {}, run: [] })
})

// --- Keyboard Forget: the cursor follows to the neighbour --------------------

test("forget stops list the header, the remembered rows, then the scan's", () => {
  const stops = logic.forgetStops(["A"], ["B", "C"], ["D"])
  assert.deepEqual(stops, [
    { key: "header", section: "header", index: -1 },
    { key: "A", section: "connected", index: 0 },
    { key: "B", section: "known", index: 0 },
    { key: "C", section: "known", index: 1 },
    { key: "scan:D", section: "discovered", index: 0 }
  ])
  assert.deepEqual(logic.forgetStops(undefined, null, undefined), [
    { key: "header", section: "header", index: -1 }
  ])
})

test("followForget waits while the device is remembered, then lands on the neighbour", () => {
  // Nothing armed: no follow.
  assert.deepEqual(logic.followForget(logic.forgetStops([], ["B"], []), "", 1), {
    follow: false,
    pendingKey: "",
    lastIndex: 1
  })
  // Still remembered (a connected device moving to Paired): wait, tracking its stop.
  const waiting = logic.followForget(logic.forgetStops([], ["X", "B", "C"], []), "B", 1)
  assert.deepEqual(waiting, { follow: false, pendingKey: "B", lastIndex: 2 })
  // Gone (here back in Available as a scan row): the row now at its index.
  const landed = logic.followForget(logic.forgetStops([], ["X", "C"], ["B"]), "B", 2)
  assert.deepEqual(landed, {
    follow: true,
    pendingKey: "",
    lastIndex: 2,
    key: "C",
    section: "known",
    index: 1
  })
  // The last row: the one before it.
  const last = logic.followForget(logic.forgetStops([], ["X"], []), "C", 2)
  assert.equal(last.key, "X")
  assert.equal(last.section, "known")
  // Everything gone: the header.
  const none = logic.followForget(logic.forgetStops([], [], []), "X", 1)
  assert.deepEqual(none.section, "header")
  assert.equal(none.index, -1)
})

test("BluetoothLogic.js's generated copy of CursorLogic answers like the source", () => {
  const { loadPragma } = require("./lib/load-pragma.js")
  const source = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.shared/CursorLogic.js")
  )
  const plain = (value) => JSON.parse(JSON.stringify(value))
  const copy = loadPragma("plugins/araneadev.bluetooth/BluetoothLogic.js")
  const rows = [{ key: "a" }, { key: "b" }, { key: "c" }]
  assert.deepEqual(
    plain(copy.reselectIndex(rows, "c", 0)),
    plain(source.reselectIndex(rows, "c", 0))
  )
  assert.deepEqual(plain(copy.followCursor(rows, "b", 0)), plain(source.followCursor(rows, "b", 0)))
  assert.equal(copy.cursorConfirmed(rows, "b", 1), source.cursorConfirmed(rows, "b", 1))
  assert.equal(copy.pressIntent(true, false), source.pressIntent(true, false))
  assert.deepEqual(plain(copy.keepRows({}, "x", rows)), plain(source.keepRows({}, "x", rows)))
  assert.equal(copy.rowKeyMatches(rows, 1, "b"), source.rowKeyMatches(rows, 1, "b"))
  assert.deepEqual(plain(copy.afterRemoval(rows, "b", 1)), plain(source.afterRemoval(rows, "b", 1)))
  // And the keyed check is exported for Panel.qml.
  assert.equal(logic.rowKeyMatches(rows, 0, "a"), true)
  assert.equal(logic.rowKeyMatches(rows, 0, "b"), false)
})

// --- A connect that fails fast ------------------------------------------------

test("a connect that reached BlueZ's connecting state and fell back to disconnected clears", () => {
  const pending = { A: "connecting", B: "connecting", C: "forgetting" }
  // First read: A is connecting (3), B not yet; nothing clears.
  let r = logic.settleConnecting(pending, {}, { A: 3, B: 0, C: 0 })
  assert.deepEqual(r.pending, pending)
  assert.deepEqual(r.seen, { A: true })
  assert.equal(r.changed, false)
  // A falls back to disconnected (0): its pending entry clears.
  r = logic.settleConnecting(r.pending, r.seen, { A: 0, B: 0, C: 0 })
  assert.deepEqual(r.pending, { B: "connecting", C: "forgetting" })
  assert.deepEqual(r.seen, {})
  assert.equal(r.changed, true)
  // The input is never mutated.
  assert.deepEqual(pending, { A: "connecting", B: "connecting", C: "forgetting" })
})

test("settleConnecting keeps a connect that never reached connecting, and forgets stale marks", () => {
  // B never reached 3: a 0 keeps it waiting (the helper may still be starting).
  let r = logic.settleConnecting({ B: "connecting" }, {}, { B: 0 })
  assert.deepEqual(r.pending, { B: "connecting" })
  // A mark for a device no longer connecting is dropped.
  r = logic.settleConnecting({}, { Z: true }, {})
  assert.deepEqual(r.seen, {})
  assert.equal(r.changed, false)
  // A device that went missing keeps its entry (syncPendingActions owns that).
  r = logic.settleConnecting({ A: "connecting" }, { A: true }, {})
  assert.deepEqual(r.pending, { A: "connecting" })
  assert.deepEqual(r.seen, { A: true })
  assert.deepEqual(logic.settleConnecting(null, null, null), {
    pending: {},
    seen: {},
    changed: false
  })
})

test("the device queue is short-lived: closing or the pending timeout empties it", () => {
  assert.deepEqual(logic.queueAfter("close", { A: "forget" }), {})
  assert.deepEqual(logic.queueAfter("timeout", { A: "forget" }), {})
  assert.deepEqual(logic.queueAfter("open", { A: "forget" }), { A: "forget" })
  assert.deepEqual(logic.queueAfter("open", null), {})
})

test("powerAfter drops a queued click on close and goes idle on timeout", () => {
  const s = { target: true, queued: false }
  assert.deepEqual(logic.powerAfter("close", s), { target: true, queued: null })
  assert.deepEqual(logic.powerAfter("timeout", s), { target: null, queued: null })
  assert.deepEqual(logic.powerAfter("open", s), s)
  assert.notEqual(logic.powerAfter("open", s), s, "never the same object")
  assert.deepEqual(logic.powerAfter("close", null), { target: null, queued: null })
  assert.deepEqual(logic.powerAfter("open", {}), { target: null, queued: null })
  const closed = logic.powerAfter("close", s)
  assert.deepEqual(
    logic.powerEcho(closed, true),
    { state: { target: null, queued: null }, send: null },
    "the echo then settles without sending the dropped click"
  )
})

test("a device moving from Connected to Paired is still remembered, so the follow waits", () => {
  const moved = logic.followForget(logic.forgetStops([], ["A", "B"], []), "A", 1)
  assert.equal(moved.follow, false)
  assert.equal(moved.pendingKey, "A")
})
