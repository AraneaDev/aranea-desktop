const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const model = require(
  path.join(__dirname, "..", "..", "plugins/araneadev.workspaces/WorkspaceModel.js")
)

test("normalizes workspace rows and marks the focused workspace active", () => {
  const states = model.normalizeWorkspaces(
    [
      { id: 2, name: "2", windows: [{ address: "a" }], monitor: "DP-1" },
      { id: 1, name: "1", windows: [], monitor: "DP-1" }
    ],
    2,
    "DP-1"
  )

  assert.deepEqual(states, [
    {
      id: 1,
      name: "1",
      active: false,
      occupied: false,
      urgent: false,
      monitor: "DP-1",
      windows: 0,
      windowLabels: [],
      special: false
    },
    {
      id: 2,
      name: "2",
      active: true,
      occupied: true,
      urgent: false,
      monitor: "DP-1",
      windows: 1,
      windowLabels: ["a"],
      special: false
    }
  ])
})

test("visible workspaces keep active, occupied, urgent, and special rows", () => {
  const states = model.normalizeWorkspaces(
    [
      { id: 1, windows: [] },
      { id: 2, windows: [{ address: "a" }] },
      { id: 3, windows: [], urgent: true },
      { id: -99, name: "special:scratchpad", special: true, windows: [] }
    ],
    1,
    ""
  )

  assert.deepEqual(
    model.visibleWorkspaces(states).map((row) => row.id),
    [1, 2, 3, -99]
  )
})

test("indicator dots expose every normal workspace and preserve urgent state", () => {
  const states = model.normalizeWorkspaces(
    [
      { id: 1, windows: [{ address: "a" }] },
      { id: 2, windows: [], urgent: true },
      { id: 3, windows: [] }
    ],
    1,
    ""
  )

  assert.deepEqual(model.indicatorDots(states), [
    { id: 1, active: true, urgent: false },
    { id: 2, active: false, urgent: true },
    { id: 3, active: false, urgent: false }
  ])
})

test("overview workspaces includes empty normal workspaces", () => {
  const states = model.normalizeWorkspaces(
    [
      { id: 1, windows: [] },
      { id: 2, windows: [] },
      { id: -1, special: true, windows: [] }
    ],
    1,
    ""
  )

  assert.deepEqual(
    model.overviewWorkspaces(states).map((row) => row.id),
    [1, 2]
  )
})

test("standard workspace set fills empty workspaces one through five", () => {
  assert.deepEqual(
    model.ensureStandardWorkspaces([{ id: 2, windows: [] }]).map((row) => row.id),
    [2, 1, 3, 4, 5]
  )
})

test("standard workspace set accepts Quickshell list wrappers", () => {
  const rows = { length: 1, 0: { id: 4, windows: [] } }
  assert.deepEqual(
    model.ensureStandardWorkspaces(rows).map((row) => row.id),
    [4, 1, 2, 3, 5]
  )
})

test("cycleTarget wraps across visible workspaces", () => {
  const states = model.normalizeWorkspaces(
    [
      { id: 1, windows: [{ address: "a" }] },
      { id: 2, windows: [] },
      { id: 3, windows: [{ address: "b" }] }
    ],
    1,
    ""
  )

  assert.equal(model.cycleTarget(states, 1, 1), 3)
  assert.equal(model.cycleTarget(states, 3, 1), 1)
  assert.equal(model.cycleTarget(states, 1, -1), 3)
})

test("extracts readable window labels for the workspace popover", () => {
  const states = model.normalizeWorkspaces(
    [
      {
        id: 4,
        windows: [{ title: "Terminal", appId: "foot" }, { appId: "firefox" }]
      }
    ],
    4,
    "DP-1"
  )

  assert.deepEqual(states[0].windowLabels, ["Terminal", "firefox"])
})

test("reads Hyprland toplevel collections for occupancy and labels", () => {
  const states = model.normalizeWorkspaces(
    [{ id: 1, toplevels: { values: { length: 1, 0: { title: "Terminal", appId: "foot" } } } }],
    2,
    ""
  )

  assert.equal(states[0].occupied, true)
  assert.equal(states[0].windows, 1)
  assert.deepEqual(states[0].windowLabels, ["Terminal"])
})

test("workspaceKey follows the row's id, blank when absent", () => {
  assert.equal(model.workspaceKey({ id: 2 }), "2")
  assert.equal(model.workspaceKey({ id: -1 }), "-1")
  assert.equal(model.workspaceKey({}), "")
  assert.equal(model.workspaceKey(null), "")
})

test("workspaceKeys joins every row's key, so an equal list rebuilt matches", () => {
  assert.equal(model.workspaceKeys([{ id: 1 }, { id: 2 }]), "1\n2")
  assert.equal(
    model.workspaceKeys([{ id: 1 }, { id: 2 }]),
    model.workspaceKeys([{ id: 1 }, { id: 2 }])
  )
  assert.notEqual(
    model.workspaceKeys([{ id: 1 }, { id: 2 }]),
    model.workspaceKeys([{ id: 2 }, { id: 1 }])
  )
})

