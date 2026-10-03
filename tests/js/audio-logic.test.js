// Logic contract for the Aranea audio dropdown (AudioLogic.js).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.audio/AudioLogic.js"))

test("a rising peak is followed fast, a falling one slowly", () => {
  const up = logic.signalLevel(0, 1, 33)
  const down = logic.signalLevel(1, 0, 33)
  assert.ok(up > 0.6, `attack too slow: ${up}`)
  assert.ok(down > 0.85, `decay too fast: ${down}`)
})

test("the level stays within 0..1 and ignores bad input", () => {
  assert.equal(logic.signalLevel(0.5, 7, 1000), 1)
  assert.equal(logic.signalLevel(0.5, -3, 100000), 0)
  assert.equal(logic.signalLevel(0.4, 0.9, 0), 0.4)
  assert.equal(logic.signalLevel(0.4, 0.9, -5), 0.4)
  assert.ok(logic.signalLevel(0.4, NaN, 33) < 0.4)
  assert.equal(logic.signalLevel(NaN, 0, 33), 0)
})

test("a tiny level snaps to zero so the glow can switch off", () => {
  assert.equal(logic.signalLevel(0.0005, 0, 33), 0)
})

const player = (dbusName, isPlaying) => ({ dbusName, isPlaying })

test("a playing player wins over paused ones", () => {
  const players = [player("a", false), player("b", true)]
  assert.equal(logic.pickPlayer(players, "a").dbusName, "b")
})

test("without a playing player the last one is kept", () => {
  const players = [player("a", false), player("b", false)]
  assert.equal(logic.pickPlayer(players, "b").dbusName, "b")
})

test("no players, or an unknown last one, gives none", () => {
  assert.equal(logic.pickPlayer([], "a"), null)
  assert.equal(logic.pickPlayer(null, "a"), null)
  assert.equal(logic.pickPlayer([player("a", false)], "zzz"), null)
})

test("now playing reads the track and progress from the player", () => {
  const p = {
    identity: "Spotify",
    trackTitle: "Midnight City",
    trackArtist: "M83",
    trackAlbum: "Hurry Up, We're Dreaming",
    position: 60,
    length: 240,
    lengthSupported: true,
    isPlaying: true,
    canGoPrevious: true,
    canGoNext: false
  }
  assert.deepEqual(logic.nowPlayingState(p), {
    visible: true,
    player: "Spotify",
    title: "Midnight City",
    artist: "M83",
    album: "Hurry Up, We're Dreaming",
    progress: 0.25,
    playing: true,
    canPrevious: true,
    canNext: false
  })
})

test("no length hides the progress, no title falls back to the player", () => {
  const s = logic.nowPlayingState({
    identity: "mpv",
    trackTitle: "",
    length: 0,
    lengthSupported: false
  })
  assert.equal(s.progress, -1)
  assert.equal(s.title, "mpv")
  assert.equal(s.artist, "")
})

test("no player means nothing to show", () => {
  assert.equal(logic.nowPlayingState(null).visible, false)
})

test("progress is clamped to 0..1", () => {
  const s = logic.nowPlayingState({
    identity: "x",
    trackTitle: "t",
    position: 500,
    length: 100,
    lengthSupported: true
  })
  assert.equal(s.progress, 1)
})

test("a device's detail names how it is connected", () => {
  const hdmi = { "node.name": "alsa_output.pci-0000_00_1f.3.hdmi-stereo", "device.api": "alsa" }
  const dp = { "node.description": "LG ULTRAGEAR DisplayPort 2" }
  const bt = { "device.api": "bluez5", "node.name": "bluez_output.AA_BB" }
  const usb = { "device.bus": "usb", "node.name": "alsa_output.usb-Focusrite" }
  assert.equal(logic.deviceDetail(hdmi, true, false), "HDMI")
  assert.equal(logic.deviceDetail(dp, true, false), "DisplayPort")
  assert.equal(logic.deviceDetail(bt, true, false), "bluetooth")
  assert.equal(logic.deviceDetail(usb, false, false), "USB")
  assert.equal(logic.deviceDetail(bt, true, true), "headphones")
})

test("a plain device is speakers or a mic, even without properties", () => {
  assert.equal(
    logic.deviceDetail({ "node.name": "alsa_output.pci-0000_00_1f.3.analog-stereo" }, true, false),
    "speakers"
  )
  assert.equal(logic.deviceDetail({}, false, false), "mic")
  assert.equal(logic.deviceDetail(null, true, false), "speakers")
  assert.equal(logic.deviceDetail(undefined, false, false), "mic")
})

test("an idle default-device choice is sent at once and pulses", () => {
  const r = logic.defaultClick(logic.defaultIdle(), "52", "47")
  assert.deepEqual(r, { state: { target: "52", queued: null }, send: "52" })
  assert.deepEqual(logic.defaultView(r.state, "47"), { key: "52", busy: true })
  assert.deepEqual(logic.defaultClick(null, "52", "47").send, "52")
})

test("choosing the current default re-sends it without a pulse", () => {
  const r = logic.defaultClick(null, "47", "47")
  assert.deepEqual(r, { state: { target: null, queued: null }, send: "47" })
  assert.deepEqual(logic.defaultView(r.state, "47"), { key: "47", busy: false })
})

