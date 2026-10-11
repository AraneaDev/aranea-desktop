const { test } = require("node:test")
const assert = require("node:assert/strict")
const { ESLint } = require("eslint")
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
