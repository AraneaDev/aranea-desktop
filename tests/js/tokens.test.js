const assert = require("node:assert/strict")
const { test } = require("node:test")

const generatorPromise = import("../../tools/token-generator.mjs")

const fixture = {
  mode: "dark",
  colors: {
    accent: "#3bff9e",
    accent_secondary: "#7a5cff",
    ceremony: "#e6c98a",
    background: "#08090b",
    lighter_background: "#10151b",
    surface_raised: "#151c24",
    foreground: "#edf3f6",
    dark_foreground: "#8b96a6",
    red: "#ff5f56"
  },
  dimensions: {
    cornerRadius: 10
  },
  motion: {
    enabled: true,
    reduced_motion_fallback: "static"
  },
  shell: {
    bar: {
      background: "#06090d",
      "background-alpha": 0.82
    }
  }
}

test("flattenTokens exposes canonical dotted token paths", async () => {
  const { flattenTokens } = await generatorPromise
  assert.deepEqual(flattenTokens(fixture), {
    mode: "dark",
    "colors.accent": "#3bff9e",
    "colors.accent_secondary": "#7a5cff",
    "colors.ceremony": "#e6c98a",
    "colors.background": "#08090b",
    "colors.lighter_background": "#10151b",
    "colors.surface_raised": "#151c24",
    "colors.foreground": "#edf3f6",
    "colors.dark_foreground": "#8b96a6",
    "colors.red": "#ff5f56",
    "dimensions.cornerRadius": 10,
    "motion.enabled": true,
    "motion.reduced_motion_fallback": "static",
    "shell.bar.background": "#06090d",
    "shell.bar.background-alpha": 0.82
  })
})

test("token validation rejects missing required sections", async () => {
  const { validateTokens } = await generatorPromise
  assert.throws(() => validateTokens({ colors: {} }), /mode|shell|dimensions/)
})

test("renderColorsToml keeps host-compatible flat color keys", async () => {
  const { renderColorsToml } = await generatorPromise
  const output = renderColorsToml(fixture)
  assert.match(output, /^mode = "dark"$/m)
  assert.match(output, /^accent = "#3bff9e"$/m)
  assert.match(output, /^corner_radius = 10$/m)
})

test("renderShellToml renders nested shell sections", async () => {
  const { renderShellToml } = await generatorPromise
  const output = renderShellToml(fixture)
  assert.match(output, /^\[bar\]$/m)
  assert.match(output, /^background-alpha = 0\.82$/m)
})

test("renderQmlTokens exposes stable shared token aliases", async () => {
  const { renderQmlTokens } = await generatorPromise
  const output = renderQmlTokens(fixture)
  assert.match(output, /readonly property color accent: Color\.accent/)
  assert.match(output, /readonly property int cornerRadius: Style\.cornerRadius/)
})

test("renderIntegrationCss projects semantic palette variables", async () => {
  const { renderIntegrationCss } = await generatorPromise
  const output = renderIntegrationCss(fixture)
  assert.match(output, /--aranea-accent: #3bff9e;/)
  assert.match(output, /--aranea-background: #08090b;/)
  assert.match(output, /--aranea-error: #ff5f56;/)
})

test("renderTemplate supports format-specific projections", async () => {
  const { renderTemplate } = await generatorPromise
  assert.equal(renderTemplate("fg={{colors.accent}} raw={{colors.accent|hex}}", fixture), "fg=#3bff9e raw=3bff9e")
})
