const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")
const targets = loadPragma("plugins/araneadev.menu/DesktopSearchTargets.js")
const plain = (value) => JSON.parse(JSON.stringify(value))
const snapshot = (extra = {}) => ({
  appRows: [
    { id: "apps.browser", appId: "browser", kind: "app", label: "Browser" },
    { id: "apps.favorites.browser", appId: "browser", kind: "app", label: "Browser" },
    { id: "apps.other", appId: "other", kind: "app", label: "Browser" }
  ],
  menuItems: {
    vpn: {
      id: "vpn",
      kind: "action",
      label: "VPN",
      action: "trusted existing action",
      when: "true"
    },
    setup: { id: "setup", kind: "menu", label: "Setup" },
    heading: { id: "heading", kind: "heading", label: "Heading" },
    hidden: { id: "hidden", kind: "action", label: "Hidden", when: "false" }
  },
  whenResults: { hidden: false },
  favoriteAppIds: ["browser"],
  recentAppIds: ["other", "browser"],
  settingsAvailable: true,
  compositorAvailable: true,
  focusedWorkspaceId: 2,
  windows: [{ address: "0xabc", title: 'Hostile "); os.execute("bad") --', workspace: { id: 2 } }],
  workspaces: [{ id: 2, name: "Development", windows: 1 }],
  ...extra
})
const records = (data) => plain(targets.sourceRecords(data))
const dispatch = (key, data) => {
  const row = records(data).find((entry) => entry.key === key)
  return plain(targets.dispatchTarget(row, data))
}

test("missing compositor removes only live records and app identities survive duplicate labels", () => {
  const rows = records(snapshot({ compositorAvailable: false, windows: null, workspaces: null }))
  assert.deepEqual(
    rows.map((r) => r.key),
    [
      "app:browser",
      "app:other",
      "command:vpn",
      "command:setup",
      "setting:appearance",
      "setting:display",
      "setting:schedule",
      "setting:integrations",
      "setting:projects",
      "setting:notifications"
    ]
  )
  assert.equal(rows[0].pinned, true)
  assert.equal(rows[1].recentRank, 0)
  assert.equal(rows[0].label, rows[1].label)
})

test("settings aliases discover scaling but dispatch only static section destinations", () => {
  const data = snapshot()
  const display = records(data).find((r) => r.key === "setting:display")
  for (const alias of ["display", "scale", "scaling", "custom scale"])
    assert.ok(display && display.aliases.includes(alias))
  for (const section of ["appearance", "display", "schedule", "integrations", "notifications"]) {
    assert.deepEqual(dispatch(`setting:${section}`, data), {
      kind: "argv",
      argv: ["omarchy-shell", "shell", "summon", "araneadev.settings", JSON.stringify({ section })]
    })
  }
  assert.equal(
    records(snapshot({ settingsAvailable: false })).filter((r) => r.type === "setting").length,
    0
  )
})

test("app and command targets preserve the host activation handlers", () => {
  assert.deepEqual(dispatch("app:other", snapshot()), {
    kind: "app",
    appId: "other",
    label: "Browser"
  })
  assert.deepEqual(dispatch("command:vpn", snapshot()), { kind: "command", itemId: "vpn" })
  assert.deepEqual(dispatch("command:setup", snapshot()), { kind: "command", itemId: "setup" })
})

test("hostile titles remain display text and window activation uses only exact hexadecimal address", () => {
  const data = snapshot()
  const row = records(data).find((r) => r.type === "window")
  assert.equal(row.label, data.windows[0].title)
  assert.equal(row.activeWorkspace, true)
  assert.deepEqual(dispatch(row.key, data), {
    kind: "argv",
    argv: ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:0xabc" })']
  })
  for (const address of ["", "0x0", "0xabc;bad", "address:0xabc", "-1", "title:Browser"]) {
    assert.equal(
      records(snapshot({ windows: [{ address, title: "Bad" }] })).filter((r) => r.type === "window")
        .length,
      0
    )
  }
})

test("removed or unavailable targets cannot dispatch a stale record", () => {
  const original = records(snapshot()).find((r) => r.type === "window")
  assert.equal(targets.dispatchTarget(original, snapshot({ windows: [] })), null)
  assert.equal(targets.dispatchTarget(original, snapshot({ compositorAvailable: false })), null)
  const app = records(snapshot())[0]
  assert.equal(targets.dispatchTarget(app, snapshot({ appRows: [] })), null)
  const command = records(snapshot()).find((r) => r.key === "command:vpn")
  assert.equal(targets.dispatchTarget(command, snapshot({ whenResults: { vpn: false } })), null)
})

