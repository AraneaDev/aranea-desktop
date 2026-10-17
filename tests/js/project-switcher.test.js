const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const s = loadPragma("plugins/araneadev.projects/ProjectSwitcher.js")
const problems = loadPragma("plugins/araneadev.projects/ProjectProblems.js")
const plain = (v) => JSON.parse(JSON.stringify(v))

const tools = {
  editors: [{ id: "code", available: true, supported: true }],
  terminals: [],
  agents: [],
  defaults: {}
}
const code = (id, rev) => ({
  id,
  name: "VS Code",
  revision: rev,
  roles: ["editor"],
  tools: { editorId: "code" }
})
const projects = () => [
  {
    id: "p-c",
    name: "Cee",
    lastCheckoutId: "c-c",
    checkouts: [{ id: "c-c", path: "/w/cee", branch: "main" }],
    profiles: []
  },
  {
    id: "p-b",
    name: "Bee",
    lastCheckoutId: "c-b",
    checkouts: [{ id: "c-b", path: "/w/bee", branch: "dev" }],
    profiles: []
  },
  {
    id: "p-a",
    name: "Aye",
    lastCheckoutId: "c-a",
    checkouts: [{ id: "c-a", path: "/w/aye", branch: "main" }],
    profiles: [code("f-a", 1)],
    lastProfileId: "f-a"
  }
]
const nav = { pinnedProjectIds: ["p-a"], visitedAt: { "p-b": 2000 } }
const env = (o) =>
  Object.assign(
    { id: "e-b", projectId: "p-b", workspaceId: 3, observedRoles: ["editor"], generation: 2 },
    o
  )
const rows = (runtime, query) =>
  plain(s.switcherRows(projects(), nav, query || "", runtime, tools, {}))

test("orders rows and picks each action", () => {
  const r = rows({ environments: [env()] })
  assert.deepEqual(
    r.map((x) => x.id),
    ["p-a", "p-b", "p-c"]
  )
  assert.deepEqual(r[0].action, {
    kind: "start",
    label: "Start · VS Code",
    target: { projectId: "p-a", checkoutId: "c-a", profileId: "f-a", profileRevision: 1 }
  })
  assert.deepEqual(r[0].startTarget, r[0].action.target)
  assert.deepEqual(r[1].action, {
    kind: "return",
    label: "Return · workspace 3",
    target: { projectId: "p-b", environmentId: "e-b" }
  })
  assert.equal(r[1].startTarget, null)
  assert.deepEqual(r[2].action, {
    kind: "setup",
    label: "Set up first",
    target: { projectId: "p-c" }
  })
  assert.equal(r[2].startTarget, null)
  assert.equal(r[0].branch, "main")
  assert.equal(r[0].path, "/w/aye")
})

test("a Return also carries the Start target when a profile is usable", () => {
  const list = projects()
  list[0].profiles = [code("f-c", 4)]
  const r = plain(
    s.switcherRows(
      list,
      nav,
      "",
      { environments: [env({ projectId: "p-c", id: "e-c" })] },
      tools,
      {}
    )
  )
  const c = r.find((x) => x.id === "p-c")
  assert.equal(c.action.kind, "return")
  assert.deepEqual(c.startTarget, {
    projectId: "p-c",
    checkoutId: "c-c",
    profileId: "f-c",
    profileRevision: 4
  })
})

test("environments without open windows are not returnable", () => {
  const r = rows({ environments: [env({ projectId: "p-a", observedRoles: [] })] })
  assert.equal(r[0].action.kind, "start")
})

test("highest generation wins, then the last one", () => {
  let r = rows({
    environments: [env({ id: "e1", generation: 5 }), env({ id: "e2", generation: 2 })]
  })
  assert.equal(r[1].action.target.environmentId, "e1")
  r = rows({
    environments: [
      env({ id: "e1", generation: undefined }),
      env({ id: "e2", generation: undefined })
    ]
  })
  assert.equal(r[1].action.target.environmentId, "e2")
})

