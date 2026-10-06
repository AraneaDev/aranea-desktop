const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const search = loadPragma("plugins/araneadev.menu/DesktopSearchLogic.js")
const plain = (value) => JSON.parse(JSON.stringify(value))
const record = (type, id, label, extra = {}) => ({
  key: `${type}:${id}`,
  type,
  label,
  detail: "",
  aliases: [],
  target: {
    [{
      app: "appId",
      command: "itemId",
      window: "address",
      workspace: "workspaceId",
      setting: "section"
    }[type]]: id
  },
  available: true,
  pinned: false,
  recentRank: null,
  activeWorkspace: false,
  ...extra
})
const keys = (records, query) => plain(search.rankResults(records, query)).map((row) => row.key)

test("recognized type prefixes filter results while unknown prefixes remain query text", () => {
  assert.deepEqual(plain(search.parseQuery("window: firefox")), { type: "window", text: "firefox" })
  assert.deepEqual(plain(search.parseQuery("https: example")), {
    type: null,
    text: "https: example"
  })
  for (const type of ["app", "command", "window", "workspace", "setting"]) {
    assert.deepEqual(plain(search.parseQuery(`  ${type.toUpperCase()}:  Firefox  `)), {
      type,
      text: "Firefox"
    })
  }
  assert.deepEqual(
    keys(
      [record("app", "firefox", "Firefox"), record("window", "0x1", "Firefox")],
      "window: firefox"
    ),
    ["window:0x1"]
  )
})

test("match quality outranks pinned apps and all other preferences", () => {
  const rows = [
    record("app", "prefix", "Firefox Nightly", { pinned: true, recentRank: 0 }),
    record("window", "0x1", "Project — Firefox", { activeWorkspace: true }),
    record("app", "exact", "Firefox")
  ]
  assert.deepEqual(keys(rows, "firefox"), ["app:exact", "app:prefix", "window:0x1"])
})

test("label, alias, and whole-word description matches form separate tiers", () => {
  const rows = [
    record("command", "description", "A", { detail: "Firefox browsing" }),
    record("command", "alias", "B", { aliases: ["FIREFOX_browser"] }),
    record("command", "substring", "C Firefox"),
    record("command", "prefix", "Firefox D"),
    record("command", "exact", "Firefox")
  ]
  assert.deepEqual(keys(rows, "firefox"), [
    "command:exact",
    "command:prefix",
    "command:substring",
    "command:alias",
    "command:description"
  ])
  assert.deepEqual(keys([rows[0]], "fire"), [])
  assert.deepEqual(keys([rows[1]], "browser"), ["command:alias"])
})

test("multiple query terms retain combined name and description matching", () => {
  const rows = [
    record("command", "power", "Power Saver", {
      aliases: ["battery_mode"],
      detail: "Reduce battery usage"
    })
  ]
  assert.deepEqual(keys(rows, "power usage"), ["command:power"])
  assert.deepEqual(keys(rows, "battery usage"), ["command:power"])
  assert.deepEqual(keys(rows, "power usag"), [])
})

test("within one tier pinned apps precede active-workspace windows and recent apps", () => {
  const rows = [
    record("app", "older", "Match", { recentRank: 7 }),
    record("command", "plain", "Match"),
    record("app", "recent", "Match", { recentRank: 0 }),
    record("window", "0x1", "Match", { activeWorkspace: true }),
    record("app", "pinned", "Match", { pinned: true })
  ]
  assert.deepEqual(keys(rows, "match"), [
    "app:pinned",
    "window:0x1",
    "app:recent",
    "app:older",
    "command:plain"
  ])
})

test("irrelevant preferences cannot promote commands, settings, workspaces, or windows", () => {
  const rows = [
    record("setting", "appearance", "Match", {
      pinned: true,
      recentRank: 0,
      activeWorkspace: true
    }),
    record("command", "a", "Match"),
    record("workspace", "1", "Match", { pinned: true, recentRank: 0, activeWorkspace: true }),
    record("window", "0x1", "Match", { pinned: true, recentRank: 0 })
  ]
  assert.deepEqual(keys(rows, "match"), [
    "command:a",
    "setting:appearance",
    "window:0x1",
    "workspace:1"
  ])
})

test("duplicate app identities collapse while same-label apps and open windows stay distinct", () => {
  const rows = [
    record("app", "firefox", "Firefox", { key: "favorite:firefox" }),
    record("app", "firefox", "Firefox", { key: "recent:firefox", pinned: true }),
    record("app", "firefox-beta", "Firefox"),
    record("window", "0x123", "Firefox")
  ]
  const results = plain(search.rankResults(rows, "firefox"))
  assert.deepEqual(
    results.map((row) => row.key),
    ["app:firefox", "app:firefox-beta", "window:0x123"]
  )
  assert.equal(results[0].pinned, true)
  assert.deepEqual(
    rows.map((row) => row.key),
    ["favorite:firefox", "recent:firefox", "app:firefox-beta", "window:0x123"]
  )
})

test("unavailable records and headings cannot become search or activation targets", () => {
  const available = record("command", "current", "Match")
  const unavailable = record("window", "0x1", "Match", { available: false })
  const heading = { key: "heading:apps", type: "heading", label: "Match", available: true }
  assert.deepEqual(keys([unavailable, heading, available], "match"), ["command:current"])
  assert.equal(search.resolveTarget([unavailable], "window:0x1"), null)
  assert.equal(search.resolveTarget([], "window:0x123"), null)
  assert.deepEqual(plain(search.resolveTarget([available], "command:current")), available)
  assert.equal(search.resolveTarget([available], "command:missing"), null)
})

test("ties sort by case-insensitive label then stable key regardless of source order", () => {
  const rows = [
    record("command", "z", "Zulu"),
    record("command", "b", "alpha"),
    record("command", "a", "Alpha")
  ]
  assert.deepEqual(keys(rows, ""), ["command:a", "command:b", "command:z"])
  assert.deepEqual(keys(rows.slice().reverse(), ""), ["command:a", "command:b", "command:z"])
})

test("the result cap applies after filtering and deduplication", () => {
  const rows = Array.from({ length: 55 }, (_, i) =>
    record("app", String(i).padStart(2, "0"), `Match ${String(i).padStart(2, "0")}`)
  )
  const duplicates = rows.flatMap((row) => [row, { ...row, key: `favorite:${row.target.appId}` }])
  const results = plain(search.rankResults(duplicates.reverse(), "match"))
  assert.equal(results.length, 50)
  assert.equal(results[0].key, "app:00")
  assert.equal(results[49].key, "app:49")
})

test("normalization creates typed canonical keys and omits invalid targets", () => {
  assert.deepEqual(
    plain(
      search.normalizeRecord({
        type: "workspace",
        label: "  Development  ",
        target: { workspaceId: 2 }
      })
    ),
    {
      key: "workspace:2",
      type: "workspace",
      label: "Development",
      detail: "",
      aliases: [],
      target: { workspaceId: 2 },
      available: true,
      pinned: false,
      recentRank: null,
      activeWorkspace: false
    }
  )
  assert.equal(search.normalizeRecord({ type: "app", label: "App", target: { appId: "" } }), null)
  assert.equal(
    search.normalizeRecord({ type: "setting", label: "Unknown", target: { section: "unknown" } }),
    null
  )
  assert.equal(search.normalizeRecord(null), null)
  assert.deepEqual(plain(search.normalizeRecords([null, record("app", "app", "App")])), [
    record("app", "app", "App")
  ])
})
