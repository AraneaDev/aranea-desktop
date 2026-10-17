const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const r = loadPragma("plugins/araneadev.projects/ProjectReview.js")
const { BANNED } = loadPragma("plugins/araneadev.projects/ProjectProblems.js")

const task = (state, at, extra) =>
  Object.assign(
    {
      taskId: "t" + at,
      reportedState: state,
      lastReceivedAt: at,
      verification: { status: "unknown" },
      association: { status: "registered", projectId: "p", checkoutId: "c1" }
    },
    extra || {}
  )
const co = (extra) => Object.assign({ id: "c1", primary: false }, extra)

test("tasksFor keeps matching registered tasks sorted ascending", () => {
  const other = task("finished", 5, {
    association: { status: "registered", projectId: "p", checkoutId: "c2" }
  })
  const unav = task("finished", 6, {
    association: { status: "unavailable", projectId: "p", checkoutId: "c1" }
  })
  const out = r.tasksFor([task("finished", 9), other, unav, task("working", 3)], "p", "c1")
  assert.deepEqual(
    out.map((t) => t.lastReceivedAt),
    [3, 9]
  )
})

test("none for primary, no tasks and unavailable association", () => {
  assert.equal(r.reviewState(co({ primary: true }), [task("finished", 1)], null), "none")
  assert.equal(r.reviewState(co(), [], null), "none")
  const t = task("finished", 1, {
    association: { status: "unavailable", projectId: "p", checkoutId: "c1" }
  })
  assert.equal(r.reviewState(co(), [t], null), "none")
})

test("task states", () => {
  assert.equal(r.reviewState(co(), [task("working", 1)], null), "working")
  assert.equal(r.reviewState(co(), [task("needs-input", 1)], null), "needsInput")
  for (const s of ["finished", "ready-for-review", "failed"])
    assert.equal(r.reviewState(co(), [task(s, 1)], null), "ready")
  assert.equal(r.reviewState(co(), [task("finished", 1), task("working", 2)], null), "working")
})

test("marks", () => {
  const mark = { reviewedHead: "a".repeat(40), reviewedTaskAt: 5, reviewedAt: 9 }
  const rev = { head: "a".repeat(40) }
  assert.equal(r.reviewState(co({ review: mark }), [task("finished", 5)], rev), "reviewed")
  assert.equal(
    r.reviewState(co({ review: mark }), [task("finished", 5)], { head: "b".repeat(40) }),
    "ready"
  )
  assert.equal(r.reviewState(co({ review: mark }), [task("finished", 6)], rev), "ready")
  assert.equal(r.reviewState(co({ review: mark }), [task("finished", 5)], null), "reviewed")
  assert.equal(r.reviewState(co({ review: mark }), [task("finished", 6)], null), "ready")
})

test("projectHasReview", () => {
  const tasks = [task("finished", 1)]
  const project = { id: "p", checkouts: [{ id: "c1", primary: false }] }
  assert.equal(r.projectHasReview(project, tasks, {}), true)
  assert.equal(
    r.projectHasReview({ id: "p", checkouts: [{ id: "c1", primary: true }] }, tasks, {}),
    false
  )
  assert.equal(
    r.projectHasReview({ id: "p", checkouts: [{ id: "c9", primary: false }] }, tasks, {}),
    false
  )
})

test("latestFinished", () => {
  assert.equal(r.latestFinished([task("working", 1)]), null)
  assert.equal(
    r.latestFinished([task("finished", 1), task("failed", 3), task("working", 4)]).lastReceivedAt,
    3
  )
})

test("checksAction", () => {
  const defs = [
    { id: "1", projectId: "p", name: "Build", kind: "command" },
    { id: "2", projectId: "p", name: "test server", kind: "service" },
    { id: "3", projectId: "p", name: "Run tests", kind: "command" },
    { id: "4", projectId: "p", name: "Check", kind: "command" }
  ]
  assert.equal(r.checksAction(defs, "p").id, "3")
  assert.equal(r.checksAction(defs.slice(0, 2), "p"), null)
  assert.equal(r.checksAction(defs, "q"), null)
})

test("labels", () => {
  assert.equal(r.checksLabel(null), "not run")
  assert.equal(r.checksLabel({ processState: "succeeded" }), "passed")
  assert.equal(r.checksLabel({ processState: "failed" }), "failed")
  assert.equal(r.checksLabel({ processState: "running" }), "running")
  assert.equal(r.checksLabel({ processState: "pending" }), "running")
  assert.equal(r.checksLabel({ processState: "stopped" }), "not run")
  assert.equal(
    r.agentReportLabel(task("finished", 1, { verification: { status: "reported-pass" } })),
    "passed"
  )
  assert.equal(
    r.agentReportLabel(task("finished", 1, { verification: { status: "reported-fail" } })),
    "failed"
  )
  assert.equal(r.agentReportLabel(task("finished", 1)), "not reported")
  assert.equal(r.agentReportLabel(null), "not reported")
})

test("changesLine", () => {
  const rv = (c, f) => ({ commits: new Array(c).fill({}), files: new Array(f).fill({}) })
  assert.equal(r.changesLine(rv(2, 3)), "2 commits · 3 files")
  assert.equal(r.changesLine(rv(1, 1)), "1 commit · 1 file")
  assert.equal(r.changesLine(null), "")
})

test("labels are plain", () => {
  const all = [
    r.checksLabel(null),
    r.checksLabel({ processState: "failed" }),
    r.agentReportLabel(null),
    r.changesLine({ commits: [{}], files: [{}] })
  ].join(" ")
  for (const w of BANNED) assert.ok(!new RegExp("\\b" + w + "\\b", "i").test(all), w)
  assert.ok(!all.includes(String.fromCharCode(8212)))
})
