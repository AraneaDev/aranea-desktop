const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const tools = loadPragma("plugins/araneadev.projects/ProjectTools.js")
const plain = (value) => JSON.parse(JSON.stringify(value))
const path = '/tmp/repo $(touch NEVER); "quoted"'
const token = "dev.aranea.project_test"
test("terminal adapters preserve exact path and distinct application token", () => {
  const expected = {
    alacritty: ["alacritty", "--class", token, "--working-directory", path],
    kitty: ["kitty", "--class", token, "--directory", path],
    foot: ["foot", "--app-id", token, "--working-directory", path],
    ghostty: [
      "ghostty",
      "--class=" + token,
      "--gtk-single-instance=false",
      "--working-directory=" + path
    ]
  }
  for (const id of Object.keys(expected)) {
    const spec = plain(tools.launchSpec("terminal", id, path, token))
    assert.deepEqual(spec, {
      argv: expected[id],
      cwd: path,
      expectedAppId: token,
      evidenceMode: "process-app-id"
    })
  }
})
test("nvim uses selected terminal execute argv with exact directory", () => {
  for (const id of ["alacritty", "kitty", "foot", "ghostty"]) {
    const base = plain(tools.launchSpec("terminal", id, path, token))
    const extra = id === "alacritty" ? ["--command"] : id === "ghostty" ? ["-e"] : []
    assert.deepEqual(
      plain(tools.launchSpec("editor", "nvim", path, token, id)).argv,
      base.argv.concat(extra, ["nvim", "--", path])
    )
  }
  assert.equal(tools.launchSpec("editor", "nvim", path, token), null)
  assert.equal(tools.launchSpec("editor", "nvim", path, token, "unsupported"), null)
})
test("code launches new window with process-only evidence", () => {
  assert.deepEqual(plain(tools.launchSpec("editor", "code", path, token)), {
    argv: ["code", "--new-window", path],
    cwd: path,
    expectedAppId: null,
    evidenceMode: "process-only"
  })
})
test("unverified tools, mismatched roles, invalid paths and tokens cannot launch", () => {
  for (const [role, id, cwd, identity] of [
    ["terminal", "wezterm", path, token],
    ["editor", "kitty", path, token],
    ["terminal", "kitty", "relative", token],
    ["terminal", "kitty", "/tmp/a\n", token],
    ["terminal", "ghostty", path, "invalid"],
    ["terminal", "alacritty", path, "--flag"]
  ])
    assert.equal(tools.launchSpec(role, id, cwd, identity), null)
})
