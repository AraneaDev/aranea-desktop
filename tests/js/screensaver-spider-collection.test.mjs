import test from "node:test"
import assert from "node:assert/strict"
import * as motion from "../../branding/3d/collection/spider/motion.mjs"

test("weaver gait follows actual ground distance and faces its continuous route", () => {
  assert.equal(typeof motion.weaver, "function", "weaver choreography is implemented")
  for (let t = 0; t < 240; t += 0.137) {
    const a = motion.weaver(t - 0.001),
      b = motion.weaver(t + 0.001),
      s = motion.weaver(t)
    const v = b.position.map((x, i) => (x - a.position[i]) / 0.002)
    assert.ok(Math.abs(Math.hypot(v[0], v[2]) - s.speed) < 0.00001)
    assert.ok(Math.abs((b.distance - a.distance) / 0.002 - s.speed) < 0.00001)
    const turn = Math.atan2(-v[0], -v[2]) - s.heading
    assert.ok(Math.abs(Math.atan2(Math.sin(turn), Math.cos(turn))) < 0.00001)
    assert.equal(s.position[1], 0)
    assert.equal(s.walk, 1)
  }
})

test("spiderfall hangs on silk without activating a walking gait", () => {
  assert.equal(typeof motion.spiderfall, "function", "spiderfall choreography is implemented")
  assert.equal(motion.spiderfall(0).position[1], 4)
  assert.equal(motion.spiderfall(48).position[1], -28)
  for (let t = 0; t < 96; t += 0.13) {
    const s = motion.spiderfall(t)
    assert.equal(s.walk, 0)
    assert.equal(s.speed, 0)
    assert.ok(s.anchor[1] > s.position[1] + 2)
    assert.ok(s.position[1] >= -28 && s.position[1] <= 4)
  }
})

test("camera and body remain finite and continuous through cycle boundaries", () => {
  for (const [sample, duration] of [
    [motion.weaver, 120],
    [motion.spiderfall, 96]
  ]) {
    assert.equal(typeof sample, "function")
    for (const t of [-duration, -0.001, 0, duration - 0.001, duration, 1e6]) {
      const a = sample(t),
        b = sample(t + 0.001)
      for (const key of ["position", "camera", "target"]) {
        assert.ok(a[key].every(Number.isFinite))
        assert.ok(Math.hypot(...a[key].map((v, i) => v - b[key][i])) < 0.02)
        assert.ok(Math.hypot(...sample(0)[key].map((v, i) => v - sample(duration)[key][i])) < 1e-10)
      }
    }
  }
})

test("camera routes stay inside architecture so walls cannot mask the spider", () => {
  for (let t = 0; t < 120; t += 0.1) {
    const terrace = motion.weaver(t).camera
    assert.ok(Math.hypot(terrace[0], terrace[2]) < 9.3)
    const shaft = motion.spiderfall(t).camera
    assert.ok(Math.hypot(shaft[0], shaft[2]) < 4)
  }
})
