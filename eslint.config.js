// ESLint for the plugin logic modules. They are plain scripts (QML imports
// them; tests load them through a module.exports guard), so sourceType is
// "script". Two bridges start with QML's `.pragma library`, which is not
// JavaScript: the processor comments it out, keeping line numbers.
const js = require("@eslint/js")
const globals = require("globals")

const qmlPragma = {
  preprocess(text) {
    return [text.replace(/^\.pragma library$/m, "// .pragma library")]
  },
  postprocess(messages) {
    return messages.flat()
  },
  supportsAutofix: true
}

module.exports = [
  { ignores: ["node_modules/**", "coverage/**", "docs/superpowers/**"] },
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
      "plugins/araneadev.notifications/ServiceBridge.js"
    ],
    rules: { "no-unused-vars": ["error", { vars: "local", caughtErrors: "none" }] }
  },
  {
    files: ["tests/js/**/*.js", "eslint.config.js", "tools/**/*.js"],
    languageOptions: { ecmaVersion: 2023, sourceType: "commonjs", globals: { ...globals.node } },
    rules: { ...js.configs.recommended.rules }
  }
]
