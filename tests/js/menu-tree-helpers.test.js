const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const tree = loadPragma("plugins/araneadev.menu/MenuTree.js")

test("menu tree helpers resolve routes and breadcrumbs", () => {
  const items = {
    root: { id: "root", label: "Go" },
    system: { id: "system", parent: "root", label: "System", aliases: ["power"] },
    "system.lock": { id: "system.lock", parent: "system", label: "Lock", kind: "action" }
  }
  const order = ["root", "system", "system.lock"]

  assert.equal(tree.resolveRoute(items, order, "power"), "system")
  assert.equal(tree.depthFor(items, "system.lock"), 1)
  assert.equal(tree.pathFor(items, "system.lock"), "System › Lock")
  assert.equal(tree.parentPathFor(items, "system.lock"), "System")
  assert.equal(tree.isDescendantOf(items, "system.lock", "root"), true)
  assert.equal(tree.childCount(items, order, "system"), 1)
})

test("menu tree visibility follows guards and visible descendants", () => {
  const items = {
    root: { id: "root", kind: "menu" },
    system: { id: "system", parent: "root", kind: "menu" },
    lock: { id: "lock", parent: "system", kind: "action", when: "check" }
  }
  const order = ["root", "system", "lock"]

  assert.equal(tree.isVisible(items, order, { lock: true }, items.system), true)
  assert.equal(tree.isVisible(items, order, { lock: false }, items.system), false)
})
