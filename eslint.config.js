// ESLint for the plugin logic modules. They are plain scripts (QML imports
// them; tests load them through a module.exports guard), so sourceType is
// "script". Two bridges start with QML's `.pragma library`, which is not
// JavaScript: the processor comments it out. QML `.import` aliases become
// declarations so their consumers remain linted. Replacements keep the same
// length as each directive, preserving original offsets for autofix ranges.
const js = require("@eslint/js")
const globals = require("globals")
const jsdoc = require("eslint-plugin-jsdoc")

// The documentation rules run in the docs stage of tools/check (it sets
// ARANEA_ESLINT_DOCS=1), so the lint stage stays about the code itself.
const docs = process.env.ARANEA_ESLINT_DOCS === "1"

const qmlPragma = {
  preprocess(text) {
    return [
      text
        .replace(/^\.pragma library$/m, (directive) => "//" + directive.slice(2))
        .replace(/^\.import[ \t]+"[^"\r\n]+"[ \t]+as[ \t]+(\w+)$/gm, (directive, alias) =>
          ("var " + alias + " = {}").padEnd(directive.length)
        )
    ]
  },
  postprocess(messages) {
    return messages.flat()
  },
  supportsAutofix: true
}

module.exports = [
  {
    ignores: ["node_modules/**", "coverage/**", "docs/superpowers/**", "branding/3d/live/vendor/**"]
  },
  {
    files: ["plugins/**/*.js"],
    plugins: { qml: { processors: { pragma: qmlPragma } } },
    processor: "qml/pragma",
    languageOptions: {
      // QML's JavaScript engine: keep the logic modules to ES2016 syntax.
      ecmaVersion: 2016,
      sourceType: "script",
      globals: { module: "readonly", Qt: "readonly", console: "readonly" }
    },
    rules: {
      ...js.configs.recommended.rules,
      // QML's engine needs a catch binding (no ES2019 "catch {"), so an
      // unused one is expected.
      "no-unused-vars": ["error", { caughtErrors: "none" }]
    }
  },
  {
    // The .pragma library bridges are called from QML: their top-level
    // functions are the public API, not unused code.
    files: [
      "plugins/araneadev.health/HealthBridge.js",
      "plugins/araneadev.audio/AudioBridge.js",
      "plugins/araneadev.notifications/ServiceBridge.js"
    ],
    rules: { "no-unused-vars": ["error", { vars: "local", caughtErrors: "none" }] }
  },
  {
    files: ["tests/js/**/*.js", "eslint.config.js", "tools/**/*.js"],
    languageOptions: { ecmaVersion: 2023, sourceType: "commonjs", globals: { ...globals.node } },
    rules: { ...js.configs.recommended.rules }
  },
  {
    files: ["tools/**/*.mjs"],
    languageOptions: { ecmaVersion: 2023, sourceType: "module", globals: { ...globals.node } },
    rules: { ...js.configs.recommended.rules }
  },
  {
    files: [
      "branding/3d/live/*.mjs",
      "branding/3d/live/dismiss.js",
      "branding/3d/collection/**/*.mjs"
    ],
    languageOptions: { ecmaVersion: 2023, sourceType: "module", globals: { ...globals.browser } },
    rules: { ...js.configs.recommended.rules }
  },
  {
    files: ["tests/js/**/*.mjs"],
    languageOptions: { ecmaVersion: 2023, sourceType: "module", globals: { ...globals.node } },
    rules: { ...js.configs.recommended.rules }
  },
  ...(docs
    ? [
        {
          files: ["plugins/**/*.js"],
          plugins: { jsdoc },
          rules: {
            "jsdoc/require-jsdoc": ["error", { require: { FunctionDeclaration: true } }],
            "jsdoc/require-description": "error",
            "jsdoc/require-param": "error",
            "jsdoc/require-param-type": "error",
            "jsdoc/require-param-name": "error",
            "jsdoc/check-param-names": "error",
            "jsdoc/require-returns": "error",
            "jsdoc/require-returns-type": "error",
            "jsdoc/check-types": "error",
            "jsdoc/valid-types": "error",
            "jsdoc/no-undefined-types": "error"
          }
        },
        {
          files: ["tests/js/**/*.js", "tools/**/*.js", "tools/**/*.mjs", "eslint.config.js"],
          plugins: { jsdoc },
          rules: {
            "jsdoc/require-jsdoc": ["error", { require: { FunctionDeclaration: true } }],
            "jsdoc/require-description": "error"
          }
        }
      ]
    : [])
]
