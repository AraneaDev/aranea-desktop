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
