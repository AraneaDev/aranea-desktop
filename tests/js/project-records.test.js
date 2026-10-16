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

test("resume never follows another checkout or unverified process/window evidence", () => {
  const binding = {
    projectId: "p-1",
    checkoutId: "c-p-1",
    sessionId: "s-1",
    address: "0xa",
    pid: 42,
    evidence: { mode: "process-app-id", processVerified: true }
  }
  for (const changed of [
    { projectId: "p-2" },
    { checkoutId: "c-other" },
    { sessionId: "s-old" },
    { evidence: null },
    { evidence: { mode: "title", processVerified: true } },
    { evidence: { mode: "process-only", processVerified: false } },
    { pid: 0 },
    { address: null },
    { address: "window-title" },
    { address: "0x000" }
  ]) {
    const row = records.records(
      { projects: [project("p-1", "/tmp/a")] },
      {
        availability: { compositor: true },
        sessionId: "s-1",
        bindings: [{ ...binding, ...changed }]
      }
    )[0]
    assert.equal(row.action, "open", JSON.stringify(changed))
    assert.equal(
      row.target.checkoutId,
      "c-p-1",
      "rejected evidence cannot change the selected checkout"
    )
  }
  assert.equal(
    records.records(
      { projects: [project("p-1", "/tmp/a")] },
      { availability: { compositor: true }, bindings: [binding] }
    )[0].action,
    "open",
    "missing owner session never grants resume"
  )
})

test("branchless and missing checkouts retain honest exact search metadata", () => {
  const branchless = {
    ...project("p-1", "/tmp/a"),
    checkouts: [{ id: "c-p-1", path: "/tmp/a", branch: "" }]
  }
  const missing = { id: "p-2", name: "Missing", lastCheckoutId: "c-gone" }
  const rows = records.records(
    { projects: [null, {}, branchless, missing] },
    { availability: { compositor: false } }
  )
  assert.equal(rows.length, 2)
  assert.equal(rows[0].detail, "/tmp/a")
  assert.deepEqual(JSON.parse(JSON.stringify(rows[0].aliases)), ["/tmp/a", ""])
  assert.equal(rows[0].available, false, "offline compositor cannot advertise an available launch")
  assert.equal(rows[1].detail, "Selected checkout not available")
  assert.deepEqual(JSON.parse(JSON.stringify(rows[1].target)), {
    projectId: "p-2",
    checkoutId: "c-gone"
  })
  assert.deepEqual(JSON.parse(JSON.stringify(rows[1].aliases)), [])
  assert.equal(rows[1].available, false)
  assert.deepEqual(JSON.parse(JSON.stringify(records.records(null, null))), [])
})

const targets = loadPragma("plugins/araneadev.menu/DesktopSearchTargets.js")
const search = loadPragma("plugins/araneadev.menu/DesktopSearchLogic.js")
const plain = (value) => JSON.parse(JSON.stringify(value))
const choice = {
  suggestedId: "codex",
  options: [
    { id: "claude", label: "Claude Code", available: true, reason: "92% of W · resets 14:20" },
    { id: "codex", label: "Codex", available: true, reason: "10% used" }
  ]
}
const runtime = { availability: { compositor: true } }
const agentRows = (projects, selection = choice, live = runtime) =>
  records.agentRecords({ projects }, live, () => selection)

test("agent records offer each installed provider with the suggested one first", () => {
  const rows = agentRows([project("p-1", "/tmp/a")])
  assert.deepEqual(plain(rows.map((row) => row.key)), [
    "project-agent:p-1:codex",
    "project-agent:p-1:claude"
  ])
  assert.equal(rows[0].label, "Start Codex in Duplicate")
  assert.equal(rows[0].detail, "Suggested · 10% used")
  assert.equal(rows[1].label, "Start Claude in Duplicate")
  assert.deepEqual(plain(rows[0].target), {
    projectId: "p-1",
    checkoutId: "c-p-1",
    agentId: "codex"
  })
  assert.deepEqual(plain(rows[1].aliases), ["agent", "claude", "Duplicate"])
  assert.equal(rows[0].available, true)
  assert.equal(rows[0].action, "agent")
  assert.equal(rows[0].pinned, false)
  assert.equal(rows[0].recentRank, null)
  assert.equal(rows[0].activeWorkspace, false)
})

test("agent records reject invalid providers, omit unavailable tools and deduplicate opaque identities", () => {
  const selection = {
    suggestedId: "other",
    options: [
      ...choice.options,
      choice.options[1],
      { id: "other", label: "Unknown", available: true },
      { id: "codex ", label: "Forged", available: true }
    ]
  }
  const projects = [null, {}, project("p-1", "/tmp/a"), project("p-1", "/tmp/b")]
  assert.equal(agentRows(projects, selection).length, 2)
  assert.deepEqual(plain(agentRows(projects, { options: [] })), [])
  assert.equal(
    agentRows(projects, {
      options: [{ ...choice.options[0], available: false }]
    }).length,
    0
  )
  const missing = { ...project("p-1", "/tmp/a"), lastCheckoutId: "missing" }
  assert.ok(
    agentRows([missing]).every((row) => !row.available && row.target.checkoutId === "missing")
  )
  assert.ok(agentRows([project("p-1", "/tmp/a")], choice, {}).every((row) => !row.available))
})

