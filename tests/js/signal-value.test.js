// Logic contract for SignalValue.js: values received through a QML `var`
// signal parameter become plain JS again. Since Qt 6.12 such a parameter
// arrives as a converted map (keys sorted) whose arrays are sequence
// objects; a test stands in for a sequence with an array-like object. Run
// with `node --test tests/js/`.
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const value = require(path.join(__dirname, "..", "..", "plugins/araneadev.shared/SignalValue.js"))

/**
 * A stand-in for a Qt sequence object: indexed, with a length, not an Array.
 * @param {Array<*>} items - the elements
 * @returns {{[key: string]: *}} the array-like object
 */
function sequence(items) {
  const seq = { length: items.length }
  items.forEach((item, i) => {
    seq[i] = item
  })
  return seq
}

test("plain turns sequences back into arrays, deeply", () => {
  const received = { b: sequence(["agent", { roles: sequence(["x"]) }]), a: 1 }
  const out = value.plain(received)
  assert.ok(Array.isArray(out.b))
  assert.ok(Array.isArray(out.b[1].roles))
  assert.deepEqual(out, { a: 1, b: ["agent", { roles: ["x"] }] })
})

test("plain turns a top-level sequence into an array", () => {
  assert.deepEqual(value.plain(sequence(["/a", "/b"])), ["/a", "/b"])
})

test("plain rebuilds a converted map, whose string form is not a plain object's", () => {
  const map = { roles: sequence(["agent"]), toString: () => "[object V4ReferenceObject]" }
  const out = value.plain({ deep: map })
  assert.ok(Array.isArray(out.deep.roles))
})

test("plain keeps scalars, null, real arrays and data with a length field", () => {
  assert.equal(value.plain(null), null)
  assert.equal(value.plain(undefined), undefined)
  assert.equal(value.plain("text"), "text")
  assert.equal(value.plain(3), 3)
  assert.deepEqual(value.plain([1, [2]]), [1, [2]])
  assert.deepEqual(value.plain({ length: 5, unit: "m" }), { length: 5, unit: "m" })
})

test("plain leaves objects that are not plain data untouched", () => {
  const item = { toString: () => "QQuickItem(0x1)", width: 4 }
  const out = value.plain({ target: item })
  assert.equal(out.target, item)
})

test("same compares data regardless of key order and sequence wrapping", () => {
  assert.ok(value.same({ projectId: "p", runId: "r" }, { runId: "r", projectId: "p" }))
  assert.ok(value.same({ roles: sequence(["agent"]) }, { roles: ["agent"] }))
  assert.ok(!value.same({ roles: ["agent", "editor"] }, { roles: ["editor", "agent"] }))
  assert.ok(!value.same({ a: 1 }, { a: 2 }))
})

test("key gives one string per value regardless of key order", () => {
  assert.equal(value.key({ b: 1, a: [2] }), value.key({ a: sequence([2]), b: 1 }))
  assert.equal(value.key({ b: 1, a: [2] }), '{"a":[2],"b":1}')
})