test("query filters with navigation matching", () => {
  assert.deepEqual(
    rows({ environments: [] }, "bee").map((x) => x.id),
    ["p-b"]
  )
  assert.deepEqual(
    rows({ environments: [] }, "dev").map((x) => x.id),
    ["p-b"]
  )
  assert.deepEqual(
    rows({ environments: [] }, "/w/cee").map((x) => x.id),
    ["p-c"]
  )
})

test("unvisited unpinned rows are alphabetical", () => {
  const list = projects()
  const r = plain(s.switcherRows(list, {}, "", {}, tools, {}))
  assert.deepEqual(
    r.map((x) => x.name),
    ["Aye", "Bee", "Cee"]
  )
})

test("labels have no banned word or em dash", () => {
  const r = rows({ environments: [env()] })
  for (const row of r) {
    const text = row.action.label.toLowerCase()
    assert.ok(!text.includes("\u2014"))
    for (const word of problems.BANNED) assert.ok(!text.includes(word), word)
  }
})

const taskOn = (checkoutId, at, state, projectId) => ({
  taskId: "t-" + checkoutId + at,
  reportedState: state || "ready-for-review",
  lastReceivedAt: at,
  association: { status: "registered", projectId: projectId || "p-b", checkoutId }
})
const withTaskCheckouts = () => {
  const list = projects()
  list[1].checkouts = [
    { id: "c-b", path: "/w/bee", branch: "dev", primary: true },
    { id: "c-x", path: "/w/bee-x", branch: "feat/x", primary: false },
    { id: "c-y", path: "/w/bee-y", branch: "feat/y", primary: false }
  ]
  return list
}
const rowsWith = (list, runtime, tasks, reviews) =>
  plain(s.switcherRows(list, nav, "", runtime, tools, {}, tasks, reviews))

test("a ready task checkout gives the review action and chip", () => {
  const r = rowsWith(withTaskCheckouts(), { environments: [env()] }, [taskOn("c-x", 100)], {})
  const bee = r.find((x) => x.id === "p-b")
  assert.deepEqual(bee.action, {
    kind: "review",
    label: "Review · feat/x",
    target: { projectId: "p-b", checkoutId: "c-x" }
  })
  assert.equal(bee.review, true)
  assert.equal(r.find((x) => x.id === "p-a").review, false)
  assert.equal(r.find((x) => x.id === "p-a").action.kind, "start")
})

test("the newest finished task picks the review checkout", () => {
  const r = rowsWith(
    withTaskCheckouts(),
    {},
    [taskOn("c-x", 100), taskOn("c-y", 300), taskOn("c-x", 200, "working")],
    {}
  )
  assert.equal(r.find((x) => x.id === "p-b").action.target.checkoutId, "c-y")
  const r2 = rowsWith(withTaskCheckouts(), {}, [taskOn("c-x", 400), taskOn("c-y", 300)], {})
  assert.equal(r2.find((x) => x.id === "p-b").action.target.checkoutId, "c-x")
})

test("working, reviewed and unrelated tasks give no review", () => {
  const list = withTaskCheckouts()
  let r = rowsWith(list, {}, [taskOn("c-x", 100, "working")], {})
  assert.equal(r.find((x) => x.id === "p-b").review, false)
  list[1].checkouts[1].review = { reviewedHead: "a".repeat(40), reviewedTaskAt: 100 }
  r = rowsWith(list, {}, [taskOn("c-x", 100)], { "c-x": { head: "a".repeat(40) } })
  assert.equal(r.find((x) => x.id === "p-b").review, false)
  r = rowsWith(withTaskCheckouts(), {}, [taskOn("c-x", 100, "ready-for-review", "p-a")], {})
  assert.equal(r.find((x) => x.id === "p-b").review, false)
})

test("without tasks nothing changes", () => {
  const r = rows({ environments: [env()] })
  assert.ok(r.every((x) => x.review === false))
  assert.equal(r[1].action.kind, "return")
})