test("record-to-dispatch pipeline preserves duplicate names and both exact provider identities", () => {
  const projects = [project("p-1", "/tmp/a"), project("p-2", "/tmp/b")]
  const snapshot = { projectRecords: agentRows(projects) }
  const source = targets.sourceRecords(snapshot)
  const rows = search.rankResults(source, "agent duplicate")
  assert.deepEqual(plain(rows.map((row) => row.key)), [
    "project-agent:p-1:codex",
    "project-agent:p-2:codex",
    "project-agent:p-1:claude",
    "project-agent:p-2:claude"
  ])
  for (const [query, wanted] of [
    ["claude duplicate", ["project-agent:p-1:claude", "project-agent:p-2:claude"]],
    ["codex duplicate", ["project-agent:p-1:codex", "project-agent:p-2:codex"]]
  ]) {
    assert.deepEqual(plain(search.rankResults(source, query).map((row) => row.key)), wanted)
  }
  for (const row of rows) {
    assert.deepEqual(plain(targets.dispatchTarget(row, snapshot)), {
      kind: "project",
      payload: {
        projectId: row.target.projectId,
        checkoutId: row.target.checkoutId,
        roles: ["agent"],
        newWindowRole: "agent",
        agentId: row.target.agentId
      }
    })
  }
})

test("agent preference cannot override match eligibility, tier, or ordinary project scoring", () => {
  const projectRow = {
    ...records.records({ projects: [project("p-1", "/tmp/a")] }, runtime)[0],
    label: "Open Duplicate"
  }
  const source = targets.sourceRecords({
    projectRecords: [projectRow, ...agentRows([project("p-1", "/tmp/a")])]
  })
  assert.deepEqual(plain(search.rankResults(source, "duplicate").map((row) => row.key)), [
    "project:p-1",
    "project-agent:p-1:claude",
    "project-agent:p-1:codex"
  ])
  assert.deepEqual(plain(search.rankResults(source, "start claude").map((row) => row.key)), [
    "project-agent:p-1:claude"
  ])
  const exact = { type: "app", label: "Agent Duplicate", target: { appId: "exact" } }
  assert.equal(search.rankResults([exact, ...source], "agent duplicate")[0].key, "app:exact")
})

test("activation revalidates checkout, provider availability, and cached provider without changing saved Open roles", () => {
  const p = { ...project("p-1", "/tmp/a"), openRoles: ["editor", "terminal", "agent"] }
  const snapshot = {
    projectRecords: [
      ...records
        .records({ projects: [p] }, runtime)
        .map((row) => ({ ...row, label: "Open " + row.label })),
      ...agentRows([p])
    ]
  }
  const row = search.rankResults(targets.sourceRecords(snapshot), "codex duplicate")[0]
  for (const fresh of [
    { projectRecords: [] },
    { projectRecords: agentRows([{ ...p, lastCheckoutId: "missing" }]) },
    {
      projectRecords: agentRows([p], {
        ...choice,
        options: [{ ...choice.options[1], available: false }]
      })
    },
    { projectRecords: agentRows([p], choice, {}) },
    { projectRecords: [{ ...row, target: { ...row.target, agentId: "other" } }] }
  ])
    assert.equal(targets.dispatchTarget(row, fresh), null)
  assert.equal(
    targets.dispatchTarget({ ...row, target: { ...row.target, agentId: "claude" } }, snapshot),
    null
  )
  const open = search.rankResults(targets.sourceRecords(snapshot), "open duplicate")[0]
  assert.deepEqual(plain(targets.dispatchTarget(open, snapshot)), {
    kind: "project",
    payload: { projectId: "p-1", checkoutId: "c-p-1" }
  })
  assert.deepEqual(p.openRoles, ["editor", "terminal", "agent"])
})

test("typed environment search keeps exact saved identity and launch snapshot", () => {
  assert.equal(typeof records.environmentRecords, "function")
  const rows = records.environmentRecords(
    { projects: [project("p-1", "/current")] },
    {
      availability: { compositor: true },
      environments: [
        {
          id: "e-one",
          projectId: "p-1",
          checkoutId: "old",
          workspaceId: 4,
          profileSnapshot: { name: "Original" },
          checkoutSnapshot: { path: "/old", branch: "topic" },
          observedRoles: []
        }
      ]
    }
  )
  assert.equal(rows[0].type, "project-environment")
  assert.deepEqual(JSON.parse(JSON.stringify(rows[0].target)), {
    projectId: "p-1",
    environmentId: "e-one"
  })
  assert.match(rows[0].label, /Return.*Original/)
  assert.match(rows[0].detail, /not checked/)
})

test("environment records survive the ranking facade with exact Return identities", () => {
  const search = loadPragma("plugins/araneadev.menu/DesktopSearchLogic.js")
  const row = {
    key: "project-environment:e-one",
    type: "project-environment",
    label: "Return Terminal",
    target: { projectId: "p-one", environmentId: "e-one" },
    available: true
  }
  const normalized = search.normalizeRecord(row)
  assert.ok(normalized, "typed environment must not disappear during source publication")
  assert.equal(normalized.key, row.key)
  assert.deepEqual(JSON.parse(JSON.stringify(normalized.target)), row.target)
  assert.equal(search.parseQuery("project-environment: Terminal").type, "project-environment")
  assert.equal(search.normalizeRecord({ ...row, target: { environmentId: "e-one" } }), null)
})
