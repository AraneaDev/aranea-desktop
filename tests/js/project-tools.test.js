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
  const expected = {
    alacritty: [
      "alacritty",
      "--class",
      token,
      "--working-directory",
      path,
      "--command",
      "nvim",
      "--",
      path
    ],
    kitty: ["kitty", "--class", token, "--directory", path, "nvim", "--", path],
    foot: ["foot", "--app-id", token, "--working-directory", path, "nvim", "--", path],
    ghostty: [
      "ghostty",
      "--class=" + token,
      "--gtk-single-instance=false",
      "--working-directory=" + path,
      "-e",
      "nvim",
      "--",
      path
    ]
  }
  for (const id of Object.keys(expected)) {
    assert.deepEqual(plain(tools.launchSpec("editor", "nvim", path, token, id)), {
      argv: expected[id],
      cwd: path,
      expectedAppId: token,
      evidenceMode: "process-app-id"
    })
  }
  assert.equal(tools.launchSpec("editor", "nvim", path, token), null)
  assert.equal(tools.launchSpec("editor", "nvim", path, token, "unsupported"), null)
})
test("agent role runs fixed provider argv inside the selected terminal", () => {
  const expected = {
    alacritty: {
      claude: ["alacritty", "--class", token, "--working-directory", path, "--command", "claude"],
      codex: [
        "alacritty",
        "--class",
        token,
        "--working-directory",
        path,
        "--command",
        "codex",
        "--cd",
        path
      ]
    },
    ghostty: {
      claude: [
        "ghostty",
        "--class=" + token,
        "--gtk-single-instance=false",
        "--working-directory=" + path,
        "-e",
        "claude"
      ],
      codex: [
        "ghostty",
        "--class=" + token,
        "--gtk-single-instance=false",
        "--working-directory=" + path,
        "-e",
        "codex",
        "--cd",
        path
      ]
    },
    kitty: {
      claude: ["kitty", "--class", token, "--directory", path, "claude"],
      codex: ["kitty", "--class", token, "--directory", path, "codex", "--cd", path]
    },
    foot: {
      claude: ["foot", "--app-id", token, "--working-directory", path, "claude"],
      codex: ["foot", "--app-id", token, "--working-directory", path, "codex", "--cd", path]
    }
  }
  for (const terminalId of Object.keys(expected)) {
    for (const providerId of ["claude", "codex"]) {
      assert.deepEqual(plain(tools.launchSpec("agent", providerId, path, token, terminalId)), {
        argv: expected[terminalId][providerId],
        cwd: path,
        expectedAppId: token,
        evidenceMode: "process-app-id"
      })
    }
  }
})
test("agent role refuses unknown providers and missing terminals", () => {
  assert.equal(tools.launchSpec("agent", "gemini", path, token, "kitty"), null)
  assert.equal(tools.launchSpec("agent", "claude", path, token, undefined), null)
  assert.equal(tools.launchSpec("agent", "claude", path, "bad token", "kitty"), null)
  assert.equal(tools.launchSpec("agent", "claude", "relative", token, "kitty"), null)
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
