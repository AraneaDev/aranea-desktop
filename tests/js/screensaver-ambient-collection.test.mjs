import * as motion from "../../branding/3d/collection/ambient/motion.mjs"
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

test("glyph school assembles into a readable crest and releases continuously", () => {
  assert.equal(typeof motion.glyphFormation, "function")
  assert.equal(motion.glyphFormation(0), 0)
  assert.equal(motion.glyphFormation(28), 1)
  assert.equal(motion.glyphFormation(36), 0)
  assert.equal(motion.glyphFormation(76), 1)
  for (const t of [20, 28, 36, 48])
    assert.ok(Math.abs(motion.glyphFormation(t + 0.001) - motion.glyphFormation(t)) < 0.001)
})
test("silk braid has a bounded quiet interval and a sustained cinematic peak", () => {
  assert.equal(typeof motion.silkBurst, "function")
  assert.equal(motion.silkBurst(0), 0)
  assert.equal(motion.silkBurst(25), 1)
  assert.equal(motion.silkBurst(32), 0)
  for (let t = 0; t < 90; t += 0.13) {
    const pulse = motion.silkBurst(t)
    assert.ok(pulse >= 0 && pulse <= 1)
    assert.ok(Math.abs(pulse - motion.silkBurst(t + 0.001)) < 0.001)
    for (const layer of [0, 3, 6]) {
      const p = ribbonPoint(0.4, 0.5, t, layer)
      const q = ribbonPoint(0.4, 0.5, t + 0.001, layer)
      assert.ok(Math.hypot(...p.map((v, i) => v - q[i])) < 0.05)
    }
  }
})
test("city express crosses the corridor smoothly and disappears before recycling", () => {
  assert.equal(typeof motion.transitState, "function")
  const start = motion.transitState(12),
    middle = motion.transitState(18),
    end = motion.transitState(24)
  assert.equal(start.opacity, 0)
  assert.equal(middle.opacity, 1)
  assert.equal(end.opacity, 0)
  assert.ok(start.x < -35 && end.x > 35)
  assert.equal(middle.x, 0)
  assert.deepEqual(motion.transitState(18), motion.transitState(60))
  for (let t = 12; t < 24; t += 0.1) {
    const a = motion.transitState(t),
      b = motion.transitState(t + 0.001)
    assert.ok(Math.abs(a.x - b.x) < 0.02)
    assert.ok(Math.abs(a.opacity - b.opacity) < 0.002)
  }
})
