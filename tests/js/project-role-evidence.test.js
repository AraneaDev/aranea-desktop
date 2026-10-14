const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { loadPragma } = require("./lib/load-pragma.js")
const modulePath = "plugins/araneadev.projects/ProjectRoleEvidence.js"
const plain = (value) => JSON.parse(JSON.stringify(value))
const operation = {
  projectId: "p-1",
  checkoutId: "c-1",
  sessionId: "s-1",
  generation: 2,
  state: "launching"
}
const binding = {
  projectId: "p-1",
  checkoutId: "c-1",
  role: "editor",
  sessionId: "s-1",
  address: "0xa",
  pid: 42,
  appId: "editor-token",
  evidence: { mode: "process-app-id", processVerified: true, startTime: "100" }
}
const window = { address: "0xa", pid: 42, appId: "editor-token" }
/** Build explicit owner snapshots for the behavior under test. */
function context(changes = {}) {
  return {
    operation: { ...operation },
    role: "editor",
    sessionId: "s-1",
    bindings: [],
    roleHistory: {},
    proof: { bindings: [], missing: [] },
    ownershipHolds: {},
    launchAttempts: [],
    windows: [window],
    ...changes
  }
}
/** Load the actual pure module and give the missing API an assertion failure. */
function policy() {
  assert.ok(
    fs.existsSync(path.resolve(__dirname, "../..", modulePath)),
    "pure role evidence module must exist"
  )
  return loadPragma(modulePath)
}
/** Resolve the public decision from real selected evidence. */
function decision(ctx) {
  const logic = policy()
  return plain(logic.resolveRoleDecision(ctx, logic.selectRoleEvidence(ctx)))
}
/** Provide hand-checked exact closure evidence for one owned identity. */
function closed(owned = binding) {
  return {
    binding: owned,
    identity: { pid: owned.pid, address: owned.address, startTime: owned.evidence.startTime }
  }
}
/** Provide retained observed history under a literal legacy ownership key. */
function observed(owned = binding) {
  return { "p-1\nc-1\neditor": { status: "observed", binding: owned } }
}

