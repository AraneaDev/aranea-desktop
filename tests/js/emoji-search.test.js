// Logic contract for the emoji picker's search (EmojiSearch.js).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const search = require(path.join(__dirname, "..", "..", "plugins/araneadev.emojis/EmojiSearch.js"))

const entries = [
  { e: "😀", k: "grinning face smile" },
  { e: "🐱", k: "cat face pet" },
  { e: "", k: "no emoji here" },
  null,
  { e: "🐶", k: "Dog Face pet" }
]

test("parseEmojis reads a JSON array and nothing else", () => {
  assert.deepEqual(search.parseEmojis('[{"e":"😀","k":"smile"}]'), [{ e: "😀", k: "smile" }])
  assert.deepEqual(search.parseEmojis('{"e":"😀"}'), [])
  assert.deepEqual(search.parseEmojis("not json"), [])
  assert.deepEqual(search.parseEmojis(null), [])
})

test("normalizedQuery trims and lowercases, with null as empty", () => {
  assert.equal(search.normalizedQuery("  Cat "), "cat")
  assert.equal(search.normalizedQuery(null), "")
})

test("filterEmojis matches keyword substrings in data order, ignoring case", () => {
  assert.deepEqual(
    search.filterEmojis(entries, " PET").map((x) => x.e),
    ["🐱", "🐶"]
  )
  assert.deepEqual(
    search.filterEmojis(entries, "dog").map((x) => x.e),
    ["🐶"]
  )
})

test("filterEmojis skips entries without an emoji and matches all on an empty query", () => {
  assert.deepEqual(
    search.filterEmojis(entries, "").map((x) => x.e),
    ["😀", "🐱", "🐶"]
  )
  assert.deepEqual(search.filterEmojis(entries, "no emoji"), [])
})

test("filterEmojis honours the limit; missing or NaN means 1000, negative means none", () => {
  assert.equal(search.filterEmojis(entries, "face", 1).length, 1)
  assert.equal(search.filterEmojis(entries, "face", null).length, 3)
  assert.equal(search.filterEmojis(entries, "face", "many").length, 3)
  assert.deepEqual(search.filterEmojis(entries, "face", -2), [])
  assert.deepEqual(search.filterEmojis("not a list", "face"), [])
})
