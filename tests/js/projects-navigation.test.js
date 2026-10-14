const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { loadPragma } = require("./lib/load-pragma.js")
const modulePath = "plugins/araneadev.projects/ProjectsNavigation.js"
// Missing implementation must fail at the API boundary, rather than loader setup.
const nav = fs.existsSync(path.join(__dirname, "../..", modulePath)) ? loadPragma(modulePath) : {}

/** Build a selected checkout with an independently searchable sibling. */
function project(id, name = "Same") {
  return {
    id,
    name,
    lastCheckoutId: id + "-selected",
    checkouts: [
      { id: id + "-selected", path: "/work/" + id, branch: "main" },
      { id: id + "-other", path: "/elsewhere/" + id, branch: "feature/search" }
    ]
  }
}
/** Read identities across the isolated QML JavaScript context. */
function ids(rows) {
  return Array.from(rows, (row) => row.id)
}

test("duplicate project names retain exact selected checkout identities without mutating inputs", () => {
  const projects = [project("b"), project("a")]
  const navigation = { pinnedProjectIds: ["b"], visitedAt: { b: 123 } }
  const before = JSON.stringify({ projects, navigation })
  assert.deepEqual(JSON.parse(JSON.stringify(nav.rows(projects, navigation, "", []))), [
    { id: "b", name: "Same", path: "/work/b", branch: "main", pinned: true, visitedAt: 123 },
    { id: "a", name: "Same", path: "/work/a", branch: "main", pinned: false, visitedAt: 0 }
  ])
  assert.equal(JSON.stringify({ projects, navigation }), before)
})

test("selection prefers a registered request, then saved identity, without choosing a fallback project", () => {
  const projects = [project("a"), project("b")]
  for (const [requested, saved, expected] of [
    ["a", "b", "a"],
    ["removed", "b", "b"],
    ["", "b", "b"],
    ["", "removed", ""],
    ["removed", "removed", ""],
    ["", "", ""]
  ])
    assert.equal(nav.restoreSelection(projects, requested, saved), expected)
  assert.equal(nav.restoreSelection([], "a", "a"), "")
  assert.equal(nav.restoreSelection(null, "", null), "")
})

test("search matches names and every known checkout path and branch case insensitively", () => {
  const projects = [project("a", "Alpha"), project("b", "Beta")]
  for (const [query, expected] of [
    [" ALPHA ", ["a"]],
    ["/WORK/B", ["b"]],
    ["/elsewhere/a", ["a"]],
    ["FEATURE/SEARCH", ["a", "b"]],
    ["absent", []]
  ])
    assert.deepEqual(ids(nav.rows(projects, {}, query, [])), expected)
})

test("pins sort ahead of recency and unvisited projects sort alphabetically with deterministic ties", () => {
  const projects = [
    project("b", "same"),
    project("z", "Zulu"),
    project("a", "Same"),
    project("p", "Pinned"),
    project("r", "Recent"),
    project("o", "Older"),
    project("q", "Other pin")
  ]
  const navigation = { pinnedProjectIds: ["p", "q"], visitedAt: { r: 400, o: 200, q: 100 } }
  assert.deepEqual(ids(nav.rows(projects, navigation, "", [])), ["q", "p", "r", "o", "a", "b", "z"])
  assert.deepEqual(ids(nav.rows(projects.slice().reverse(), navigation, "", [])), [
    "q",
    "p",
    "r",
    "o",
    "a",
    "b",
    "z"
  ])
})

test("frozen results retain only matching identities and append new matches once", () => {
  const projects = [project("a", "Alpha"), project("b", "Beta"), project("c", "Gamma")]
  assert.deepEqual(
    ids(nav.rows(projects, { pinnedProjectIds: ["a"] }, "feature", ["b", "removed", "b", "c"])),
    ["b", "c", "a"]
  )
  assert.deepEqual(ids(nav.rows(projects, {}, "Alpha", ["b", "a"])), ["a"])
  assert.deepEqual(ids(nav.rows(projects, {}, "missing", ["b", "a"])), [])
})

test("missing selected checkout never silently substitutes another registered checkout", () => {
  const projects = [project("a")]
  projects[0].lastCheckoutId = "gone"
  const result = nav.rows(projects, null, "/elsewhere", null)
  assert.deepEqual(JSON.parse(JSON.stringify(result)), [
    { id: "a", name: "Same", path: "", branch: "", pinned: false, visitedAt: 0 }
  ])
  assert.deepEqual(ids(nav.rows(null, null, "", null)), [])
})

test("navigation remains searchable at zero, one, ten, fifty and one hundred projects", () => {
  for (const count of [0, 1, 10, 50, 100]) {
    const projects = Array.from({ length: count }, (_, i) => project("p" + i))
    assert.equal(nav.rows(projects, {}, "", []).length, count)
    if (count)
      assert.deepEqual(ids(nav.rows(projects, {}, "/work/p" + (count - 1), [])), [
        "p" + (count - 1)
      ])
  }
})

test("matching cached Git branches update presentation and search without editing registry", () => {
  const projects = [project("a"), project("b")]
  const before = JSON.stringify(projects)
  const cache = {
    '["a","a-selected"]': {
      data: { projectId: "a", checkoutId: "a-selected", branch: "fresh-work" }
    },
    '["b","b-selected"]': {
      data: { projectId: "a", checkoutId: "b-selected", branch: "wrong-project" }
    }
  }
  assert.equal(nav.rows(projects, {}, "", [], cache)[0].branch, "fresh-work")
  assert.deepEqual(ids(nav.rows(projects, {}, "fresh-work", [], cache)), ["a"])
  assert.equal(nav.rows(projects, {}, "", [], cache)[1].branch, "main")
  assert.equal(JSON.stringify(projects), before)
})
