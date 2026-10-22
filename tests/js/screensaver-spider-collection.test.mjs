import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
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

test("loom resonance blooms briefly, resets continuously, and preserves shaft clearance", () => {
  assert.equal(typeof motion.loomState, "function", "environment choreography exists")
  for (const fall of [false, true]) {
    const duration = fall ? 96 : 120
    let bright = 0
    for (let t = 0; t < duration; t += 0.1) {
      const state = motion.loomState(t, fall)
      assert.ok(state.resonance >= 0 && state.resonance <= 1)
      assert.ok(state.aperture >= 2.8 && state.aperture <= 4.7)
      if (state.resonance > 0.1) bright++
      assert.ok(Math.abs(state.resonance - motion.loomState(t + duration, fall).resonance) < 1e-10)
    }
    assert.ok(
      bright > 10 && bright < duration * 2.5,
      "a visible transformation has a quiet interval"
    )
    const before = motion.loomState(duration - 0.001, fall)
    const after = motion.loomState(duration + 0.001, fall)
    assert.ok(Math.abs(before.aperture - after.aperture) < 0.001)
  }
})

test("silk chase vertices stay within their architecture and away from the hanging spider", () => {
  assert.equal(typeof motion.writeLoomSignals, "function", "batched silk chase exists")
  for (const fall of [false, true]) {
    const vertices = new Float32Array(192 * 3).fill(NaN)
    motion.writeLoomSignals(vertices, 22, fall)
    assert.ok(vertices.every(Number.isFinite))
    const replay = new Float32Array(vertices.length)
    motion.writeLoomSignals(replay, 22, fall)
    assert.deepEqual(vertices, replay)
    for (let i = 0; i < vertices.length; i += 3) {
      const radius = Math.hypot(vertices[i], vertices[i + 2])
      assert.ok(radius < (fall ? 4.3 : 4.8))
      if (fall) {
        assert.ok(radius > 2.5)
        assert.ok(vertices[i + 1] >= -42 && vertices[i + 1] <= 14)
      }
    }
    motion.writeLoomSignals(replay, 23, fall)
    assert.notDeepEqual(vertices, replay, "signals travel independently of the spider")
  }
})

test("weaver keeps the complete articulated model inside the camera throughout its route", () => {
  const glb = readFileSync(new URL("../../branding/3d/aranea-spider.glb", import.meta.url))
  const model = JSON.parse(glb.subarray(20, 20 + glb.readUInt32LE(12)).toString())
  const positions = model.meshes.flatMap((mesh) =>
    mesh.primitives.map((p) => model.accessors[p.attributes.POSITION])
  )
  // GLB mesh bounds plus 0.18 world units for the walking leg excursion.
  const lower = [0, 1, 2].map(
    (axis) => Math.min(...positions.map((p) => p.min[axis])) * 0.65 - 0.18
  )
  const upper = [0, 1, 2].map(
    (axis) => Math.max(...positions.map((p) => p.max[axis])) * 0.65 + 0.18
  )
  const normalize = (v) => v.map((n) => n / Math.hypot(...v))
  const dot = (a, b) => a.reduce((sum, n, i) => sum + n * b[i], 0)
  const halfHeight = Math.tan((24 * Math.PI) / 180)
  for (const aspect of [16 / 9, 16 / 10, 4 / 3]) {
    for (let time = 0; time < 120; time += 0.25) {
      const state = motion.weaver(time)
      const forward = normalize(state.target.map((n, i) => n - state.camera[i]))
      const right = normalize([-forward[2], 0, forward[0]])
      const up = [
        -right[2] * forward[1],
        right[2] * forward[0] - right[0] * forward[2],
        right[0] * forward[1]
      ]
      const c = Math.cos(state.heading),
        s = Math.sin(state.heading)
      for (const x of [lower[0], upper[0]])
        for (const y of [lower[1], upper[1]])
          for (const z of [lower[2], upper[2]]) {
            const offset = [
              c * x + s * z + state.position[0] - state.camera[0],
              y + state.position[1] - 0.065 - state.camera[1],
              -s * x + c * z + state.position[2] - state.camera[2]
            ]
            const depth = dot(offset, forward)
            const screenX = dot(offset, right) / (depth * halfHeight * aspect)
            const screenY = dot(offset, up) / (depth * halfHeight)
            assert.ok(
              Math.abs(screenX) < 0.96 && Math.abs(screenY) < 0.96 && depth > 0.1 && depth < 150,
              `model clips at t=${time}, aspect=${aspect}: ${screenX},${screenY},${depth}`
            )
          }
    }
  }
})
