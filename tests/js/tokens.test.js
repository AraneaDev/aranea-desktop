const assert = require("node:assert/strict")
const { test } = require("node:test")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")
const { crc32, deflateSync, inflateSync } = require("node:zlib")

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
  assert.match(output, /readonly property color accent: Commons\.Color\.accent/)
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
  assert.match(
    output,
    /readonly property color accentSecondary: Commons\.Color\.menu\.selectedText/
  )
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
  assert.match(output, /readonly property color ceremony: Commons\.Color\.notifications\.countdown/)
  assert.match(
    output,
    /readonly property color attention: Commons\.Color\.notifications\.countdown/
  )
  assert.match(output, /readonly property color lockOverlay: Commons\.Color\.lock\.background/)
})

test("identity projections always use Aranea", async () => {
  const { renderBrandShellEnv, renderBrandQml } = await generatorPromise
  const output = renderBrandShellEnv()
  assert.match(output, /^BRAND_NAME='Aranea'$/m)
  assert.match(output, /^BRAND_SHORT_NAME='ARANEA'$/m)
  assert.match(renderBrandQml(), /shortName: "ARANEA"/)
  assert.match(renderBrandQml(), /lockSubtitle: "SECURE SESSION"/)
})

test("canonicalPng removes rasterizer-specific ancillary chunks", async () => {
  const { canonicalPng } = await generatorPromise
  const fs = require("node:fs")
  const png = fs.readFileSync("unlock.png")
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

test("the canonical spider retains tokenized mark colors", async () => {
  const { renderAssetSource } = await generatorPromise
  const mark = renderAssetSource("branding/marks/aranea-primary.svg", fixture)
  assert.match(mark, /#a1b2c3/)
  assert.match(mark, /#d4e5f6/)
  assert.match(mark, /#0a1b2c/)
  assert.doesNotMatch(mark, /#8af79c|#2cf2b8|#00e5ff/i)
})

test("renderQmlTokens projects spring tuning from canonical motion tokens", async () => {
  const { renderQmlTokens } = await generatorPromise
  const output = renderQmlTokens({
    ...fixture,
    motion: {
      ...fixture.motion,
      spring_strength: 3,
      spring_damping: 0.25,
      surface_closed_scale: 0.96
    }
  })
  assert.match(output, /readonly property real springStrength: 3/)
  assert.match(output, /readonly property real springDamping: 0.25/)
  assert.match(output, /readonly property real surfaceClosedScale: 0.96/)
})

/** Run the actual generator against private copies of its source inputs. */
function generatorSandbox(t) {
  const repo = path.resolve(__dirname, "../..")
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "aranea-token-cli-"))
  t.after(() => fs.rmSync(root, { recursive: true, force: true }))
  for (const relative of [
    "tools/token-generator.mjs",
    "scripts/generate-tokens",
    "design",
    "branding/marks",
    "integrations/icons/aranea",
    "integrations/qt/kvantum/Aranea"
  ]) {
    const target = path.join(root, relative)
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.cpSync(path.join(repo, relative), target, { recursive: true })
  }
  fs.symlinkSync(fs.realpathSync(path.join(repo, "node_modules")), path.join(root, "node_modules"))
  return {
    read: (relative) => fs.readFileSync(path.join(root, relative)),
    write: (relative, content) => fs.writeFileSync(path.join(root, relative), content),
    generate: (mode) =>
      spawnSync("bash", ["scripts/generate-tokens", mode], {
        cwd: root,
        encoding: "utf8",
        env: { ...process.env, ARANEA_RSVG_CONVERT: "rsvg-convert" }
      })
  }
}

/** Change rendered pixels without changing the raster canvas dimensions. */
function changeMarkColors(sandbox) {
  sandbox.write(
    "design/tokens.toml",
    sandbox
      .read("design/tokens.toml")
      .toString("utf8")
      .replace(/^(mark_(?:start|mid|end)\s*=\s*)"[^"\n]+"/gm, '$1"#ff0000"')
  )
}

/** Re-encode the same decoded PNG pixels with a different compression policy. */
function uncompressedPng(png) {
  const chunks = []
  const imageData = []
  for (let offset = 8; offset < png.length;) {
    const end = offset + 12 + png.readUInt32BE(offset)
    const chunk = png.subarray(offset, end)
    if (chunk.toString("ascii", 4, 8) === "IDAT") imageData.push(chunk.subarray(8, -4))
    else chunks.push(chunk)
    offset = end
  }
  // Keep the decoded pixels identical, but vary the PNG encoding as rasterizer
  // versions can. An uncompressed IDAT guarantees different bytes from rsvg.
  const data = deflateSync(inflateSync(Buffer.concat(imageData)), { level: 0 })
  const idat = Buffer.alloc(data.length + 12)
  idat.writeUInt32BE(data.length)
  idat.write("IDAT", 4, "ascii")
  data.copy(idat, 8)
  idat.writeUInt32BE(crc32(idat.subarray(4, -4)), idat.length - 4)
  return Buffer.concat([png.subarray(0, 8), ...chunks.slice(0, -1), idat, chunks.at(-1)])
}

test("token CLI write refreshes same-sized raster pixels after mark token edits", (t) => {
  const sandbox = generatorSandbox(t)
  let result = sandbox.generate("--write")
  assert.equal(result.status, 0, result.stderr)
  const before = sandbox.read("unlock.png")
  const manifest = sandbox.read("branding/raster-manifest.txt")
  changeMarkColors(sandbox)

  result = sandbox.generate("--write")
  assert.equal(result.status, 0, result.stderr)
  const after = sandbox.read("unlock.png")
  assert.deepEqual(after.subarray(16, 24), before.subarray(16, 24))
  assert.equal(after.equals(before), false, "changed mark colors must replace raster pixels")
  assert.equal(sandbox.read("branding/raster-manifest.txt").equals(manifest), false)
  result = sandbox.generate("--check")
  assert.equal(result.status, 0, result.stderr)
})

test("token CLI check rejects same-sized raster when source inputs changed", (t) => {
  const sandbox = generatorSandbox(t)
  const initial = sandbox.generate("--write")
  assert.equal(initial.status, 0, initial.stderr)
  const before = sandbox.read("unlock.png")
  const manifest = sandbox.read("branding/raster-manifest.txt")
  changeMarkColors(sandbox)

  const result = sandbox.generate("--check")
  assert.equal(result.status, 1, result.stderr)
  assert.match(result.stderr, /generated token output is stale: unlock\.png/)
  assert.equal(sandbox.read("unlock.png").equals(before), true)
  assert.deepEqual(sandbox.read("branding/raster-manifest.txt"), manifest)
})

test("token CLI check tolerates same-source PNG encoding differences while write replaces them", (t) => {
  const sandbox = generatorSandbox(t)
  let result = sandbox.generate("--write")
  assert.equal(result.status, 0, result.stderr)
  const expected = sandbox.read("unlock.png")
  const alternative = uncompressedPng(expected)
  assert.equal(alternative.equals(expected), false)
  sandbox.write("unlock.png", alternative)

  result = sandbox.generate("--check")
  assert.equal(result.status, 0, result.stderr)
  assert.equal(sandbox.read("unlock.png").equals(alternative), true)
  result = sandbox.generate("--write")
  assert.equal(result.status, 0, result.stderr)
  assert.equal(sandbox.read("unlock.png").equals(expected), true)
})