test("named and special negative workspace IDs use fresh canonical name selectors with Lua encoding", () => {
  const data = snapshot({
    workspaces: [
      { id: 2, name: "Display-only name", windows: 3 },
      { id: -1337, name: 'Dev "quoted" \\ room', label: "Do not dispatch this" },
      { id: -99, name: "special:scratch" },
      { id: -98, name: "special" },
      { id: -1338, label: "Cannot infer identity from label" }
    ]
  })
  assert.deepEqual(
    records(data)
      .filter((r) => r.type === "workspace")
      .map((r) => r.key),
    ["workspace:2", "workspace:-1337", "workspace:-99", "workspace:-98"]
  )
  assert.deepEqual(dispatch("workspace:2", data).argv, [
    "hyprctl",
    "dispatch",
    'hl.dsp.focus({ workspace = "2" })'
  ])
  assert.equal(
    dispatch("workspace:-1337", data).argv[2],
    'hl.dsp.focus({ workspace = "name:Dev \\"quoted\\" \\\\ room" })'
  )
  assert.equal(
    dispatch("workspace:-99", data).argv[2],
    'hl.dsp.focus({ workspace = "special:scratch" })'
  )
  assert.equal(dispatch("workspace:-98", data).argv[2], 'hl.dsp.focus({ workspace = "special" })')
  const stale = records(data).find((r) => r.key === "workspace:-1337")
  assert.equal(targets.dispatchTarget(stale, snapshot({ workspaces: [] })), null)
  const renamed = snapshot({ workspaces: [{ id: -1337, name: "Current" }] })
  assert.equal(
    targets.dispatchTarget(stale, renamed).argv[2],
    'hl.dsp.focus({ workspace = "name:Current" })'
  )
})

test("raw object-model collections and missing window titles normalize without guessed targets", () => {
  const data = snapshot({
    windows: {
      values: [{ address: "0xdef", lastIpcObject: { class: "Editor" }, workspace: { id: 2 } }]
    },
    workspaces: { values: [{ id: 2, name: "2", toplevels: { values: [1, 2] } }] }
  })
  const rows = records(data)
  assert.equal(rows.find((r) => r.key === "window:0xdef").label, "Editor")
  assert.equal(rows.find((r) => r.type === "workspace").detail, "Workspace 2 · 2 windows")
})

test("invalid workspace identity cannot be guessed from labels or arbitrary selectors", () => {
  const data = snapshot({
    workspaces: [
      { id: 0, name: "Zero" },
      { id: -1, name: "Invalid" },
      { id: 1.5, name: "Fraction" },
      { id: "2", name: "String" },
      { id: -1337, name: "Unsafe\nname" },
      { id: -1338, label: "Label only", selector: "name:Fabricated" }
    ]
  })
  assert.deepEqual(
    records(data).filter((r) => r.type === "workspace"),
    []
  )
  assert.equal(
    targets.dispatchTarget(
      { key: "workspace:-1338", target: { workspaceId: -1338, selector: "name:Fabricated" } },
      data
    ),
    null
  )
})

test("forged cached selectors and display text cannot override the current raw identity", () => {
  const data = snapshot({ workspaces: [{ id: -1337, name: 'Room "); os.execute("bad") --' }] })
  const row = records(data).find((r) => r.type === "workspace")
  const forged = { ...row, label: "Forged", target: { ...row.target, selector: "previous" } }
  const result = targets.dispatchTarget(forged, data)
  assert.equal(
    result.argv[2],
    "hl.dsp.focus({ workspace = " + targets.luaString("name:" + data.workspaces[0].name) + " })"
  )
  assert.ok(!result.argv[2].includes('workspace = "previous"'))
  assert.equal(targets.luaString('a"b\\c'), '"a\\"b\\\\c"')
})

test("obsolete guard results do not hide a command whose current item has no guard", () => {
  const data = snapshot({
    menuItems: { vpn: { id: "vpn", kind: "action", label: "VPN" } },
    whenResults: { vpn: false }
  })
  assert.ok(records(data).some((r) => r.key === "command:vpn"))
})

test("project search forwards typed identities and details without display-derived commands", () => {
  const row = {
    key: "project:p-aranea",
    type: "project",
    label: 'Open Hostile ";bad',
    detail: "/tmp/dev/aranea",
    target: { projectId: "p-aranea", checkoutId: "c-main" },
    available: true
  }
  const data = snapshot({ projectRecords: [row] })
  assert.deepEqual(dispatch("project:p-aranea", data), {
    kind: "project",
    payload: { projectId: "p-aranea", checkoutId: "c-main" }
  })
  assert.equal(targets.dispatchTarget(row, snapshot({ projectRecords: [] })), null)
  assert.equal(
    targets.dispatchTarget(
      row,
      snapshot({
        projectRecords: [{ ...row, target: { projectId: "p-aranea", checkoutId: "c-other" } }]
      })
    ),
    null
  )
  assert.equal(
    targets.dispatchTarget(row, snapshot({ projectRecords: [{ ...row, available: false }] })),
    null
  )
  assert.deepEqual(dispatch("setting:projects", data).argv, [
    "omarchy-shell",
    "shell",
    "summon",
    "araneadev.settings",
    '{"section":"projects"}'
  ])
})
