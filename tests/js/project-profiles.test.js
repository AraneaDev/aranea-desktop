const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const profiles = loadPragma("plugins/araneadev.projects/ProjectProfiles.js")
const tool = (id) => ({ id, available: true, supported: true })
const probes = (editors = [], terminals = [], agents = []) => ({
  editors: editors.map(tool),
  terminals: terminals.map(tool),
  agents: agents.map(tool)
})
const plain = (value) => JSON.parse(JSON.stringify(value))
test("missing agents leave an editor-only preset usable", () => {
  const tools = probes(["code"])
  const drafts = profiles.presets(tools)
  assert.equal(drafts[0].name, "VS Code")
  assert.deepEqual(plain(drafts[0].roles), ["editor"])
  assert.equal(profiles.resolve(drafts[0], tools).ok, true)
})
test("installed subsets produce only usable presets and no probe writes", () => {
  for (const [tools, names] of [
    [probes([], ["kitty"]), ["Terminal"]],
    [probes(["nvim"], ["kitty"]), ["Neovim", "Terminal"]],
    [probes([], ["kitty"], ["claude"]), ["Terminal + Agent", "Terminal"]],
    [probes([], [], ["claude"]), []],
    [probes(["nvim"]), []],
    [probes(), []]
  ]) {
    const before = JSON.stringify(tools)
    const drafts = profiles.presets(tools)
    assert.deepEqual(plain(drafts.map((p) => p.name)), names)
    assert.ok(drafts.every((p) => profiles.resolve(p, tools).ok))
    assert.equal(JSON.stringify(tools), before)
  }
})
test("available defaults and both provider choices resolve without mutating saved defaults", () => {
  const tools = probes(["code", "nvim"], ["kitty", "foot"], ["claude", "codex"])
  tools.defaults = { editorId: "nvim", terminalId: "foot", agentId: "codex" }
  const saved = {
    name: "Default",
    roles: ["editor", "agent"],
    tools: { editorId: null, terminalId: null, agentId: null }
  }
  assert.deepEqual(plain(profiles.resolve(saved, tools).tools), {
    editorId: "nvim",
    terminalId: "foot",
    agentId: "codex"
  })
  assert.equal(saved.tools.editorId, null)
  const agent = profiles.presets(tools).find((p) => p.name === "Terminal + Agent")
  assert.equal(agent.tools.agentId, "codex")
  agent.tools.agentId = "claude"
  assert.equal(profiles.resolve(agent, tools).ok, true)
})
test("unavailable saved adapters stay unresolved, dependencies have actionable errors", () => {
  const tools = probes(["code"], ["kitty"], ["codex"])
  for (const [roles, choices] of [
    [["editor"], { editorId: "nvim" }],
    [["agent"], { agentId: "claude" }],
    [["terminal"], { terminalId: "foot" }]
  ]) {
    const result = profiles.resolve({ roles, tools: choices }, tools)
    assert.equal(result.ok, false)
    assert.match(result.error, /Choose/)
  }
  assert.match(
    profiles.resolve({ roles: ["editor"], tools: { editorId: "nvim" } }, probes(["nvim"])).error,
    /terminal/i
  )
  assert.match(
    profiles.resolve({ roles: ["agent"], tools: { agentId: "codex" } }, probes([], [], ["codex"]))
      .error,
    /terminal/i
  )
  assert.equal(profiles.resolve({ roles: [], tools: {} }, tools).ok, false)
  assert.equal(profiles.resolve({ roles: ["invalid"], tools: {} }, tools).ok, false)
  tools.editors[0].supported = false
  assert.equal(
    profiles.presets(tools).some((p) => p.name === "VS Code"),
    false
  )
})
test("remembered resolves only the actual existing choice", () => {
  const saved = { id: "f-one", name: "<b>Work</b>", revision: 3 }
  assert.equal(profiles.remembered({ profiles: [saved], lastProfileId: "f-one" }), saved)
  assert.equal(profiles.remembered({ profiles: [saved], lastProfileId: "removed" }), null)
  assert.equal(profiles.remembered({ profiles: [saved] }), null)
})
test("human tool summaries name adapters and explain terminal dependencies", () => {
  const tools = probes(["code", "nvim"], ["kitty"], ["codex"])
  tools.editors[0].label = "VS Code"
  tools.editors[1].label = "Neovim"
  tools.terminals[0].label = "Kitty"
  tools.agents[0].label = "Codex"
  assert.equal(
    profiles.summary({ roles: ["editor"], tools: { editorId: "code" } }, tools),
    "VS Code"
  )
  assert.equal(
    profiles.summary(
      { roles: ["terminal", "agent"], tools: { terminalId: "kitty", agentId: "codex" } },
      tools
    ),
    "Kitty terminal + Codex"
  )
  assert.equal(
    profiles.summary(
      { roles: ["editor"], tools: { editorId: "nvim", terminalId: "kitty" } },
      tools
    ),
    "Neovim in Kitty terminal"
  )
})

