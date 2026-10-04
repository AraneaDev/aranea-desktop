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
  if (model.iconFor("brightness", 50) !== String.fromCodePoint(0xf0379))
    throw new Error("icon mapping changed")
})

test("every icon name keeps its code point", () => {
  const expected = {
    "volume-muted": 0xeee8,
    "volume-mute": 0xeee8,
    muted: 0xeee8,
    mute: 0xeee8,
    "volume-low": 0xf026,
    "volume-medium": 0xf027,
    "volume-high": 0xf028,
    volume: 0xf028,
    "microphone-muted": 0xf036d,
    "microphone-off": 0xf036d,
    "mic-muted": 0xf036d,
    "mic-off": 0xf036d,
    microphone: 0xf036c,
    mic: 0xf036c,
    keyboard: 0xf030c,
    brightness: 0xf0379,
    display: 0xf0379,
    touchpad: 0xf07f8,
    touch: 0xf0741,
    touchscreen: 0xf0741,
    reboot: 0xf0709,
    restart: 0xf0709,
    shutdown: 0xf0425,
    power: 0xf0425,
    poweroff: 0xf0425,
    logout: 0xf0343,
    "sign-out": 0xf0343,
    leave: 0xf0343,
    media: 0xf075a,
    player: 0xf075a,
    "media-source": 0xf075a,
    "player-source": 0xf075a,
    "media-play": 0xf040a,
    "player-play": 0xf040a,
    "media-pause": 0xf03e4,
    "player-pause": 0xf03e4,
    "media-next": 0xf04ad,
    "player-next": 0xf04ad,
    "media-previous": 0xf04ae,
    "player-previous": 0xf04ae
  }
  Object.keys(expected).forEach((name) => {
    eq(model.iconFor(name, -1).codePointAt(0), expected[name], `${name} glyph`)
    eq(model.iconFor(name.toUpperCase(), -1).codePointAt(0), expected[name], `${name} ignores case`)
  })
  eq(model.iconFor("", 0).codePointAt(0), 0xeee8, "0% falls back to muted")
  eq(model.iconFor("", 33).codePointAt(0), 0xf026, "33% falls back to low")
  eq(model.iconFor("", 66).codePointAt(0), 0xf027, "66% falls back to medium")
  eq(model.iconFor("", 67).codePointAt(0), 0xf028, "67% falls back to high")
  eq(model.iconFor("X", 50), "X", "an unknown name is its own glyph")
})

test("OsdModel.js spells its glyphs as code points, never literal private-use characters", () => {
  const fs = require("node:fs")
  const source = fs.readFileSync(
    path.join(__dirname, "..", "..", "plugins/araneadev.osd/OsdModel.js"),
    "utf8"
  )
  eq(/[\uE000-\uF8FF]|[\u{F0000}-\u{10FFFF}]/u.test(source), false, "no literal glyphs")
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
  // /usr/bin/omarchy-chromium-ytdlp-host passes this glyph straight through
  // `omarchy-osd -i <glyph>` (iconFor returns an unrecognized name as-is),
  // so the icon column's fixed width must cover it even though it has no
  // entry in iconNames.
  eq(
    glyphs.includes(String.fromCodePoint(0xf01da)),
    true,
    "the chromium-ytdlp-host download glyph (U+F01DA) is covered"
  )
})

test("valueColumnWidth keeps the '100%' floor for normal values and widens for out-of-range ones", () => {
  eq(model.valueColumnWidth(28, 18), 28, "a value narrower than the floor keeps the fixed width")
  eq(model.valueColumnWidth(28, 28), 28, "exactly '100%' keeps the fixed width")
  eq(model.valueColumnWidth(28, 35), 35, "'1000%' (wider than the floor) widens the column")
})

test("maxInkWidth picks the widest glyph by the measure callback, 0 for an empty list", () => {
  eq(
    model.maxInkWidth([], () => 99),
    0,
    "an empty glyph list measures 0, never calling measure"
  )
  eq(
    model.maxInkWidth(["a", "bb", "ccc", "d"], (glyph) => glyph.length),
    3,
    "picks the widest"
  )
  // Every real OSD icon glyph measures a positive width at a real font;
  // order and which entry is widest should not matter.
  const widths = { x: 5, yy: 12, zzz: 3 }
  eq(
    model.maxInkWidth(Object.keys(widths), (glyph) => widths[glyph]),
    12,
    "reads the measure callback per glyph"
  )
  eq(
    model.maxInkWidth(Object.keys(widths).reverse(), (glyph) => widths[glyph]),
    12,
    "order does not matter"
  )
})
