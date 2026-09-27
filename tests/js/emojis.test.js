// Logic contract for the emojis modules (moved from tests/emojis.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")

test("emojis logic", () => {
  const root = path.join(__dirname, "..", "..")
  const m = require(`${root}/plugins/araneadev.emojis/EmojiLogic.js`)
  const assert = (cond, msg) => {
    if (!cond) throw new Error(msg)
  }

  assert(m.parseRecents('{"version":1,"recent":["🚀","✅"]}').join() === "🚀,✅", "parse recents")
  assert(
    m.parseRecents("{broken").length === 0 && m.parseRecents("").length === 0,
    "corrupt recents are empty"
  )
  let r = []
  for (const e of ["a", "b", "c", "b"]) r = m.pushRecent(r, e, 16)
  assert(r.join() === "b,c,a", "newest first, deduped")
  for (let i = 0; i < 20; i++) r = m.pushRecent(r, "x" + i, 16)
  assert(r.length === 16 && r[0] === "x19", "capped at 16")
  assert(JSON.parse(m.serializeRecents(["🚀"])).recent[0] === "🚀", "serialize")
  assert(
    m.emojiName("grinning face smile grinning happy") === "grinning face smile",
    "stop at a repeated word, max 3"
  )
  assert(m.emojiName("rocket launch space ship") === "rocket launch space", "max three words")
  assert(m.emojiName("thumbs thumbs up") === "thumbs", "repeat stops early")
  assert(m.emojiName("") === "", "empty keywords")
  // m8: a recent stored with VS16 still finds its keywords
  assert(
    m.keywordsFor({ "🕷": "spider insect" }, "🕷️") === "spider insect",
    "VS16 variant falls back to the base emoji"
  )
  assert(m.keywordsFor({ "❤️": "red heart love" }, "❤️") === "red heart love", "exact match first")

  const data = JSON.parse(
    require("fs").readFileSync(`${root}/plugins/araneadev.emojis/emojis.json`, "utf8")
  )
  assert(Array.isArray(data) && data.length > 1000 && data[0].e && data[0].k, "emoji data copied")
  console.log("emoji logic contract passed")
})
