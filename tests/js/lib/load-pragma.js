// Loads a QML `.pragma library` script (plain JS apart from that first line)
// into a fresh context, so node can test it and coverage counts it under its
// own path. The pragma line becomes blank, keeping line numbers.
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

/**
 * Evaluates a `.pragma library` file and returns its globals.
 * @param {string} file - path to the script, relative to the repository root
 * @returns {Object<string, *>} the script's top-level functions and variables
 */
function loadPragma(file) {
  const absolute = path.join(__dirname, "..", "..", "..", file)
  const context = vm.createContext({ Date })
  loadIntoContext(absolute, context)
  return context
}

/** Evaluates one QML JS module and its relative `.import` dependencies. */
function loadIntoContext(absolute, context) {
  let source = fs.readFileSync(absolute, "utf8").replace(/^\.pragma library$/m, "")
  const imports = [...source.matchAll(/^\.import\s+"([^"]+)"\s+as\s+(\w+)$/gm)]
  for (const [, relative, name] of imports) {
    const dependency = vm.createContext({ Date })
    loadIntoContext(path.resolve(path.dirname(absolute), relative), dependency)
    context[name] = dependency
  }
  source = source.replace(/^\.import.*$/gm, "")
  vm.runInContext(source, context, { filename: absolute })
}

module.exports = { loadPragma }
