import assert from "node:assert/strict"
import { test } from "node:test"
import { EventDirector, EVENT_KINDS, GLYPHS } from "../../branding/3d/live/events.mjs"

test("events are rare, bounded and never overlap", () => {
  const d = new EventDirector(() => 0.25)
  assert.equal(d.sample(20), null)
  assert.equal(d.sample(40), null)
  const first = d.sample(44)
  assert.ok(first && EVENT_KINDS.includes(first.kind))
  assert.equal(d.sample(45), first)
  assert.equal(d.sample(60), null)
  assert.equal(d.sample(80), null)
  const next = d.sample(120)
  assert.ok(next && next.kind !== first.kind)
})
test("both kanji styles use only bundled glyphs; all event kinds can be selected", () => {
  const kinds = new Set()
  for (const v of [0, 0.26, 0.51, 0.76]) {
    const d = new EventDirector(() => v)
    d.sample(0)
    const e = d.sample(50)
    kinds.add(e.kind)
    assert.ok(GLYPHS.includes(e.glyph))
    assert.ok(e.duration >= 7 && e.duration <= 12)
  }
  assert.deepEqual(kinds, new Set(EVENT_KINDS))
})
