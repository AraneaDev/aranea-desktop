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
