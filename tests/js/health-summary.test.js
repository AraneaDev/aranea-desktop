const assert = require("node:assert/strict")
const test = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

/** Copies QML script values into this realm for structural assertions. */
function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

test("unavailable health takes precedence over stale healthy status and issues", () => {
  const logic = loadPragma("plugins/araneadev.health/HealthSummaryLogic.js")
  assert.deepEqual(plain(logic.summaryFor(false, "healthy", [])), {
    label: "Health data unavailable",
    tone: "unavailable"
  })
  assert.equal(logic.summaryFor(false, "critical", [{ urgency: 2 }]).tone, "unavailable")
  assert.equal(logic.resourceSummary(null).cpu, null)
})

test("health summary counts issues and retains severity", () => {
  const logic = loadPragma("plugins/araneadev.health/HealthSummaryLogic.js")
  assert.deepEqual(plain(logic.summaryFor(true, "healthy", [])), {
    label: "No detected problems",
    tone: "healthy"
  })
  assert.deepEqual(plain(logic.summaryFor(true, "attention", [{}])), {
    label: "1 issue needs attention",
    tone: "attention"
  })
  assert.deepEqual(plain(logic.summaryFor(true, "critical", [{}, {}])), {
    label: "2 issues need attention",
    tone: "critical"
  })
})

test("unknown resource values stay null and the fullest valid disk wins", () => {
  const logic = loadPragma("plugins/araneadev.health/HealthSummaryLogic.js")
  assert.deepEqual(
    plain(
      logic.resourceSummary({
        cpu: null,
        mem: { memUsed: null, memTotal: 100 },
        diskRows: [{ target: "/", percent: null }]
      })
    ),
    {
      cpu: null,
      memory: null,
      disk: null
    }
  )
  assert.deepEqual(
    plain(
      logic.resourceSummary({
        cpu: 0,
        mem: { memUsed: 0, memTotal: 100 },
        diskRows: [
          { target: "/bad", percent: "oops" },
          { target: "/", percent: 20 },
          { target: "/boot", percent: 80 },
          { target: "/invalid", percent: 110 }
        ]
      })
    ),
    { cpu: 0, memory: { used: 0, total: 100 }, disk: { target: "/boot", percent: 80 } }
  )
  for (const value of [undefined, "", " ", false, [], {}, NaN, Infinity, -1, 101])
    assert.equal(logic.resourceSummary({ cpu: value }).cpu, null)
  assert.equal(logic.resourceSummary({ mem: { memUsed: 5, memTotal: 0 } }).memory, null)
})

test("keyed stops keep problems ahead of disclosures and first press only reveals", () => {
  const logic = loadPragma("plugins/araneadev.health/HealthSummaryLogic.js")
  const health = require("../../plugins/araneadev.health/HealthLogic.js")
  const stops = logic.keyboardStops([{ key: "disk:/" }, { key: "unit:web" }])
  assert.deepEqual(
    plain(stops).map((row) => row.key),
    ["disk:/", "unit:web", "details:resources", "details:processes"]
  )
  assert.equal(health.cursorPress(stops, "", false).row, null)
  assert.equal(health.cursorMove(stops, "unit:web", true, 1).key, "details:resources")
  assert.equal(health.cursorMove(stops, "details:resources", true, 1).key, "details:processes")
  const empty = logic.keyboardStops([])
  assert.equal(health.cursorPress(empty, "", false).key, "details:resources")
  assert.equal(health.cursorPress(empty, "details:resources", true).row.key, "details:resources")
})
