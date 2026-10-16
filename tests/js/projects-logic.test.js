const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const logic = loadPragma("plugins/araneadev.projects/ProjectsLogic.js")

test("project navigation accepts opaque IDs and rejects paths, commands and wrong types", () => {
  for (const id of ["p-one", "p-123-ABC"]) assert.equal(logic.normalizeProjectId(id), id)
  for (const id of [
    null,
    undefined,
    {},
    12,
    "",
    "p-",
    "p-one\n",
    "p-one/two",
    "r-one",
    "/tmp/repo",
    "p-é",
    "p-$(command)"
  ])
    assert.equal(logic.normalizeProjectId(id), "", String(id))
})

test("local folder URLs decode once while editable absolute paths retain literal text", () => {
  for (const [input, expected] of [
    ["/", "/"],
    ["/tmp/with spaces; $(literal) 'quotes'", "/tmp/with spaces; $(literal) 'quotes'"],
    ["/tmp/literal%20folder?#", "/tmp/literal%20folder?#"],
    ["file:///tmp/with%20spaces", "/tmp/with spaces"],
    ["file://localhost/tmp/%C3%A9", "/tmp/é"],
    ["file:///tmp/literal%2520folder%3F%23", "/tmp/literal%20folder?#"]
  ])
    assert.equal(logic.normalizeFolder(input), expected, input)
})

test("folder selection rejects nonlocal URLs, malformed escapes and decoded control characters", () => {
  for (const input of [
    null,
    {},
    "",
    "relative",
    "~/Work",
    "https://host/repo",
    "file://remote/tmp/repo",
    "file:///tmp/repo?query",
    "file:///tmp/repo#fragment",
    "file:///tmp/%ZZ",
    "file:///tmp/%00",
    "file:///tmp/%0A",
    "file:///tmp/%7F",
    "/tmp/a\n",
    "/tmp/a\u0000",
    "/tmp/a\u007f"
  ])
    assert.equal(logic.normalizeFolder(input), "", String(input))
})

test("Projects window fits screen margins at normal and enlarged desktop spacing", () => {
  for (const [width, height, scale, expected] of [
    [1920, 1080, 1, { width: 1080, height: 720 }],
    [800, 600, 1, { width: 752, height: 552 }],
    [1920, 1080, 1.5, { width: 1620, height: 1008 }],
    [40, 40, 1, { width: 1, height: 1 }],
    [800, 600, undefined, { width: 752, height: 552 }]
  ])
    assert.deepEqual(JSON.parse(JSON.stringify(logic.geometry(width, height, scale))), expected)
})

test("switcher geometry is 560 by 440 and stays inside the screen", () => {
  for (const [width, height, scale, expected] of [
    [1920, 1080, 1, { width: 560, height: 440 }],
    [1920, 1080, 2, { width: 1120, height: 880 }],
    [500, 400, 1, { width: 452, height: 352 }],
    [40, 40, 1, { width: 1, height: 1 }],
    [800, 600, undefined, { width: 560, height: 440 }]
  ])
    assert.deepEqual(
      JSON.parse(JSON.stringify(logic.switcherGeometry(width, height, scale))),
      expected
    )
})
