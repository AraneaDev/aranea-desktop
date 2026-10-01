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
    red: "#ff5f56",
    bright_green: "#abcdef",
    cyan: "#123456",
    mark_start: "#a1b2c3",
    mark_mid: "#d4e5f6",
    mark_end: "#0a1b2c"
  },
  dimensions: {
    surfaceBorderAlpha: 0.48
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
    "colors.bright_green": "#abcdef",
    "colors.cyan": "#123456",
    "colors.mark_start": "#a1b2c3",
    "colors.mark_mid": "#d4e5f6",
    "colors.mark_end": "#0a1b2c",
    "dimensions.surfaceBorderAlpha": 0.48,
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

test("dimensions need no corner radius: the radius follows Hyprland", async () => {
  const { validateTokens } = await generatorPromise
  assert.doesNotThrow(() => validateTokens({ ...fixture, dimensions: {} }))
})

test("renderColorsToml keeps host-compatible flat color keys", async () => {
  const { renderColorsToml } = await generatorPromise
  const output = renderColorsToml(fixture)
  assert.match(output, /^mode = "dark"$/m)
  assert.match(output, /^accent = "#3bff9e"$/m)
  assert.match(output, /^surface_border_alpha = 0\.48$/m)
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
  assert.match(output, /readonly property int borderWidth: Math\.max\(1, Style\.space\(2\)\)/)
  assert.match(output, /readonly property bool motionEnabled: MotionState\.motionEnabled/)
})

test("renderQmlTokens draws the filament's far end in Aranea's violet", async () => {
  const { renderQmlTokens } = await generatorPromise
  const output = renderQmlTokens({
    ...fixture,
    colors: { ...fixture.colors, accent_secondary: "#123456" }
  })
  assert.match(output, /readonly property color strandEnd: "#123456"/)
  assert.match(output, /readonly property color accentSecondary: Color\.menu\.selectedText/)
})

test("renderIntegrationCss projects semantic palette variables", async () => {
  const { renderIntegrationCss } = await generatorPromise
  const output = renderIntegrationCss(fixture)
  assert.match(output, /--aranea-accent: #3bff9e;/)
  assert.match(output, /--aranea-background: #08090b;/)
  assert.match(output, /--aranea-error: #ff5f56;/)
  assert.match(output, /--aranea-ceremony: #e6c98a;/)
})

test("renderQmlTokens exposes semantic colors used by branding consumers", async () => {
  const { renderQmlTokens } = await generatorPromise
  const output = renderQmlTokens(fixture)
  assert.match(output, /readonly property color ceremony: Color\.notifications\.countdown/)
  assert.match(output, /readonly property color attention: Color\.notifications\.countdown/)
  assert.match(output, /readonly property color lockOverlay: Color\.lock\.background/)
})

test("renderBrandShellEnv produces shell-safe visible identity values", async () => {
  const { renderBrandShellEnv } = await generatorPromise
  const output = renderBrandShellEnv({
    identity: {
      name: "Example Desktop",
      short_name: "EXAMPLE",
      tagline: "A different signal.",
      palette_name: "ink / lime",
      lock_subtitle: "PRIVATE SESSION",
      ceremony_title: "EXAMPLE THEME CHANGE",
      ceremony_detail: "CEREMONY: example mark"
    },
    assets: { mark: "branding/marks/aranea-primary.svg" }
  })
  assert.match(output, /^BRAND_NAME='Example Desktop'$/m)
  assert.match(output, /^BRAND_SHORT_NAME='EXAMPLE'$/m)
})

test("canonicalPng removes rasterizer-specific ancillary chunks", async () => {
  const { canonicalPng } = await generatorPromise
  const fs = require("node:fs")
  const png = fs.readFileSync("branding/screens/plymouth.png")
  const ancillary = Buffer.from("0000000662474b4400ff00ff00ff00000000", "hex")
  const withMetadata = Buffer.concat([png.subarray(0, 33), ancillary, png.subarray(33)])
  const canonical = canonicalPng(withMetadata)
  assert.equal(canonical.includes(Buffer.from("bKGD")), false)
  assert.equal(canonical.subarray(0, 8).equals(png.subarray(0, 8)), true)
})

test("renderTemplate supports format-specific projections", async () => {
  const { renderTemplate } = await generatorPromise
  assert.equal(
    renderTemplate("fg={{colors.accent}} raw={{colors.accent|hex}}", fixture),
    "fg=#3bff9e raw=3bff9e"
  )
})

test("brand projections use the configured identity and tokenized mark colors", async () => {
  const { renderAssetSource, renderBrandQml } = await generatorPromise
  const brand = {
    identity: {
      name: "Example",
      short_name: "EXAMPLE",
      tagline: "A different signal.",
      palette_name: "ink / lime",
      lock_subtitle: "PRIVATE SESSION",
      ceremony_title: "EXAMPLE THEME CHANGE",
      ceremony_detail: "CEREMONY: example mark"
    },
    assets: { mark: "branding/marks/aranea-primary.svg" }
  }
  const mark = renderAssetSource(brand.assets.mark, fixture)
  assert.match(mark, /#a1b2c3/)
  assert.match(mark, /#d4e5f6/)
  assert.match(mark, /#0a1b2c/)
  assert.doesNotMatch(mark, /#8af79c|#2cf2b8|#00e5ff/i)
  assert.match(renderBrandQml(brand), /shortName: "EXAMPLE"/)
  assert.match(renderBrandQml(brand), /lockSubtitle: "PRIVATE SESSION"/)
})
