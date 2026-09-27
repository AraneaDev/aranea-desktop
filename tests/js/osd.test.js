// Logic contract for the osd modules (moved from tests/osd.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")

test("osd logic", () => {
  const root = path.join(__dirname, "..", "..")
  const model = require(`${root}/plugins/araneadev.osd/OsdModel.js`)

  const progress = model.stateForShow("volume", "", "150", "100", "", "1200")
  if (!progress.hasProgress || progress.value !== 100 || progress.message !== "100%")
    throw new Error("progress payload was not clamped")
  if (model.progressFraction(progress) !== 1)
    throw new Error("progress fraction was not normalized")

  const message = model.stateForShow("media-play", "Playing", "", "100", "", "not-a-number")
  if (message.hasProgress || message.message !== "Playing" || message.duration !== 1200)
    throw new Error("message payload was not normalized")

  const zero = model.stateForShow("volume", "", "0", "0", "", "-1")
  if (zero.maxValue !== 1 || model.progressFraction(zero) !== 0 || zero.duration !== 0)
    throw new Error("zero/max duration edge case failed")
  if (model.iconFor("brightness", 50) !== "󰍹") throw new Error("icon mapping changed")

  console.log("osd model contract passed")
})

test("osd maximum and value (4d)", () => {
  const o = require(path.join(__dirname, "..", "..", "plugins/araneadev.osd/OsdModel.js"))
  const eq = (a, b, msg) => {
    if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  const bad = o.stateForShow("", "", "50", "abc", "", "")
  eq(bad.maxValue, 100, "non-numeric max means 100")
  eq(bad.message, "50%", "no NaN%")
  eq(o.stateForShow("", "", undefined, "", "", "").hasProgress, false, "undefined value: no bar")
  eq(o.stateForShow("", "", null, "", "", "").hasProgress, false, "null value: no bar")
  eq(o.stateForShow("", "", "", "", "", "").hasProgress, false, "empty value: no bar")
  eq(o.stateForShow("", "", "0", "", "", "").hasProgress, true, "zero is a value")
  eq(o.widestIcon, undefined, "unused export removed")
})
