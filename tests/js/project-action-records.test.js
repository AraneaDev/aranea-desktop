const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const Records = loadPragma("plugins/araneadev.projects/ProjectActionRecords.js")
test("process result and independent preview evidence never claim agent verification", () => {
  assert.equal(
    Records.runLabel({ processState: "running", readiness: "unknown" }),
    "Running · Preview not checked"
  )
  assert.equal(
    Records.runLabel({ processState: "unconfirmed", readiness: "reachable" }),
    "Unconfirmed · Previous preview reachability"
  )
  assert.equal(
    Records.runLabel({
      processState: "succeeded",
      readiness: "unknown",
      submissionUnconfirmed: true,
      exitCode: 0
    }),
    "Command succeeded · Cleanup unconfirmed · Preview not checked"
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
