// Logic contract for the osd modules (moved from tests/osd.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")

const model = require(path.join(__dirname, "..", "..", "plugins/araneadev.osd/OsdModel.js"))
const eq = (a, b, msg) => {
  if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
}

test("a progress value is clamped to the maximum", () => {
  const progress = model.stateForShow("volume", "", "150", "100", "", "1200")
  if (!progress.hasProgress || progress.value !== 100 || progress.message !== "100%")
    throw new Error("progress payload was not clamped")
  if (model.progressFraction(progress) !== 1)
    throw new Error("progress fraction was not normalized")
})

test("a message without a value shows no bar and gets the default duration", () => {
  const message = model.stateForShow("media-play", "Playing", "", "100", "", "not-a-number")
  if (message.hasProgress || message.message !== "Playing" || message.duration !== 1200)
    throw new Error("message payload was not normalized")
})

test("a zero maximum and a negative duration are safe", () => {
  const zero = model.stateForShow("volume", "", "0", "0", "", "-1")
  if (zero.maxValue !== 1 || model.progressFraction(zero) !== 0 || zero.duration !== 0)
    throw new Error("zero/max duration edge case failed")
})

test("brightness keeps its icon", () => {
  if (model.iconFor("brightness", 50) !== "󰍹") throw new Error("icon mapping changed")
})

test("a non-numeric maximum means 100 and never shows NaN%", () => {
  const bad = model.stateForShow("", "", "50", "abc", "", "")
  eq(bad.maxValue, 100, "non-numeric max means 100")
  eq(bad.message, "50%", "no NaN%")
})

test("only a real value shows a bar, and zero is a value", () => {
  eq(
    model.stateForShow("", "", undefined, "", "", "").hasProgress,
    false,
    "undefined value: no bar"
  )
  eq(model.stateForShow("", "", null, "", "", "").hasProgress, false, "null value: no bar")
  eq(model.stateForShow("", "", "", "", "", "").hasProgress, false, "empty value: no bar")
  eq(model.stateForShow("", "", "0", "", "", "").hasProgress, true, "zero is a value")
  eq(model.widestIcon, undefined, "unused export removed")
})

test("allIconGlyphs covers every glyph the OSD can show, no duplicates", () => {
  const glyphs = model.allIconGlyphs()
  eq(Array.isArray(glyphs), true, "allIconGlyphs returns an array")
  eq(glyphs.length > 0, true, "allIconGlyphs is not empty")
  eq(
    glyphs.every((glyph) => typeof glyph === "string" && glyph.length > 0),
    true,
    "every glyph is a non-empty string"
  )
  eq(new Set(glyphs).size, glyphs.length, "allIconGlyphs has no duplicate glyphs")
  // The percent-only fallback (no icon name) reuses the volume-* glyphs, so
  // it needs no separate entries in allIconGlyphs to be covered.
  ;[0, 20, 50, 80, 100].forEach((percent) => {
    eq(
      glyphs.includes(model.iconFor("", percent)),
      true,
      `percent fallback glyph for ${percent}% is covered`
    )
  })
})
