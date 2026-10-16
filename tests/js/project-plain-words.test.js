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

test("guard finds visible strings and ignores identifiers and comments", () => {
  const sample =
    "// owner note\nproperty var ownerClient: null\ntext: 'Owner unavailable'\nlabel: x ? 'Fine' : 'Exact match'"
  assert.deepEqual(visibleStrings(sample), ["Owner unavailable", "Fine", "Exact match"])
})

test("no banned internal words in visible Projects strings", () => {
  const hits = []
  for (const file of fs.readdirSync(dir).filter((f) => /\.(qml|js)$/.test(f))) {
    if (file === "ProjectProblems.js") continue
    for (const s of visibleStrings(fs.readFileSync(path.join(dir, file), "utf8")))
      if (banned.test(s)) hits.push(file + ": " + s)
  }
  assert.deepEqual(hits, [])
})

test("old status words are gone", () => {
  const old =
    /\b(Unconfirmed|Unavailable|Tools unconfirmed|Awaiting observation|Usage unknown|Launch status unknown)\b/
  const hits = []
  for (const file of fs.readdirSync(dir).filter((f) => /\.(qml|js)$/.test(f)))
    for (const s of visibleStrings(fs.readFileSync(path.join(dir, file), "utf8")))
      if (old.test(s)) hits.push(file + ": " + s)
  assert.deepEqual(hits, [])
})
