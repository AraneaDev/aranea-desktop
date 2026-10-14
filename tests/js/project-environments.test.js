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
test("allocation excludes live occupancy, legacy, retained and queued reservations", () => {
  assert.equal(typeof env.chooseEmptyWorkspace, "function")
  assert.equal(
    env.chooseEmptyWorkspace(
      [
        { id: 1, windows: 1 },
        { id: 5, windows: 0 }
      ],
      [{ workspaceId: 2 }],
      [{ workspaceId: 3 }],
      [{ workspaceId: 4 }]
    ),
    5
  )
  assert.equal(
    env.chooseEmptyWorkspace(
      [
        { id: 1, windows: [] },
        { id: -1, windows: [1] }
      ],
      [],
      [],
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
    assert.equal(env.chooseEmptyWorkspace(unknown, [], [], []), null)
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
