import assert from "node:assert/strict"
import { test } from "node:test"
import fs from "node:fs"
import { journey, DURATION, WALK_SPEED } from "../../branding/3d/live/journey.mjs"

test("spider actually traverses both bridges and descends between them", () => {
  assert.ok(journey(0).position[2] - journey(45).position[2] > 14)
  assert.equal(journey(60).phase, "descend")
  assert.ok(journey(60).position[1] > journey(70).position[1] + 4)
  assert.ok(journey(125).position[2] - journey(85).position[2] > 12)
  assert.equal(journey(145).phase, "ascend")
})
test("route and camera close continuously at every boundary and full loop", () => {
  for (const t of [0, 50, 56, 74, 80, 130, 136, 154, 160]) {
    const a = journey(t - 0.0001),
      b = journey(t + 0.0001)
    for (const key of ["position", "camera", "target"]) {
      assert.ok(Math.hypot(...a[key].map((v, i) => v - b[key][i])) < 0.01, `${key} jumps at ${t}`)
    }
  }
  assert.deepEqual(journey(0), journey(DURATION))
})
test("walking pauses while suspended; camera changes viewpoint and all values are finite", () => {
  assert.equal(journey(65).walk, 0)
  assert.ok(journey(25).walk > 0.9)
  assert.ok(Math.hypot(...journey(25).camera.map((v, i) => v - journey(25).position[i])) > 7)
  for (let t = 0; t < DURATION; t += 0.1) {
    const state = journey(t)
    for (const key of ["position", "camera", "target"]) assert.ok(state[key].every(Number.isFinite))
    assert.ok(state.walk >= 0 && state.walk <= 1)
  }
})

test("vertical silk travel stays outside the solid bridge decks", () => {
  for (let t = 56; t < 74; t += 0.1) assert.ok(journey(t).position[0] > 4)
  for (let t = 136; t < 154; t += 0.1) assert.ok(journey(t).position[0] < -4)
})

test("camera stays beside the suspended spider instead of behind the bridge", () => {
  for (let t = 56; t < 74; t += 0.1) assert.ok(journey(t).camera[0] > journey(t).position[0])
  for (let t = 136; t < 154; t += 0.1) assert.ok(journey(t).camera[0] < journey(t).position[0])
  assert.ok(journey(77).walk > 0.5)
  assert.ok(journey(157).walk > 0.5)
})

test("gait pace and facing match actual horizontal travel, including sidesteps", () => {
  for (const time of [10, 25, 53, 77, 105, 133, 157]) {
    const a = journey(time - 0.001).position,
      b = journey(time + 0.001).position
    const vx = (b[0] - a[0]) / 0.002,
      vz = (b[2] - a[2]) / 0.002
    assert.ok(Math.abs(journey(time).speed - Math.hypot(vx, vz)) < 0.001)
    assert.ok(Math.abs(Math.sin(journey(time).heading - Math.atan2(-vx, -vz))) < 0.001)
  }
  assert.equal(journey(65).speed, 0)
})

test("live gait rate matches the exported model contract", () => {
  const model = JSON.parse(
    fs.readFileSync(new URL("../../branding/3d/model-info.json", import.meta.url), "utf8")
  )
  assert.ok(Math.abs(model.walk_world_speed - WALK_SPEED) < 1e-8)
})
