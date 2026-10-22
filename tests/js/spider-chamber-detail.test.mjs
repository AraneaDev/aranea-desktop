import test from "node:test"
import assert from "node:assert/strict"
import * as events from "../../branding/3d/live/events.mjs"
import * as choreography from "../../branding/3d/live/journey.mjs"

test("chamber transformation follows silk transfers with quiet walking intervals", () => {
  assert.equal(typeof choreography.chamberBeat, "function")
  assert.equal(choreography.chamberBeat(25).resonance, 0)
  assert.equal(choreography.chamberBeat(105).resonance, 0)
  assert.equal(choreography.chamberBeat(65).resonance, 1)
  assert.equal(choreography.chamberBeat(145).resonance, 1)
  for (let t = -160; t < 320; t += 0.1) {
    const a = choreography.chamberBeat(t),
      b = choreography.chamberBeat(t + 0.001)
    assert.ok(a.resonance >= 0 && a.resonance <= 1)
    assert.ok(Math.abs(a.resonance - b.resonance) < 0.001)
    assert.ok(Math.abs(a.resonance - choreography.chamberBeat(t + 160).resonance) < 1e-10)
  }
})

test("bridge carriers remain on the deck edge, move, and reproduce captured time", () => {
  assert.equal(typeof choreography.writeChamberSignals, "function")
  const a = new Float32Array(224 * 3).fill(NaN),
    b = new Float32Array(a.length)
  choreography.writeChamberSignals(a, 20)
  choreography.writeChamberSignals(b, 20)
  assert.deepEqual(a, b)
  for (let i = 0; i < a.length; i += 3) {
    assert.ok(Math.abs(a[i]) > 2 && Math.abs(a[i]) < 2.2)
    assert.ok(Math.abs(a[i + 1] - 6.06) < 0.001 || Math.abs(a[i + 1] + 2.94) < 0.001)
    assert.ok(a[i + 2] >= -13 && a[i + 2] <= 18)
  }
  choreography.writeChamberSignals(b, 21)
  assert.notDeepEqual(a, b)
})

test("rare event captures match playback regardless of sampling history", () => {
  assert.equal(typeof events.EventTimeline, "function")
  const playback = new events.EventTimeline(),
    capture = new events.EventTimeline()
  let seen = 0
  for (let t = 0; t < 1500; t += 0.5) {
    const event = playback.sample(t)
    if (event) {
      seen++
      assert.ok(event.start <= t && event.start + event.duration > t)
      assert.ok(events.EVENT_KINDS.includes(event.kind))
      assert.equal(playback.sample(t + 0.001), event, "active event identity stays stable")
    }
    if (t % 7 === 0) assert.deepEqual(capture.sample(t), event)
  }
  assert.ok(seen > 100 && seen < 600, "quiet gaps dominate the timeline")
  assert.deepEqual(new events.EventTimeline().sample(44), new events.EventTimeline().sample(44))
})