test("a choice without a key does nothing", () => {
  const s = { target: "52", queued: null }
  assert.deepEqual(logic.defaultClick(s, "", "47"), { state: s, send: null })
  assert.deepEqual(logic.defaultClick(s, undefined, "47"), { state: s, send: null })
})

test("choices while a switch is in flight queue, and the last one wins", () => {
  let s = logic.defaultClick(null, "52", "47").state
  let r = logic.defaultClick(s, "60", "47")
  assert.deepEqual(r, { state: { target: "52", queued: "60" }, send: null })
  r = logic.defaultClick(r.state, "47", "47")
  assert.deepEqual(r, { state: { target: "52", queued: "47" }, send: null })
  assert.deepEqual(logic.defaultView(r.state, "47"), { key: "47", busy: true })
  r = logic.defaultClick(r.state, "52", "47")
  assert.deepEqual(
    r,
    { state: { target: "52", queued: null }, send: null },
    "back to the in-flight one empties the queue"
  )
})

test("the echo settles the switch or sends the queued choice", () => {
  const busy = { target: "52", queued: null }
  assert.deepEqual(
    logic.defaultEcho(busy, "47"),
    { state: busy, send: null },
    "another default keeps waiting"
  )
  assert.deepEqual(logic.defaultEcho(busy, "52"), {
    state: { target: null, queued: null },
    send: null
  })
  const queued = { target: "52", queued: "60" }
  assert.deepEqual(logic.defaultEcho(queued, "52"), {
    state: { target: "60", queued: null },
    send: "60"
  })
  const same = { target: "52", queued: "52" }
  assert.deepEqual(logic.defaultEcho(same, "52").state, { target: null, queued: null })
  assert.deepEqual(logic.defaultEcho(null, "52"), {
    state: { target: null, queued: null },
    send: null
  })
})

test("rapid choices end on the last one with no pulse left", () => {
  let s = logic.defaultIdle()
  const sent = []
  for (const key of ["52", "60", "61", "60"]) {
    const r = logic.defaultClick(s, key, "47")
    s = r.state
    if (r.send) sent.push(r.send)
  }
  let r = logic.defaultEcho(s, "52")
  s = r.state
  if (r.send) sent.push(r.send)
  r = logic.defaultEcho(s, "60")
  s = r.state
  assert.deepEqual(sent, ["52", "60"])
  assert.deepEqual(logic.defaultView(s, "60"), { key: "60", busy: false })
})

test("the timeout falls back to the real default; closing drops the queue", () => {
  assert.equal(logic.defaultTimeoutMs, 4000)
  const s = { target: "52", queued: "60" }
  assert.deepEqual(logic.defaultAfter("timeout", s), { target: null, queued: null })
  assert.deepEqual(logic.defaultView(logic.defaultAfter("timeout", s), "47"), {
    key: "47",
    busy: false
  })
  assert.deepEqual(logic.defaultAfter("close", s), { target: "52", queued: null })
  assert.deepEqual(logic.defaultAfter("close", null), { target: null, queued: null })
  assert.deepEqual(logic.defaultAfter("open", s), s)
  assert.notEqual(logic.defaultAfter("open", s), s, "never the same object")
  assert.deepEqual(logic.defaultView(null, undefined), { key: "", busy: false })
})

test("a keyed node lookup refuses a row that changed underneath", () => {
  const list = [{ id: 7 }, { id: 8 }, null]
  assert.equal(logic.nodeAt(list, 1, "8"), list[1])
  assert.equal(logic.nodeAt(list, 0, "8"), null, "a re-sort is refused")
  assert.equal(logic.nodeAt(list, 2, "9"), null)
  assert.equal(logic.nodeAt(list, 3, "8"), null)
  assert.equal(logic.nodeAt(list, -1, "7"), null)
  assert.equal(logic.nodeAt(list, 0, ""), null)
  assert.equal(logic.nodeAt(null, 0, "7"), null)
  assert.equal(logic.nodeByKey(list, "8"), list[1])
  assert.equal(logic.nodeByKey(list, "9"), null)
  assert.equal(logic.nodeByKey(list, ""), null)
  assert.equal(logic.nodeByKey(undefined, "7"), null)
})

test("a device is keyed by its id and name, so a reused id never matches", () => {
  const speakers = { id: 52, name: "alsa_output.analog" }
  const reused = { id: 52, name: "bluez_output.headset" }
  assert.equal(logic.deviceKey(speakers), "52:alsa_output.analog")
  assert.equal(logic.deviceKey({ id: 3 }), "3:")
  assert.equal(logic.deviceKey(null), "")
  const key = logic.deviceKey(speakers)
  assert.equal(logic.nodeAt([speakers], 0, key, true), speakers)
  assert.equal(logic.nodeAt([reused], 0, key, true), null, "the reused id is refused")
  assert.equal(logic.nodeAt([speakers], 0, "52"), speakers, "streams stay keyed by id")
  assert.equal(logic.nodeByKey([reused, speakers], key, true), speakers)
  assert.equal(logic.nodeByKey([reused], key, true), null)
  const pending = logic.defaultClick(null, key, "47:alsa_output.hdmi").state
  assert.deepEqual(
    logic.defaultEcho(pending, logic.deviceKey(reused)).state,
    pending,
    "a reused id's echo keeps waiting"
  )
})
