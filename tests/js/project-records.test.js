const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const records = loadPragma("plugins/araneadev.projects/ProjectRecords.js")
const project = (id, path) => ({
  id,
  name: "Duplicate",
  lastCheckoutId: "c-" + id,
  checkouts: [{ id: "c-" + id, path, branch: "main", primary: true }]
})
test("project search identities are opaque while duplicate names retain location", () => {
  const result = records.records(
    { projects: [project("p-1", "/tmp/a"), project("p-2", "/tmp/b"), project("p-1", "/tmp/c")] },
    { availability: { compositor: true }, sessionId: "s-1", bindings: [] }
  )
  assert.equal(result.length, 2)
  assert.equal(result[0].key, "project:p-1")
  assert.equal(result[0].type, "project")
  assert.equal(result[0].target.projectId, "p-1")
  assert.equal(result[0].target.checkoutId, "c-p-1")
  assert.match(result[0].detail, /\/tmp\/a/)
  assert.match(result[1].detail, /\/tmp\/b/)
  assert.equal(result[0].action, "open")
})
test("lost selected checkouts stay visible with exact target and unavailable status", () => {
  const p = { ...project("p-1", "/tmp/a"), lastCheckoutId: "missing" }
  const row = records.records({ projects: [p] }, { availability: { compositor: true } })[0]
  assert.equal(row.available, false)
  assert.equal(row.target.checkoutId, "missing")
  assert.equal(records.records({ projects: [project("p-1", "/tmp/a")] }, {})[0].available, false)
})
test("resume labels require process-validated current-session bindings", () => {
  const binding = {
    projectId: "p-1",
    checkoutId: "c-p-1",
    sessionId: "s-1",
    address: "0xa",
    pid: 42,
    evidence: { mode: "process-only", processVerified: true }
  }
  const runtime = { availability: { compositor: true }, sessionId: "s-1", bindings: [binding] }
  assert.equal(
    records.records({ projects: [project("p-1", "/tmp/a")] }, runtime)[0].action,
    "resume"
  )
  assert.equal(
    records.records({ projects: [project("p-1", "/tmp/a")] }, { ...runtime, sessionId: "s-2" })[0]
      .action,
    "open"
  )
})