test("indexOfKey finds a row by its workspace id, -1 for an empty key", () => {
  const rows = [{ id: 1 }, { id: 2 }, { id: 3 }]
  assert.equal(model.indexOfKey(rows, "2"), 1)
  assert.equal(model.indexOfKey(rows, "9"), -1)
  assert.equal(model.indexOfKey(rows, ""), -1)
})

test("keyedWorkspace refuses a row that no longer carries the key it was aimed at", () => {
  const rows = [{ id: 1 }, { id: 2 }]
  assert.deepEqual(model.keyedWorkspace(rows, 1, "2"), { id: 2 })
  assert.equal(model.keyedWorkspace(rows, 1, "1"), null)
  assert.equal(model.keyedWorkspace(rows, 0, ""), null)
})

test("moveCursorKey wraps across rows and starts from an end when the key is gone", () => {
  const rows = [{ id: 1 }, { id: 2 }, { id: 3 }]
  assert.equal(model.moveCursorKey(rows, "1", 1), "2")
  assert.equal(model.moveCursorKey(rows, "3", 1), "1")
  assert.equal(model.moveCursorKey(rows, "1", -1), "3")
  assert.equal(model.moveCursorKey(rows, "", 1), "1")
  assert.equal(model.moveCursorKey(rows, "", -1), "3")
  assert.equal(model.moveCursorKey([], "1", 1), "")
})

test("cursorMove reveals the current cursor on the first key, then moves it", () => {
  const rows = [{ id: 1 }, { id: 2 }, { id: 3 }]
  assert.deepEqual(model.cursorMove(rows, "2", false, 1), { key: "2", keyboard: true })
  assert.deepEqual(model.cursorMove(rows, "", false, 1), { key: "1", keyboard: true })
  assert.deepEqual(model.cursorMove(rows, "1", true, 1), { key: "2", keyboard: true })
  assert.deepEqual(model.cursorMove(rows, "1", true, 0), { key: "1", keyboard: true })
})

test("cursorPress only reveals the cursor before acting on it", () => {
  const rows = [{ id: 1 }, { id: 2 }]
  assert.deepEqual(model.cursorPress(rows, "1", false), { keyboard: true, row: null })
  assert.deepEqual(model.cursorPress(rows, "1", true), { keyboard: true, row: { id: 1 } })
  assert.deepEqual(model.cursorPress(rows, "", true), { keyboard: true, row: null })
})

test("outlineIndex draws the outline only while the keyboard shows the cursor", () => {
  const rows = [{ id: 1 }, { id: 2 }]
  assert.equal(model.outlineIndex(rows, "2", true), 1)
  assert.equal(model.outlineIndex(rows, "2", false), -1)
})

test("openCaption reports how many workspaces are shown", () => {
  assert.equal(model.openCaption(2), "2 open")
  assert.equal(model.openCaption(0), "0 open")
  assert.equal(model.openCaption(-1), "0 open")
})

test("workspaceLabel names the row by its display name", () => {
  assert.equal(model.workspaceLabel({ name: "2" }), "Workspace 2")
  assert.equal(model.workspaceLabel({}), "Workspace ")
})

test("workspaceDetail reads the window count, empty, and the active row", () => {
  assert.equal(model.workspaceDetail({ windows: 0, active: false }), "empty")
  assert.equal(model.workspaceDetail({ windows: 1, active: false }), "1 window")
  assert.equal(model.workspaceDetail({ windows: 3, active: false }), "3 windows")
  assert.equal(model.workspaceDetail({ windows: 0, active: true }), "empty · current")
  assert.equal(model.workspaceDetail({ windows: 2, active: true }), "2 windows · current")
})

test("workspaceDetail appends attention for an urgent row, alongside current", () => {
  assert.equal(model.workspaceDetail({ windows: 1, urgent: true }), "1 window · attention")
  assert.equal(
    model.workspaceDetail({ windows: 0, active: false, urgent: true }),
    "empty · attention"
  )
  assert.equal(
    model.workspaceDetail({ windows: 2, active: true, urgent: true }),
    "2 windows · current · attention"
  )
  assert.equal(model.workspaceDetail({ windows: 1, urgent: false }), "1 window")
})

test("workspaceTitles joins the open windows' titles, blank with none", () => {
  assert.equal(model.workspaceTitles({ windowLabels: ["kitty", "firefox"] }), "kitty · firefox")
  assert.equal(model.workspaceTitles({ windowLabels: [] }), "")
  assert.equal(model.workspaceTitles({}), "")
  assert.equal(model.workspaceTitles({ windowLabels: ["a", "", 3, "b"] }), "a · b")
})

test("workspaceLayoutSignature pairs each row's id with whether it shows titles", () => {
  const withTitles = [
    { id: 1, windowLabels: ["kitty"] },
    { id: 2, windowLabels: [] }
  ]
  assert.equal(model.workspaceLayoutSignature(withTitles), "1:1\n2:0")
  assert.equal(
    model.workspaceLayoutSignature(withTitles),
    model.workspaceLayoutSignature(withTitles)
  )
  const titlesGone = [
    { id: 1, windowLabels: [] },
    { id: 2, windowLabels: [] }
  ]
  assert.notEqual(
    model.workspaceLayoutSignature(withTitles),
    model.workspaceLayoutSignature(titlesGone)
  )
})