test("primary falls back from an unusable remembered profile without persisting", () => {
  const unavailable = {
    id: "missing",
    name: "Neovim",
    roles: ["editor"],
    tools: { editorId: "nvim" }
  }
  const usable = {
    id: "available",
    name: "VS Code",
    roles: ["editor"],
    tools: { editorId: "code" }
  }
  const project = { lastProfileId: null, profiles: [unavailable, usable] }
  const before = JSON.stringify(project)
  assert.equal(profiles.primary(project, probes(["code"])).id, "available")
  assert.equal(JSON.stringify(project), before)
  assert.equal(profiles.remembered(project), null)
  assert.equal(profiles.primary(project, probes()), null)
  assert.equal(profiles.primary(null, probes(["code"])), null)
  project.lastProfileId = "missing"
  assert.equal(profiles.primary(project, probes(["code"])).id, "available")
  assert.equal(
    profiles.fallbackNote(project, probes(["code"])),
    "Neovim isn't available \u2014 using VS Code."
  )
  project.lastProfileId = "available"
  assert.equal(profiles.primary(project, probes(["code"])).id, "available")
  assert.equal(profiles.fallbackNote(project, probes(["code"])), "")
  project.lastProfileId = "removed"
  assert.equal(profiles.primary(project, probes(["code"])).id, "available")
  assert.equal(profiles.fallbackNote(project, probes(["code"])), "")
  assert.equal(profiles.fallbackNote(project, probes()), "")
  assert.equal(JSON.stringify(project.profiles), JSON.stringify([unavailable, usable]))
  assert.equal(profiles.primary({ lastProfileId: null }, probes(["code"])), null)
})

test("blocked reasons distinguish no tools, unusable profiles and seeding", () => {
  const nvim = { id: "n", name: "Neovim", roles: ["editor"], tools: { editorId: "nvim" } }
  assert.equal(profiles.blockedReason({ profiles: [] }, probes()), "")
  assert.equal(profiles.blockedReason({}, probes()), "")
  assert.equal(profiles.blockedReason(null, probes()), "")
  assert.equal(
    profiles.blockedReason({ profiles: [nvim] }, probes()),
    "Install a supported editor or terminal (VS Code, Neovim, Kitty, Alacritty, Foot or Ghostty), then Refresh."
  )
  assert.match(
    profiles.blockedReason({ profiles: [nvim] }, probes(["code"])),
    /^None of this project's profiles can start: /
  )
  assert.equal(profiles.blockedReason({ profiles: [nvim] }, probes(["nvim"], ["kitty"])), "")
  assert.equal(profiles.usable(nvim, probes(["code"])), false)
  assert.equal(profiles.usable(nvim, probes(["nvim"], ["kitty"])), true)
})

test("JS presets match the backend preset rule", () => {
  const { execFileSync } = require("node:child_process")
  const fixtures = [
    probes(["code", "nvim"], ["alacritty", "kitty"], ["claude"]),
    probes([], ["foot"], []),
    probes(["code"], [], ["codex"]),
    probes()
  ]
  fixtures[0].defaults = { terminalId: "kitty" }
  for (const tools of fixtures) {
    const backend = JSON.parse(
      execFileSync(
        "jq",
        [
          "-cn",
          "--argjson",
          "tools",
          JSON.stringify(tools),
          "-f",
          "scripts/lib/project-presets.jq"
        ],
        { encoding: "utf8" }
      )
    )
    assert.deepEqual(plain(profiles.presets(tools)), backend)
  }
})
