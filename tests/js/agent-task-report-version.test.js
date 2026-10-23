const { test } = require("node:test")
const assert = require("node:assert/strict")
const { execFileSync } = require("node:child_process")
const activity = require("../../plugins/araneadev.activity/ActivityLogic.js")
const tasks = require("../../plugins/araneadev.agents/AgentTasksLogic.js")

const context = { receivedAt: 100, monotonic: 100, bootId: "boot", generatedId: "id" }
const empty = { schemaVersion: 1, revision: 0, sessions: [], tasks: [] }
const producer = { provider: "claude", providerSessionId: "session", producerEpoch: "epoch" }
const initial = {
  taskId: "task",
  cwd: "/checkout",
  reportedState: "working",
  description: "Original"
}
/** Run the real reducer with a fixed clock, independent of timestamp precision.
 * @param {string} operation - reducer entry point
 * @param {any} state - durable state or serialized legacy state
 * @param {any} [request] - mutation request
 * @param {string} [hash] - canonical request fingerprint
 * @returns {Array<any>} reducer output records
 */
function reduce(operation, state, request = null, hash = "a".repeat(64)) {
  return execFileSync(
    "jq",
    [
      "-c",
      "--arg",
      "operation",
      operation,
      "--arg",
      "hash",
      hash,
      "--argjson",
      "activity_context",
      JSON.stringify([context]),
      "--argjson",
      "activity_projects",
      JSON.stringify([{ projects: [] }]),
      "--argjson",
      "activity_request",
      JSON.stringify([request]),
      "-f",
      "scripts/lib/agent-activity.jq"
    ],
    { input: JSON.stringify(state), encoding: "utf8" }
  )
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line))
}
/** Register one initial task through the real transaction boundary.
 * @returns {any} registered durable state
 */
function registered() {
  return reduce("transaction", empty, {
    action: "register",
    args: { ...producer, tasks: [initial] }
  })[0]
}
const report = (sequence, kind, payload) => ({
  action: "report",
  args: {
    schemaVersion: 1,
    ...producer,
    taskId: "task",
    eventId: "event-" + sequence,
    sequence,
    kind,
    payload
  }
})

test("distinct same-second reports invalidate old details through full and preview projections", () => {
  let state = registered()
  const versions = new Set()
  for (const [index, [kind, payload]] of [
    ["working", { description: "Updated" }],
    ["diagnostic", { summary: "Diagnostic" }],
    ["verification", { status: "reported-pass", summary: "Tests", commands: ["make"] }],
    ["needs-input", { blockerId: "b", question: "Question?" }],
    ["blocker-resolved", { blockerId: "b", summary: "Resolved" }],
    ["finished", { result: "Result" }],
    ["snapshot", { cwd: "/checkout", reportedState: "working", description: "Replaced" }]
  ].entries()) {
    const oldDetail = activity.boundTask(state.tasks[0])
    versions.add(oldDetail.reportVersion)
    const sequence = kind === "snapshot" ? 9007199254740991 : index + 1
    const request = report(sequence, kind, payload)
    const [next, response] = reduce("transaction", state, request, String(index + 1).repeat(64))
    const detail = activity.boundTask(response.state.tasks[0])
    const listed = activity.expandPreview(activity.previewTask(detail))
    assert.equal(detail.lastReceivedAt, 100)
    assert.ok(typeof detail.reportVersion === "string" && detail.reportVersion.length > 0)
    assert.ok(!versions.has(detail.reportVersion), "every accepted report gets a new identity")
    assert.equal(listed.reportVersion, detail.reportVersion)
    assert.equal(tasks.withDetails(listed, oldDetail), listed, "prior content stays rejected")
    assert.equal(tasks.withDetails(listed, detail).preview, undefined)
    assert.deepEqual(
      reduce("transaction", next, request, String(index + 1).repeat(64))[0],
      next,
      "replay preserves identity"
    )
    state = next
  }
})

test("legacy stored rows project stable identity and invalidate it after an accepted report", () => {
  const legacy = registered()
  delete legacy.tasks[0].reportVersion
  const [loaded] = reduce("load", JSON.stringify(legacy))
  assert.deepEqual(loaded, legacy, "old state stays valid without rewriting it")
  const old = reduce("project", legacy)[0].tasks[0]
  const owner = activity.project(legacy, 100000, null).tasks[0]
  assert.ok(typeof owner.reportVersion === "string" && owner.reportVersion.length > 0)
  assert.equal(owner.reportVersion, old.reportVersion, "owner and store agree on legacy identity")
  assert.ok(typeof old.reportVersion === "string" && old.reportVersion.length > 0)
  assert.equal(reduce("project", legacy)[0].tasks[0].reportVersion, old.reportVersion)
  const [, response] = reduce(
    "transaction",
    legacy,
    report(1, "working", { description: "New" }),
    "b".repeat(64)
  )
  const listed = activity.expandPreview(activity.previewTask(response.state.tasks[0]))
  assert.equal(tasks.withDetails(listed, old), listed)
  assert.equal(tasks.withDetails(activity.previewTask(old), old).description, "Original")
})
