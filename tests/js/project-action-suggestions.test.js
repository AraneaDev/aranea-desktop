const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const S = loadPragma("plugins/araneadev.projects/ProjectActionSuggestions.js")
const plain = (value) => JSON.parse(JSON.stringify(value))

const row = (source, cwd, entry, argv, extra = {}) => ({
  key: `${source}:${cwd}:${entry}`,
  source,
  sourcePath: cwd === "." ? "package.json" : `${cwd}/package.json`,
  entry,
  label: cwd === "." ? entry : `${cwd} · ${entry}`,
  definition: { name: entry, kind: "command", argv, cwdRelative: cwd, timeoutSeconds: 300, previewUrl: null },
  previewEvidence: null,
  alreadySaved: false,
  ...extra
})

test("live definitions hide saved suggestions even when the cache says unsaved", () => {
  const detection = {
    suggestions: [
      row("package.json", ".", "test", ["npm", "run", "test"]),
      row("package.json", ".", "build", ["npm", "run", "build"]),
      row("package.json", ".", "lint", ["npm", "run", "lint"], { alreadySaved: true })
    ]
  }
  const saved = [{ argv: ["npm", "run", "test"], cwdRelative: "." }]
  assert.deepEqual(
    plain(S.pending(detection, saved).map((r) => r.entry)),
    ["build", "lint"]
  )
  assert.deepEqual(plain(S.pending(null, saved)), [])
  assert.deepEqual(plain(S.pending({ suggestions: "bad" }, [])), [])
})

test("groups put the root first, then paths, with stable source order", () => {
  const rows = [
    row("makefile", ".", "build", ["make", "build"]),
    row("package.json", "apps/web", "dev", ["npm", "run", "dev"]),
    row("package.json", ".", "test", ["npm", "run", "test"]),
    row("package.json", "apps/api", "dev", ["npm", "run", "dev"])
  ]
  assert.deepEqual(plain(S.groups(rows)).map((g) => [g.path, g.title, g.rows.map((r) => r.entry)]), [
    [".", "Repository root", ["test", "build"]],
    ["apps/api", "apps/api", ["dev"]],
    ["apps/web", "apps/web", ["dev"]]
  ])
})

test("overview picks prefer root test, dev and build", () => {
  const rows = [
    row("package.json", "apps/web", "dev", ["npm", "run", "dev"]),
    row("package.json", ".", "lint", ["npm", "run", "lint"]),
    row("python", ".", "pytest", ["pytest"]),
    row("package.json", ".", "start", ["npm", "run", "start"]),
    row("makefile", ".", "build", ["make", "build"])
  ]
  assert.deepEqual(
    plain(S.overviewPicks(rows).map((r) => r.key)),
    ["python:.:pytest", "package.json:.:start", "makefile:.:build"]
  )
  assert.deepEqual(
    plain(S.overviewPicks([row("package.json", "apps/web", "dev", ["x"])]).map((r) => r.key)),
    ["package.json:apps/web:dev"]
  )
  assert.deepEqual(plain(S.overviewPicks([])), [])
})

test("add plan respects the per-project limit", () => {
  const rows = [1, 2, 3].map((n) => row("makefile", ".", `t${n}`, ["make", `t${n}`]))
  assert.deepEqual(plain(S.addPlan(rows, 0)).capacity, 50)
  assert.equal(S.addPlan(rows, 0).limited, false)
  const tight = S.addPlan(rows, 48)
  assert.equal(tight.capacity, 2)
  assert.equal(tight.limited, true)
  assert.deepEqual(plain(tight.rows.map((r) => r.entry)), ["t1", "t2"])
  assert.equal(S.addPlan(rows, 60).capacity, 0)
})

test("lines and notes are readable", () => {
  const dev = row("package.json", "apps/web", "dev", ["pnpm", "run", "dev"], { previewEvidence: "Vite default port" })
  dev.definition.previewUrl = "http://127.0.0.1:5173/"
  assert.equal(S.sourceLine(dev), "apps/web · package.json · pnpm run dev")
  assert.equal(S.previewLine(dev), "127.0.0.1:5173 · Vite default port")
  assert.equal(S.previewLine(row("makefile", ".", "x", ["make", "x"])), "")
  const bare = row("package.json", ".", "serve", ["npm", "run", "serve"])
  bare.definition.previewUrl = "http://127.0.0.1:9000/"
  assert.equal(S.previewLine(bare), "127.0.0.1:9000")
  assert.equal(S.sourceLine(row("makefile", ".", "x", ["make", "x"])), "Makefile · make x")
  assert.equal(
    S.sourceNote([
      { source: "cargo", status: "unavailable", reason: "Needs python3" },
      { source: "justfile", status: "unavailable", reason: "Needs just" },
      { source: "package.json", status: "invalid", reason: "apps/x/package.json could not be read." },
      { source: "makefile", status: "found", reason: null },
      { source: "python", status: "truncated", reason: "Detection time limit reached." }
    ]),
    "Not checked: Cargo (needs python3), justfile (needs just) · apps/x/package.json could not be read. · Detection time limit reached."
  )
  assert.equal(S.sourceNote([]), "")
  assert.equal(S.sourceNote(null), "")
  assert.equal(S.sourceName("unknown"), "unknown")
})