// Catches preferring retained identities to freshly verified ownership.
test("fresh ownership wins over retained history and focuses", () => {
  const fresh = { ...binding, address: "0xb", pid: 43 }
  const ctx = context({
    bindings: [binding],
    roleHistory: observed(),
    proof: { bindings: [fresh], missing: [] },
    windows: [{ ...window, address: "0xb", pid: 43 }]
  })
  assert.deepEqual(plain(policy().selectRoleEvidence(ctx)), {
    prior: observed()["p-1\nc-1\neditor"],
    fresh,
    binding: fresh,
    disposition: null
  })
  assert.deepEqual(decision(ctx), { action: "focus", code: null })
})
// Catches stale processVerified flags being treated as fresh proof.
test("retained ownership cannot focus from stale verified flags", () => {
  const ctx = context({ bindings: [binding], roleHistory: observed() })
  assert.deepEqual(decision(ctx), { action: "hold", code: "OWNERSHIP_UNCONFIRMED" })
})
// Catches selection order changing when multiple owned copies survive.
test("history identity precedes first retained copy and fresh proof preserves first match", () => {
  const other = { ...binding, address: "0xb", pid: 43 }
  const ctx = context({ bindings: [other, binding], roleHistory: observed() })
  assert.equal(policy().selectRoleEvidence(ctx).binding.address, "0xa")
  assert.equal(
    policy().selectRoleEvidence(context({ bindings: [other, binding] })).binding.address,
    "0xb"
  )
  assert.equal(
    policy().selectRoleEvidence(context({ proof: { bindings: [other, binding], missing: [] } }))
      .fresh.address,
    "0xb"
  )
})
// Catches launching on mere absence instead of positive closure of all copies.
test("exact closure of every owned copy permits ordinary resume", () => {
  const other = {
    ...binding,
    address: "0xb",
    pid: 43,
    evidence: { ...binding.evidence, startTime: "101" }
  }
  const ctx = context({
    bindings: [other, binding],
    roleHistory: observed(),
    proof: { bindings: [], missing: [closed(other), closed()] },
    windows: []
  })
  assert.deepEqual(plain(policy().selectRoleEvidence(ctx).disposition), {
    state: "confirmed-missing",
    verified: true,
    projectId: "p-1",
    checkoutId: "c-1",
    environmentId: null,
    role: "editor",
    sessionId: "s-1",
    generation: 2,
    identity: { pid: 42, address: "0xa", startTime: "100" }
  })
  assert.deepEqual(decision(ctx), { action: "launch", code: null })
})
// Catches accepting one closure while another accepted copy remains uncertain.
test("mixed closed and uncertain copies hold ordinary resume", () => {
  const other = { ...binding, address: "0xb", pid: 43 }
  const ctx = context({
    bindings: [binding, other],
    roleHistory: observed(),
    proof: { bindings: [], missing: [closed()] },
    windows: []
  })
  assert.equal(policy().selectRoleEvidence(ctx).disposition, null)
  assert.deepEqual(decision(ctx), { action: "hold", code: "OWNERSHIP_UNCONFIRMED" })
})
for (const [name, change] of [
  ["start time", { identity: { pid: 42, address: "0xa", startTime: "999" } }],
  ["address", { binding: { ...binding, address: "0xb" } }],
  ["process", { binding: { ...binding, pid: 99 } }],
  ["session", { binding: { ...binding, sessionId: "old" } }],
  ["environment", { binding: { ...binding, environmentId: "other" } }]
]) {
  test(`closure with wrong ${name} cannot authorize a launch`, () => {
    const ctx = context({
      bindings: [binding],
      roleHistory: observed(),
      proof: { bindings: [], missing: [{ ...closed(), ...change }] },
      windows: []
    })
    assert.deepEqual(decision(ctx), { action: "hold", code: "OWNERSHIP_UNCONFIRMED" })
  })
}
// Catches evidence from another ownership scope entering selection.
for (const [name, change] of [
  ["project", { projectId: "other" }],
  ["checkout", { checkoutId: "other" }],
  ["role", { role: "terminal" }],
  ["session", { sessionId: "old" }],
  ["environment", { environmentId: "other" }]
]) {
  test(`retained and fresh ${name} mismatches are excluded`, () => {
    const unrelated = { ...binding, ...change }
    const ctx = context({ bindings: [unrelated], proof: { bindings: [unrelated], missing: [] } })
    assert.deepEqual(plain(policy().selectRoleEvidence(ctx)), {
      prior: null,
      fresh: null,
      binding: null,
      disposition: null
    })
    assert.deepEqual(decision(ctx), { action: "launch", code: null })
  })
}
test("prepared environment history stays isolated from legacy and sibling environments", () => {
  const own = { ...binding, environmentId: "env-a" }
  const ctx = context({
    operation: { ...operation, environmentId: "env-a" },
    bindings: [binding, { ...own, environmentId: "env-b" }, own],
    roleHistory: {
      ...observed(),
      "env-b\neditor": { status: "failed" },
      "env-a\neditor": { status: "observed", binding: own }
    }
  })
  assert.deepEqual(plain(policy().selectRoleEvidence(ctx)), {
    prior: { status: "observed", binding: own },
    fresh: null,
    binding: own,
    disposition: null
  })
  assert.deepEqual(decision(ctx), { action: "hold", code: "OWNERSHIP_UNCONFIRMED" })
})
// Catches only inspecting the latest attempt after a newer explicit failure.
for (const state of ["submitted", "accepted"]) {
  test(`older ${state} launch blocks retry after a newer failed attempt`, () => {
    const ctx = context({
      operation: { ...operation, retryRole: "editor" },
      roleHistory: { "p-1\nc-1\neditor": { status: "failed" } },
      launchAttempts: [
        { ...binding, state },
        { ...binding, state: "failed" }
      ]
    })
    assert.deepEqual(decision(ctx), { action: "hold", code: "OWNERSHIP_UNCONFIRMED" })
  })
}
test("unrelated and settled attempts do not block a failed-role retry", () => {
  const attempts = [
    { ...binding, state: "failed" },
    { ...binding, state: "observed" },
    { ...binding, state: "accepted", sessionId: "old" },
    { ...binding, state: "accepted", environmentId: "other" },
    { ...binding, state: "accepted", projectId: "other" },
    { ...binding, state: "accepted", checkoutId: "other" },
    { ...binding, state: "accepted", role: "terminal" }
  ]
  assert.deepEqual(
    decision(
      context({
        operation: { ...operation, retryRole: "editor" },
        roleHistory: { "p-1\nc-1\neditor": { status: "failed" } },
        launchAttempts: attempts
      })
    ),
    { action: "launch", code: null }
  )
})
test("ownership hold blocks ordinary open but explicit new window bypasses every retained guard", () => {
  const ctx = context({
    ownershipHolds: { "p-1\nc-1\neditor": true },
    launchAttempts: [{ ...binding, state: "accepted" }]
  })
  assert.deepEqual(decision(ctx), { action: "hold", code: "OWNERSHIP_UNCONFIRMED" })
  assert.deepEqual(decision({ ...ctx, operation: { ...operation, newWindowRole: "editor" } }), {
    action: "launch",
    code: null
  })
})
test("retry targets skip siblings and launch only a known failed role", () => {
  assert.deepEqual(
    decision(
      context({ operation: { ...operation, retryRole: "terminal", newWindowRole: "editor" } })
    ),
    { action: "skip", code: null }
  )
  assert.deepEqual(decision(context({ operation: { ...operation, retryRole: "editor" } })), {
    action: "hold",
    code: "RETRY_NOT_FAILED"
  })
  assert.deepEqual(
    decision(
      context({
        operation: { ...operation, retryRole: "editor" },
        roleHistory: observed(),
        bindings: [binding],
        proof: { bindings: [], missing: [closed()] }
      })
    ),
    { action: "hold", code: "OWNERSHIP_UNCONFIRMED" }
  )
})
test("selection and decisions leave nested input evidence unchanged", () => {
  const ctx = context({
    bindings: [binding],
    roleHistory: observed(),
    proof: { bindings: [], missing: [closed()] },
    launchAttempts: [{ ...binding, state: "failed" }]
  })
  const before = plain(ctx)
  /** Freeze every input layer so accidental writes cannot alter the fixture. */
  function freeze(value) {
    if (value && typeof value === "object") {
      Object.values(value).forEach(freeze)
      Object.freeze(value)
    }
    return value
  }
  assert.deepEqual(decision(freeze(ctx)), { action: "launch", code: null })
  assert.deepEqual(plain(ctx), before)
})
