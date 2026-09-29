const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const normalization = loadPragma("plugins/araneadev.clipboard/ClipboardNormalization.js")

test("clipboard normalization keeps supported base entry shapes", () => {
  assert.equal(
    JSON.stringify(normalization.normalizeBase(" hello ")),
    JSON.stringify({ type: "text", text: " hello " })
  )
  assert.equal(
    JSON.stringify(normalization.normalizeBase({ type: "image", path: "/tmp/a.png" })),
    JSON.stringify({ type: "image", path: "/tmp/a.png", mime: "image/png" })
  )
  assert.equal(normalization.normalizeBase("   "), null)
})

test("clipboard normalization preserves typed entry metadata", () => {
  assert.equal(
    JSON.stringify(
      normalization.normalizeEntry({
        type: "text",
        text: "secret",
        kind: "password",
        secret: true,
        pinned: true,
        pinnedAtMs: "42"
      })
    ),
    JSON.stringify({
      type: "text",
      text: "secret",
      kind: "password",
      secret: true,
      pinned: true,
      pinnedAtMs: 42
    })
  )
})
