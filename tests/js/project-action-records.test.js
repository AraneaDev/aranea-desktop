const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const Records = loadPragma("plugins/araneadev.projects/ProjectActionRecords.js")
const plain = (value) => JSON.parse(JSON.stringify(value))

test("run ordering and protection stay scoped to the exact project, checkout and action", () => {
  const state = {
    definitions: [
      { id: "a-1", projectId: "p-1", revision: 3 },
      { id: "a-other", projectId: "p-2", revision: 1 }
    ],
    runs: [
      {
        id: "r-old",
        projectId: "p-1",
        checkoutId: "c-1",
        actionId: "a-1",
        createdAt: 10,
        processState: "running"
      },
      {
        id: "r-new",
        projectId: "p-1",
        checkoutId: "c-1",
        actionId: "a-1",
        createdAt: 30,
        processState: "succeeded",
        submissionUnconfirmed: true
      },
      {
        id: "r-other-checkout",
        projectId: "p-1",
        checkoutId: "c-2",
        actionId: "a-1",
        createdAt: 40,
        processState: "running"
      },
      {
        id: "r-finished",
        projectId: "p-1",
        checkoutId: "c-1",
        actionId: "a-1",
        createdAt: 50,
        processState: "stopped"
      },
      {
        id: "r-other-project",
        projectId: "p-2",
        checkoutId: "c-1",
        actionId: "a-1",
        createdAt: 60,
        processState: "running"
      }
    ]
  }
  const before = structuredClone(state)
  assert.deepEqual(plain(Records.runs(state, "p-1", "c-1").map((run) => run.id)), [
    "r-finished",
    "r-new",
    "r-old"
  ])
  assert.deepEqual(plain(Records.runs(state, "p-1", "").map((run) => run.id)), [
    "r-finished",
    "r-other-checkout",
    "r-new",
    "r-old"
  ])
  assert.equal(Records.activeRun(state, "p-1", "c-1", "a-1").id, "r-new")
  assert.equal(Records.activeRun(state, "p-1", "c-1", "a-missing"), null)
  assert.deepEqual(plain(Records.definitions(state, "p-1")), [
    { id: "a-1", projectId: "p-1", revision: 3 }
  ])
  assert.deepEqual(state, before, "projections do not reorder or mutate backend observations")
})

test("only live protected processes or cleanup uncertainty block replacement", () => {
  assert.equal(Records.protectedRun(null), false)
  for (const state of ["pending", "running", "unconfirmed"])
    assert.equal(Records.protectedRun({ processState: state }), true, state)
  for (const state of ["succeeded", "failed", "stopped"])
    assert.equal(Records.protectedRun({ processState: state }), false, state)
})

test("preview eligibility requires a live confirmed service with pinned invocation and URL", () => {
  const run = {
    processState: "running",
    submissionUnconfirmed: false,
    invocationId: "invocation-one",
    definitionSnapshot: { kind: "service", previewUrl: "http://127.0.0.1:8080" }
  }
  assert.equal(Records.canOpenPreview(run), true)
  for (const change of [
    { processState: "succeeded" },
    { submissionUnconfirmed: true },
    { invocationId: "" },
    { definitionSnapshot: null },
    { definitionSnapshot: { kind: "command", previewUrl: "http://127.0.0.1:8080" } },
    { definitionSnapshot: { kind: "service", previewUrl: "" } }
  ])
    assert.equal(Records.canOpenPreview({ ...run, ...change }), false, JSON.stringify(change))
  assert.equal(Records.canOpenPreview(null), false)
})

test("preview failures remain independent from terminal command outcomes", () => {
  for (const [run, expected] of [
    [null, "No run"],
    [{ processState: "running", readiness: "reachable" }, "Running · Preview reachable"],
    [{ processState: "running", readiness: "unreachable" }, "Running · Preview unreachable"],
    [
      { processState: "running", readiness: "unreachable", submissionUnconfirmed: true },
      "Running · Previous preview unreachable"
    ],
    [
      { processState: "succeeded", readiness: "unreachable" },
      "Command succeeded · Previous preview unreachable"
    ],
    [
      { processState: "failed", readiness: "reachable" },
      "Command failed · Previous preview reachability"
    ],
    [{ processState: "stopped", readiness: "unknown" }, "Stopped · Preview not checked"],
    [{ processState: "unknown", readiness: "unknown" }, "Not available · Preview not checked"]
  ])
    assert.equal(Records.runLabel(run), expected)
})
test("process result and independent preview evidence never claim agent verification", () => {
  assert.equal(
    Records.runLabel({ processState: "running", readiness: "unknown" }),
    "Running · Preview not checked"
  )
  assert.equal(
    Records.runLabel({ processState: "unconfirmed", readiness: "reachable" }),
    "Not confirmed · Previous preview reachability"
  )
  assert.equal(
    Records.runLabel({
      processState: "succeeded",
      readiness: "unknown",
      submissionUnconfirmed: true,
      exitCode: 0
    }),
    "Command succeeded · Cleanup not confirmed · Preview not checked"
  )
  assert.equal(
    Records.protectedRun({ processState: "succeeded", submissionUnconfirmed: true }),
    true
  )
  assert.equal(
    Records.protectedRun({ processState: "succeeded", submissionUnconfirmed: false }),
    false
  )
})
test("rows and eligibility retain exact checkout and immutable definition identity", () => {
  const state = {
    definitions: [{ id: "a-1", projectId: "p-1", revision: 2 }],
    runs: [
      {
        id: "r-1",
        projectId: "p-1",
        checkoutId: "c-1",
        actionId: "a-1",
        definitionRevision: 1,
        processState: "succeeded",
        submissionUnconfirmed: true
      },
      { id: "r-2", projectId: "p-1", checkoutId: "c-2", actionId: "a-1", processState: "running" }
    ]
  }
  assert.equal(Records.activeRun(state, "p-1", "c-1", "a-1").id, "r-1")
  assert.equal(Records.definitions(state, "p-1")[0].revision, 2)
  assert.equal(Records.runs(state, "p-1", "c-1").length, 1)
  assert.equal(
    Records.canOpenPreview({
      processState: "running",
      submissionUnconfirmed: false,
      invocationId: "11111111111111111111111111111111",
      definitionSnapshot: { kind: "service", previewUrl: "http://127.0.0.1:8080" }
    }),
    true
  )
  assert.equal(
    Records.canOpenPreview({
      processState: "unconfirmed",
      definitionSnapshot: { kind: "service", previewUrl: "http://127.0.0.1:8080" }
    }),
    false
  )
})
