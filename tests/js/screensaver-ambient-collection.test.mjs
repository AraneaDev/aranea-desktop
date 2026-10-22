import test from "node:test"
import assert from "node:assert/strict"
import {
  cityDepth,
  ribbonPoint,
  glyphPhase,
  renderScale
} from "../../branding/3d/collection/ambient/motion.mjs"

test("city blocks recycle behind the camera without leaving a gap in the flight corridor", () => {
  assert.equal(cityDepth(0, 0), -12)
  assert.equal(cityDepth(0, 20), -12)
  for (let t = 0; t < 100; t += 0.17) {
    const depths = Array.from({ length: 24 }, (_, i) => cityDepth(i, t)).sort((a, b) => a - b)
    assert.ok(depths.every((z) => z >= -276 && z < 12))
    for (let i = 1; i < depths.length; i++)
      assert.ok(Math.abs(depths[i] - depths[i - 1] - 12) < 1e-9)
  }
})
test("silk ribbons retain their width and deform continuously in three dimensions", () => {
  const a = ribbonPoint(0.4, -0.5, 2, 1)
  const b = ribbonPoint(0.4, 0.5, 2, 1)
  assert.ok(Math.hypot(...a.map((v, i) => v - b[i])) > 0.8)
  const next = ribbonPoint(0.4, -0.5, 2.001, 1)
  assert.ok(Math.hypot(...a.map((v, i) => v - next[i])) < 0.02)
  assert.ok(a.every(Number.isFinite))
  assert.notDeepEqual(a, ribbonPoint(0.7, -0.5, 2, 1))
})
test("glyph dissolution is staggered, repeats deterministically and has visible intact and scattered phases", () => {
  assert.deepEqual(glyphPhase(0, 0), { cycle: 0, dissolve: 0 })
  assert.equal(glyphPhase(0, 10).dissolve, 1)
  assert.deepEqual(glyphPhase(0, 12), { cycle: 1, dissolve: 0 })
  assert.notDeepEqual(glyphPhase(0, 6), glyphPhase(1, 6))
})
test("render sizing enforces both pixel and device ratio budgets", () => {
  assert.equal(renderScale(1000, 1000, 3), 1.4)
  assert.ok(3840 * 2160 * renderScale(3840, 2160, 2) ** 2 <= 2100000.0001)
  assert.equal(renderScale(800, 600, 1), 1)
})
