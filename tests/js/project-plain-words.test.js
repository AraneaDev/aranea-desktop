const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { loadPragma } = require("./lib/load-pragma.js")
const { BANNED } = loadPragma("plugins/araneadev.projects/ProjectProblems.js")
const dir = path.join(__dirname, "../../plugins/araneadev.projects")
const banned = new RegExp("\\b(" + BANNED.join("|") + ")\\b", "i")

/**
 * User-visible string literals in one QML/JS source: values of text:, label:, title:,
 * placeholderText:, ToolTip.text:, message:/body: inside UI objects, and strings
 * returned from functions named *Label/*Text/*Note/*Reason/summary.
 * @param {string} source - file contents
 * @returns {string[]} visible literals
 */
function visibleStrings(source) {
  const out = []
  const noComments = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1")
  const prop =
    /\b(text|label|title|placeholderText|ToolTip\.text|searchPlaceholder)\s*:\s*([^\n]+)/g
  let m
  while ((m = prop.exec(noComments)))
    for (const s of m[2].matchAll(/'([^'\\]*(?:\\.[^'\\]*)*)'|"([^"\\]*(?:\\.[^"\\]*)*)"/g))
      out.push(s[1] ?? s[2])
  return out
}

/**
 * Visible string literals in a presentation JS source. Every literal counts except
 * comparison operands, case labels, object keys, ALL_CAPS codes and lowercase
 * identifier-like values such as state names.
 * @param {string} source - file contents
 * @returns {string[]} visible literals
 */
function jsVisibleStrings(source) {
  const out = []
  const noComments = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1")
  const lit = /'([^'\\\n]*(?:\\.[^'\\\n]*)*)'|"([^"\\\n]*(?:\\.[^"\\\n]*)*)"/g
  let m
  while ((m = lit.exec(noComments))) {
    const value = m[1] ?? m[2]
    const before = noComments.slice(0, m.index)
    const after = noComments.slice(m.index + m[0].length)
    if (/(===?|!==?|\bcase|\.indexOf\(|\brequire\(|\btypeof [\w.]+ ===?)\s*$/.test(before)) continue
    if (/^\s*(===?|!==?)/.test(after)) continue
    if (/^\s*:/.test(after) && /[{,]\s*$/.test(before)) continue
    if (/^[A-Z][A-Z0-9_]*$/.test(value)) continue
    // Raw lowercase state values assigned to a status field are data, not text.
    const lineStart = before.slice(before.lastIndexOf("\n") + 1)
    if (/^[a-z]+$/.test(value) && /\bstatus\s*[:=][^\n]*$/.test(lineStart)) continue
    if (/^[a-z][a-z0-9_.-]*$/.test(value) && !/^(unavailable|unknown)$/.test(value)) continue
    out.push(value)
  }
  return out
}

/**
 * Scan every Projects source for strings matching a pattern.
 * @param {function(string): string[]} fn - QML-property scanner
 * @param {RegExp} pattern - pattern to flag
 * @param {function(string): string[]} jsFn - JS literal scanner, applied to .js files too
 * @returns {string[]} "file: string" hits
 */
function scanAll(fn, pattern, jsFn) {
  const hits = []
  for (const file of fs.readdirSync(dir).filter((f) => /\.(qml|js)$/.test(f))) {
    if (file === "ProjectProblems.js") continue
    const source = fs.readFileSync(path.join(dir, file), "utf8")
    const strings = new Set(fn(source))
    if (file.endsWith(".js")) for (const s of jsFn(source)) strings.add(s)
    for (const s of strings) if (pattern.test(s)) hits.push(file + ": " + s)
  }
  return hits
}

test("JS scanner includes UI text and excludes codes, comparisons and keys", () => {
  const sample = [
    "// owner comment",
    "var a = x === 'Owner state' ? 1 : 2",
    "if (s.status !== 'unconfirmed') return",
    "switch (k) { case 'observed': break }",
    "var o = { observed: 1, 'quoted': 2 }",
    "var c = 'ACCEPTANCE_UNKNOWN'",
    "var d = r.indexOf('observed')",
    "return { status: 'Observed tools', detail: 'Receipt kept', tooltip: 'Exact match' }",
    "var t = reason || 'Usage unknown'",
    "text = 'Awaiting observation'",
    "var labels = { failed: 'Command failed', unconfirmed: 'Unconfirmed' }",
    "var long = ok",
    "  ? 'Fine'",
    "  : 'Unavailable'",
    "var low = 'unavailable'",
    "var id = 'unconfirmed'",
    "task.status = 'unavailable'",
    "  status: ok ? 'suppressed' : 'unavailable',",
    "  message: 'unavailable'"
  ].join("\n")
  assert.deepEqual(jsVisibleStrings(sample), [
    "Observed tools",
    "Receipt kept",
    "Exact match",
    "Usage unknown",
    "Awaiting observation",
    "Command failed",
    "Unconfirmed",
    "Fine",
    "Unavailable",
    "unavailable",
    "unavailable"
  ])
})

test("guard finds visible strings and ignores identifiers and comments", () => {
  const sample =
    "// owner note\nproperty var ownerClient: null\ntext: 'Owner unavailable'\nlabel: x ? 'Fine' : 'Exact match'"
  assert.deepEqual(visibleStrings(sample), ["Owner unavailable", "Fine", "Exact match"])
})

test("no banned internal words in visible Projects strings", () => {
  assert.deepEqual(scanAll(visibleStrings, banned, jsVisibleStrings), [])
})

test("old status words are gone", () => {
  const old =
    /\b(Unconfirmed|Unavailable|Tools unconfirmed|Awaiting observation|Usage unknown|Launch status unknown)\b/i
  assert.deepEqual(scanAll(visibleStrings, old, jsVisibleStrings), [])
})

/**
 * String literals on QML lines that assign or return user-visible text through
 * error/return forms the property scanner does not see.
 * @param {string} source - file contents
 * @returns {string[]} literals from those lines
 */
function assignedStrings(source) {
  const out = []
  const noComments = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1")
  for (const line of noComments.split("\n"))
    if (/\b(return\s|error\s*=|\w*Error\s*:|\w*Hint\s*:)/i.test(line))
      for (const s of line.matchAll(/'([^'\\]*(?:\\.[^'\\]*)*)'|"([^"\\]*(?:\\.[^"\\]*)*)"/g)) {
        if (/[=!]==?\s*$/.test(line.slice(0, s.index))) continue
        out.push(s[1] ?? s[2])
      }
  return out
}

test("assignment and return forms say not available instead of unavailable", () => {
  const sample =
    "error = 'Folder chooser unavailable.'\nreturn x || 'unavailable'\nvar code = 'unavailable'\nreturn s.status === 'unavailable'"
  assert.deepEqual(assignedStrings(sample), ["Folder chooser unavailable.", "unavailable"])
  assert.deepEqual(
    scanAll(assignedStrings, /\bunavailable\b/i, () => []),
    []
  )
})

const agentsDir = path.join(__dirname, "../../plugins/araneadev.agents")
const agentFiles = ["AgentTasksLogic.js", "AgentTaskDetails.qml", "AgentTasks.qml"]
const oldStatus =
  /\b(Unconfirmed|Unavailable|Tools unconfirmed|Awaiting observation|Usage unknown|Launch status unknown)\b/i

/**
 * Every visible-string scanner applied to the shared agent task view, which
 * Projects shows under Agents. Same patterns, no allowlist.
 * @returns {string[]} unique "file: string" entries
 */
function agentStrings() {
  const out = []
  for (const file of agentFiles) {
    const source = fs.readFileSync(path.join(agentsDir, file), "utf8")
    const strings = new Set([
      ...visibleStrings(source),
      ...assignedStrings(source),
      ...jsVisibleStrings(source)
    ])
    for (const s of strings) out.push(file + ": " + s)
  }
  return out
}

test("agent task view has no banned internal words in visible strings", () => {
  assert.deepEqual(
    agentStrings().filter((s) => banned.test(s.replace(/^[^:]*: /, ""))),
    []
  )
})

test("agent task view has no old status words", () => {
  assert.deepEqual(
    agentStrings().filter((s) => oldStatus.test(s.replace(/^[^:]*: /, ""))),
    []
  )
})

const pluginsDir = path.join(__dirname, "../../plugins")

/**
 * Every visible-string scanner applied to all QML/JS sources of one plugin.
 * Same patterns, no allowlist.
 * @param {string} plugin - plugin directory name
 * @returns {string[]} unique "file: string" entries
 */
function pluginStrings(plugin) {
  const base = path.join(pluginsDir, plugin)
  const out = []
  for (const file of fs.readdirSync(base).filter((f) => /\.(qml|js)$/.test(f))) {
    const source = fs.readFileSync(path.join(base, file), "utf8")
    const strings = new Set([
      ...visibleStrings(source),
      ...assignedStrings(source),
      ...jsVisibleStrings(source)
    ])
    for (const s of strings) out.push(file + ": " + s)
  }
  return out
}

for (const plugin of ["araneadev.activity", "araneadev.workspaces"]) {
  test(plugin + " has no banned internal words in visible strings", () => {
    assert.deepEqual(
      pluginStrings(plugin).filter((s) => banned.test(s.replace(/^[^:]*: /, ""))),
      []
    )
  })
  test(plugin + " has no old status words", () => {
    assert.deepEqual(
      pluginStrings(plugin).filter((s) => oldStatus.test(s.replace(/^[^:]*: /, ""))),
      []
    )
  })
}
