import test from "node:test"
import assert from "node:assert/strict"
const motion = await import("../../branding/3d/collection/ambient/expansion-motion.mjs").catch(
  () => ({})
)
test("surprise envelopes open gently, peak, and close before the next cycle", () => {
  assert.equal(typeof motion.eventEnvelope, "function", "event envelope is implemented")
  for (const [time, expected] of [
    [0, 0],
    [12, 0],
    [16, 1],
    [20, 0],
    [40, 1],
    [-8, 1]
  ])
    assert.ok(Math.abs(motion.eventEnvelope(time, 24, 12, 8) - expected) < 1e-9)
  assert.ok(motion.eventEnvelope(12.001, 24, 12, 8) < 0.00001)
  assert.ok(motion.eventEnvelope(19.999, 24, 12, 8) < 0.00001)
})
test("scene event states are deterministic, bounded, and independent of sample order", () => {
  assert.equal(typeof motion.expansionState, "function", "scene event sampler is implemented")
  const expected = motion.expansionState(24)
  assert.ok(expected.eclipse > 0.9)
  motion.expansionState(4000)
  assert.deepEqual(motion.expansionState(24), expected)
  for (let t = -100; t <= 300; t += 0.17)
    for (const value of Object.values(motion.expansionState(t))) assert.ok(value >= 0 && value <= 1)
})

test("reactor travel retains bounded speed through events after one hour and one day", () => {
  assert.equal(typeof motion.foundryParticleTravel, "function")
  for (const age of [0, 3600, 86400]) {
    const cycle = Math.floor(age / 36) * 36
    for (let offset = 19.9; offset < 32.2; offset += 1 / 30) {
      const t = cycle + offset
      const step =
        motion.foundryParticleTravel(t + 1 / 30, 17) - motion.foundryParticleTravel(t, 17)
      assert.ok(Math.abs(step) < 0.042, `travel speed at ${t}: ${step}`)
    }
    for (const edge of [20, 32, 36]) {
      const t = cycle + edge
      assert.ok(
        Math.abs(
          motion.foundryParticleTravel(t + 0.0001, 17) -
            motion.foundryParticleTravel(t - 0.0001, 17)
        ) < 0.0003
      )
    }
  }
})
test("crystal shatter twist stays gentle and closes continuously after one hour and one day", () => {
  assert.equal(typeof motion.crystalTwist, "function")
  for (const age of [0, 3600, 86400]) {
    const cycle = Math.floor(age / 42) * 42
    for (let offset = 24.9; offset < 34.2; offset += 1 / 30) {
      const t = cycle + offset
      const twist = motion.crystalTwist(t, 23)
      assert.ok(Math.abs(twist) <= 0.45)
      assert.ok(Math.abs(motion.crystalTwist(t + 1 / 30, 23) - twist) < 0.018)
    }
    for (const edge of [25, 34, 42]) {
      const t = cycle + edge
      assert.ok(
        Math.abs(motion.crystalTwist(t + 0.0001, 23) - motion.crystalTwist(t - 0.0001, 23)) < 0.0002
      )
    }
  }
})
