// Logic contract for the shared traffic-graph rules (GraphLogic.js), moved
// from NetworkLogic.js so araneadev.vpn can reuse them. Run with
// `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.shared/GraphLogic.js"))

// --- pushSample ------------------------------------------------------------

test("pushSample starts fresh, appends, trims at max, and never mutates its input", () => {
  const empty = []
  const first = logic.pushSample(empty, { iface: "wlp2s0", rx: 1, tx: 2 }, 3)
  assert.deepEqual(first, [{ iface: "wlp2s0", rx: 1, tx: 2 }])
  assert.deepEqual(empty, [])

  const second = logic.pushSample(first, { iface: "wlp2s0", rx: 2, tx: 3 }, 3)
  assert.deepEqual(second, [
    { iface: "wlp2s0", rx: 1, tx: 2 },
    { iface: "wlp2s0", rx: 2, tx: 3 }
  ])
  assert.deepEqual(first, [{ iface: "wlp2s0", rx: 1, tx: 2 }])

  const third = logic.pushSample(second, { iface: "wlp2s0", rx: 3, tx: 4 }, 2)
  assert.deepEqual(third, [
    { iface: "wlp2s0", rx: 2, tx: 3 },
    { iface: "wlp2s0", rx: 3, tx: 4 }
  ])
  assert.deepEqual(second.length, 2)

  const switched = logic.pushSample(third, { iface: "enp3s0", rx: 9, tx: 9 }, 2)
  assert.deepEqual(switched, [{ iface: "enp3s0", rx: 9, tx: 9 }])
})

// --- graphPoints -----------------------------------------------------------

test("graphPoints at idle sits on the baseline", () => {
  const samples = [
    { iface: "wlp2s0", rx: 0, tx: 0 },
    { iface: "wlp2s0", rx: 0, tx: 0 }
  ]
  const points = logic.graphPoints(samples, 2, 100, 50, 10)
  assert.equal(points.scale, 10)
  assert.ok(points.rx.every((p) => p.y === 50))
  assert.ok(points.tx.every((p) => p.y === 50))
})

test("graphPoints at a peak touches the top", () => {
  const samples = [
    { iface: "wlp2s0", rx: 0, tx: 0 },
    { iface: "wlp2s0", rx: 100, tx: 0 }
  ]
  const points = logic.graphPoints(samples, 2, 100, 50, 10)
  assert.equal(points.scale, 100)
  assert.equal(points.rx[1].y, 0)
  assert.equal(points.rx[0].y, 50)
})

test("graphPoints uses the floor when every sample is below it", () => {
  const samples = [{ iface: "wlp2s0", rx: 1, tx: 1 }]
  const points = logic.graphPoints(samples, 4, 100, 50, 1000)
  assert.equal(points.scale, 1000)
})

test("graphPoints treats negative values as 0 and places the newest sample at x === width", () => {
  const samples = [
    { iface: "wlp2s0", rx: -5, tx: -5 },
    { iface: "wlp2s0", rx: 5, tx: 5 },
    { iface: "wlp2s0", rx: 10, tx: 0 }
  ]
  const points = logic.graphPoints(samples, 3, 90, 50, 1)
  assert.equal(points.rx[0].y, 50)
  assert.equal(points.rx[2].x, 90)
  assert.equal(points.rx[0].x, 90 - 2 * (90 / 2))
})

test("graphPoints treats slots below 2 as 2", () => {
  const samples = [
    { iface: "wlp2s0", rx: 1, tx: 1 },
    { iface: "wlp2s0", rx: 2, tx: 2 }
  ]
  const points = logic.graphPoints(samples, 1, 10, 10, 1)
  assert.equal(points.rx[1].x, 10)
  assert.equal(points.rx[0].x, 0)
})

test("graphPoints on empty samples returns {rx: [], tx: [], scale: floor}", () => {
  assert.deepEqual(logic.graphPoints([], 4, 100, 50, 7), { rx: [], tx: [], scale: 7 })
  assert.deepEqual(logic.graphPoints(undefined, 4, 100, 50, 7), { rx: [], tx: [], scale: 7 })
})

test("graphPoints never throws on a null array element, reading it as rx/tx 0", () => {
  assert.deepEqual(logic.graphPoints([null], 2, 100, 50, 1), {
    rx: [{ x: 100, y: 50 }],
    tx: [{ x: 100, y: 50 }],
    scale: 1
  })
})
