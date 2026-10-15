const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const env = loadPragma("plugins/araneadev.projects/ProjectEnvironments.js")
const plain = (value) => JSON.parse(JSON.stringify(value))
test("environment role identities preserve the exact legacy key", () => {
  assert.equal(typeof env.roleKey, "function")
  assert.equal(env.roleKey({ projectId: "p", checkoutId: "c" }, "editor"), "p\nc\neditor")
  assert.notEqual(
    env.roleKey({ environmentId: "e-a" }, "editor"),
    env.roleKey({ environmentId: "e-b" }, "editor")
  )
})
test("allocation excludes live occupancy and in-flight reservations only", () => {
  assert.equal(typeof env.chooseEmptyWorkspace, "function")
  assert.equal(env.chooseEmptyWorkspace.length, 2)
  assert.equal(
    env.chooseEmptyWorkspace(
      [
        { id: 1, windows: 1 },
        { id: 5, windows: 0 }
      ],
      [{ workspaceId: 2 }]
    ),
    3
  )
  // Observed 2026-10-15: saved records on 1-4, windows only on 5.
  assert.equal(env.chooseEmptyWorkspace([{ id: 5, windows: 1 }], []), 1)
  assert.equal(
    env.chooseEmptyWorkspace(
      [
        { id: 1, windows: [] },
        { id: -1, windows: [1] }
      ],
      []
    ),
    1
  )
  for (const unknown of [
    null,
    undefined,
    [{ id: 1 }],
    [{ id: 1, windows: -1 }],
    [{ id: 1, windows: "0" }]
  ])
    assert.equal(env.chooseEmptyWorkspace(unknown, []), null)
})
test("activation coalescing retains completed acceptance but respects session and deliberate activations", () => {
  assert.equal(typeof env.coalesced, "function")
  const first = {
    id: "op",
    environmentId: "e",
    activationId: "a",
    sessionId: "s",
    state: "completed"
  }
  assert.equal(env.coalesced([first], "s", "a"), first)
  assert.equal(env.coalesced([first], "s", "b"), null)
  assert.equal(env.coalesced([first], "old", "a"), null)
  assert.equal(env.coalesced([{ sessionId: "s" }], "s", undefined), null)
})
test("projection requires current exact environment process evidence and never mutates snapshots", () => {
  assert.equal(typeof env.projectRows, "function")
  const saved = ["e-a", "e-b"].map((id) => ({
    id,
    projectId: "p",
    checkoutId: "c",
    sessionId: "s",
    workspaceId: 2,
    profileSnapshot: { roles: ["editor", "terminal"] }
  }))
  const proof = {
    environmentId: "e-a",
    projectId: "p",
    checkoutId: "c",
    sessionId: "s",
    role: "editor",
    pid: 42,
    address: "0xa",
    evidence: { processVerified: true, mode: "process-only" }
  }
  const rows = env.projectRows(saved, [proof], "s")
  assert.equal(rows[0].status, "observed")
  assert.deepEqual(plain(rows[0].observedRoles), ["editor"])
  assert.equal(rows[1].status, "unconfirmed")
  for (const patch of [
    { sessionId: "old" },
    { environmentId: undefined },
    { checkoutId: "elsewhere" },
    { evidence: { processVerified: false } }
  ])
    assert.equal(env.projectRows(saved, [{ ...proof, ...patch }], "s")[0].status, "unconfirmed")
  assert.equal(env.projectRows(saved, [proof], "new")[0].status, "unconfirmed")
  rows[0].profileSnapshot.roles.push("agent")
  assert.deepEqual(saved[0].profileSnapshot.roles, ["editor", "terminal"])
})

test("fresh recovery bindings project an environment created in an older session without rewriting it", () => {
  const saved = {
    id: "e-old",
    projectId: "p",
    checkoutId: "c",
    sessionId: "creation-session",
    workspaceId: 2,
    checkoutSnapshot: { id: "c", path: "/repo", branch: "launch-branch", primary: true },
    profileSnapshot: { id: "f", name: "Original", revision: 1, roles: ["editor"] }
  }
  const original = JSON.stringify(saved)
  const proof = {
    environmentId: "e-old",
    projectId: "p",
    checkoutId: "c",
    sessionId: "recovery-session",
    role: "editor",
    pid: 42,
    address: "0xa",
    evidence: { processVerified: true, mode: "process-only" }
  }
  const observed = env.projectRows([saved], [proof], "recovery-session")[0]
  assert.equal(observed.status, "observed")
  assert.deepEqual(plain(observed.observedRoles), ["editor"])
  assert.equal(observed.sessionId, "creation-session")
  assert.equal(JSON.stringify(saved), original)
  assert.equal(env.projectRows([saved], [], "recovery-session")[0].status, "unconfirmed")
  for (const patch of [
    { sessionId: "creation-session" },
    { environmentId: "e-other" },
    { projectId: "p-other" },
    { checkoutId: "c-other" },
    { role: "unsupported" },
    { pid: 0 },
    { address: "0x0" },
    { evidence: { processVerified: false, mode: "process-only" } },
    { evidence: { processVerified: true, mode: "workspace-only" } }
  ]) {
    const row = env.projectRows([saved], [{ ...proof, ...patch }], "recovery-session")[0]
    assert.equal(row.status, "unconfirmed", JSON.stringify(patch))
    assert.deepEqual(plain(row.observedRoles), [])
  }
  observed.checkoutSnapshot.branch = "mutated-output"
  observed.profileSnapshot.name = "mutated-output"
  assert.equal(JSON.stringify(saved), original)
})
