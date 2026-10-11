const { test } = require("node:test")
const assert = require("node:assert/strict")
const { ESLint } = require("eslint")
const jsdoc = require("eslint-plugin-jsdoc")
const { Script } = require("node:vm")
const lint = new ESLint()
const filePath = "plugins/araneadev.projects/AgentSuggestion.js"

test("QML import aliases pass lint while their JS consumers remain checked", async () => {
  const [result] = await lint.lintText(
    '.import "../araneadev.agents/AgentsLogic.js" as AgentsLogic\n' +
      "function suggest() { return AgentsLogic.ringFraction([]) }\n" +
      "module.exports = { suggest }\n",
    { filePath }
  )
  assert.deepEqual(result.messages, [])
})

test("QML import preprocessing preserves undefined-name diagnostics and line numbers", async () => {
  const [result] = await lint.lintText(
    '.import "../araneadev.agents/AgentsLogic.js" as AgentsLogic\n' +
      "function suggest() {\n" +
      "  return AgentsLogic.ringFraction(missingLimits)\n" +
      "}\nmodule.exports = { suggest }\n",
    { filePath }
  )
  assert.equal(result.messages.length, 1)
  assert.equal(result.messages[0].ruleId, "no-undef")
  assert.equal(result.messages[0].message, "'missingLimits' is not defined.")
  assert.equal(result.messages[0].line, 3)
})

for (const [name, directives, value] of [
  [
    "import",
    '.import "../araneadev.agents/AgentsLogic.js" as AgentsLogic\n',
    "AgentsLogic.ringFraction([])"
  ],
  ["pragma", ".pragma library\n", "[]"],
  [
    "pragma and import",
    '.pragma library\n.import "../araneadev.agents/AgentsLogic.js" as AgentsLogic\n',
    "AgentsLogic.ringFraction([])"
  ]
]) {
  test("JSDoc autofix preserves " + name + " directives and the following JS body", async () => {
    const fixer = new ESLint({
      fix: true,
      overrideConfig: {
        plugins: { jsdoc },
        rules: { "jsdoc/require-jsdoc": ["error", { require: { FunctionDeclaration: true } }] }
      }
    })
    const body = "function suggest() { return " + value + " }\nmodule.exports = { suggest }\n"
    const [result] = await fixer.lintText(directives + body, { filePath })
    assert.equal(result.output, directives + "/**\n *\n */\n" + body)
    assert.equal(
      result.messages.some((m) => m.fatal || m.ruleId === "jsdoc/require-jsdoc"),
      false
    )
    assert.doesNotThrow(() => new Script(result.output.replace(/^\.(?:pragma|import).*$/gm, "")))
  })
}
