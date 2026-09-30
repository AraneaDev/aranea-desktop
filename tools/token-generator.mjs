import fs from "node:fs"
import { createHash } from "node:crypto"
import os from "node:os"
import path from "node:path"
import { execFileSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { parse } from "smol-toml"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const sourcePath = path.join(root, "design/tokens.toml")
const brandSourcePath = path.join(root, "design/brand.toml")
const rasterizer = process.env.ARANEA_RSVG_CONVERT || "rsvg-convert"
const pngSignature = Buffer.from("89504e470d0a1a0a", "hex")

function canonicalPng(png) {
  if (!png.subarray(0, pngSignature.length).equals(pngSignature))
    throw new Error("cannot canonicalize a non-PNG image")
  const chunks = [pngSignature]
  let offset = pngSignature.length
  while (offset < png.length) {
    if (offset + 12 > png.length) throw new Error("truncated PNG chunk")
    const length = png.readUInt32BE(offset)
    const end = offset + 12 + length
    if (end > png.length) throw new Error("truncated PNG data")
    const type = png.subarray(offset + 4, offset + 8)
    // Keep critical chunks (whose first type byte is uppercase) and drop
    // rasterizer-specific ancillary metadata such as bKGD and tIME.
    if ((type[0] & 0x20) === 0) chunks.push(png.subarray(offset, end))
    offset = end
  }
  return Buffer.concat(chunks)
}

function pngsMatch(first, second) {
  try {
    const firstSize = first.subarray(16, 24)
    const secondSize = second.subarray(16, 24)
    return firstSize.length === 8 && firstSize.equals(secondSize)
  } catch {
    return false
  }
}

function flattenTokens(value, prefix = "", output = {}) {
  for (const [key, child] of Object.entries(value)) {
    const name = prefix ? `${prefix}.${key}` : key
    if (child && typeof child === "object" && !Array.isArray(child))
      flattenTokens(child, name, output)
    else output[name] = child
  }
  return output
}

function validateTokens(tokens) {
  const required = ["mode", "colors", "dimensions", "motion", "shell"]
  for (const name of required) {
    if (!(name in tokens)) throw new Error(`tokens missing required section: ${name}`)
  }
  if (tokens.mode !== "dark") throw new Error(`unsupported token mode: ${tokens.mode}`)
  for (const name of ["accent", "background", "foreground", "red"])
    if (typeof tokens.colors[name] !== "string") throw new Error(`colors.${name} must be a string`)
  return tokens
}

function validateBrand(brand) {
  if (!brand || typeof brand !== "object") throw new Error("brand config must be a table")
  for (const name of ["identity", "assets"])
    if (!(name in brand)) throw new Error(`brand missing required section: ${name}`)
  for (const name of [
    "name",
    "short_name",
    "tagline",
    "palette_name",
    "lock_subtitle",
    "ceremony_title",
    "ceremony_detail"
  ]) {
    if (typeof brand.identity[name] !== "string" || brand.identity[name].length === 0)
      throw new Error(`brand.identity.${name} must be a non-empty string`)
  }
  if (typeof brand.assets.mark !== "string" || brand.assets.mark.length === 0)
    throw new Error("brand.assets.mark must be a non-empty string")
  if (!fs.existsSync(path.join(root, brand.assets.mark)))
    throw new Error(`brand asset does not exist: ${brand.assets.mark}`)
  return brand
}

function quote(value) {
  if (typeof value === "string") return JSON.stringify(value)
  if (typeof value === "boolean") return value ? "true" : "false"
  return String(value)
}

function keyName(key) {
  return key.replaceAll(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase()
}

function renderFlatSection(section) {
  return Object.entries(section)
    .map(([key, value]) => `${keyName(key)} = ${quote(value)}`)
    .join("\n")
}

function renderColorsToml(tokens) {
  const lines = [`mode = ${quote(tokens.mode)}`, renderFlatSection(tokens.colors)]
  lines.push(renderFlatSection(tokens.dimensions))
  lines.push(`motion_enabled = ${quote(tokens.motion.enabled)}`)
  lines.push(`reduced_motion_fallback = ${quote(tokens.motion.reduced_motion_fallback)}`)
  return `${lines.filter(Boolean).join("\n\n")}\n`
}

function renderTable(name, value, lines) {
  lines.push(`[${name}]`)
  for (const [key, child] of Object.entries(value)) {
    if (!(child && typeof child === "object" && !Array.isArray(child)))
      lines.push(`${key} = ${quote(child)}`)
  }
  lines.push("")
  for (const [key, child] of Object.entries(value)) {
    if (child && typeof child === "object" && !Array.isArray(child))
      renderTable(`${name}.${key}`, child, lines)
  }
}

function renderShellToml(tokens) {
  const lines = []
  for (const [name, section] of Object.entries(tokens.shell)) renderTable(name, section, lines)
  return `${lines.join("\n").trimEnd()}\n`
}

function renderQmlTokens() {
  return `// Canonical semantic design tokens exposed to shared QML components.
// qmllint disable missing-property
pragma Singleton
import QtQuick
import qs.Commons

QtObject {
  // Primary accent colour.
  readonly property color accent: Color.accent
  // Secondary accent used by selected menu text.
  readonly property color accentSecondary: Color.menu.selectedText
  // Base background colour.
  readonly property color background: Color.background
  // Default foreground colour.
  readonly property color foreground: Color.foreground
  // Urgent and attention colour.
  readonly property color urgent: Color.urgent
  // Semantic colors used by branding glyphs and lock overlays.
  readonly property color ceremony: Color.notifications.countdown
  // Attention color used by health status surfaces.
  readonly property color attention: Color.notifications.countdown
  // Base color used by the lock scrim.
  readonly property color lockOverlay: Color.lock.background
  // Shared surface border colour.
  readonly property color surfaceBorder: Color.tooltip.border
  // Shared panel corner radius.
  readonly property int cornerRadius: Style.cornerRadius
  // Shared panel border width: the host's panel frame width (KeyboardPanel, PopupCard, OSD).
  readonly property int borderWidth: Math.max(1, Style.space(2))
  // Shared panel padding.
  readonly property int panelPadding: Style.spacing.panelPadding
  // Shared row horizontal padding.
  readonly property int rowPadding: Style.spacing.rowPaddingX
  // Whether motion effects are enabled.
  readonly property bool motionEnabled: MotionState.motionEnabled
}
`
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`
}

function renderBrandShellEnv(brand) {
  const i = brand.identity
  return `# Generated from design/brand.toml. Do not edit directly.\nBRAND_NAME=${shellQuote(i.name)}\nBRAND_SHORT_NAME=${shellQuote(i.short_name)}\nBRAND_TAGLINE=${shellQuote(i.tagline)}\nBRAND_PALETTE_NAME=${shellQuote(i.palette_name)}\nBRAND_LOCK_SUBTITLE=${shellQuote(i.lock_subtitle)}\nBRAND_CEREMONY_TITLE=${shellQuote(i.ceremony_title)}\nBRAND_CEREMONY_DETAIL=${shellQuote(i.ceremony_detail)}\n`
}

function renderBrandQml(brand) {
  const i = brand.identity
  const markFile = "brand.svg"
  const q = (value) => JSON.stringify(value)
  return `// Generated from design/brand.toml. Do not edit directly.
pragma Singleton
import QtQuick

QtObject {
  // Full visible product name.
  readonly property string name: ${q(i.name)}
  // Compact visible product name used in shell surfaces.
  readonly property string shortName: ${q(i.short_name)}
  // Visible product tagline.
  readonly property string tagline: ${q(i.tagline)}
  // Human-readable palette label.
  readonly property string paletteName: ${q(i.palette_name)}
  // Subtitle shown on the lock screen.
  readonly property string lockSubtitle: ${q(i.lock_subtitle)}
  // Title used by the theme-change ceremony.
  readonly property string ceremonyTitle: ${q(i.ceremony_title)}
  // Detail line used by the theme-change ceremony.
  readonly property string ceremonyDetail: ${q(i.ceremony_detail)}
  // Generated runtime mark filename.
  readonly property string markFile: ${q(markFile)}
}
`
}

function renderBrandText(brand) {
  const i = brand.identity
  return new Map([
    [
      "branding/about.txt",
      `${i.short_name} IDENTITY\nSource mark: ${brand.assets.mark}\nTagline: ${i.tagline}\n`
    ],
    [
      "branding/about-card.txt",
      `${i.short_name}\n=======\n\nTheme: ${i.name}\nPalette: ${i.palette_name}\nSource mark: ${brand.assets.mark}\nTagline: ${i.tagline}\n`
    ],
    ["branding/screensaver.txt", `${i.short_name}\n${i.tagline}\n`],
    ["branding/glyphs/theme-change.txt", `${i.ceremony_title}\n${i.ceremony_detail}\n`],
    ["branding/brand.env", renderBrandShellEnv(brand)]
  ])
}

function htmlEscape(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}

function renderBrowserIndex(brand) {
  const i = brand.identity
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${htmlEscape(i.name)}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main>
    <img class="mark" src="../../../branding/brand.svg" alt="">
    <h1>${htmlEscape(i.name)}</h1>
    <p>${htmlEscape(i.tagline)}</p>
  </main>
</body>
</html>
`
}

function xmlEscape(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}

function renderBrandRaster(brand, tokens, markSvg, width, height, filename) {
  const markData = Buffer.from(markSvg).toString("base64")
  const i = brand.identity
  const c = tokens.colors
  const markWidth = Math.round(width * 0.18)
  const markHeight = Math.round(height * 0.42)
  const markX = Math.round((width - markWidth) / 2)
  const markY = Math.round(height * 0.18)
  const textY = Math.round(height * 0.72)
  const subtitleY = Math.round(height * 0.78)
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <defs><radialGradient id="bg"><stop stop-color="${c.surface_raised}"/><stop offset="1" stop-color="${c.darker_background}"/></radialGradient></defs>
  <rect width="${width}" height="${height}" fill="url(#bg)"/>
  <image href="data:image/svg+xml;base64,${markData}" x="${markX}" y="${markY}" width="${markWidth}" height="${markHeight}" preserveAspectRatio="xMidYMid meet"/>
  <text x="${width / 2}" y="${textY}" fill="${c.foreground}" text-anchor="middle" font-family="sans-serif" font-size="${Math.max(24, Math.round(height * 0.035))}" letter-spacing="${Math.max(2, Math.round(height * 0.008))}">${xmlEscape(i.short_name)}</text>
  <text x="${width / 2}" y="${subtitleY}" fill="${c.dark_foreground}" text-anchor="middle" font-family="sans-serif" font-size="${Math.max(14, Math.round(height * 0.018))}">${xmlEscape(i.tagline)}</text>
</svg>
`
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "aranea-brand-"))
  const input = path.join(temporaryRoot, "brand.svg")
  const output = path.join(temporaryRoot, filename)
  try {
    fs.writeFileSync(input, svg)
    execFileSync(rasterizer, ["-w", String(width), "-h", String(height), "-o", output, input], {
      stdio: "ignore"
    })
    return canonicalPng(fs.readFileSync(output))
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true })
  }
}

function renderBrandAssets(brand, tokens) {
  const markSvg = renderAssetSource(brand.assets.mark, tokens)
  const fingerprint = createHash("sha256")
    .update(JSON.stringify({ brand, tokens, markSvg }))
    .digest("hex")
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "aranea-brand-"))
  const output = path.join(temporaryRoot, "unlock.png")
  const markOutput = path.join(temporaryRoot, "brand.svg")
  try {
    fs.writeFileSync(markOutput, markSvg)
    execFileSync(rasterizer, ["-w", "320", "-h", "320", "-o", output, markOutput], {
      stdio: "ignore"
    })
    return new Map([
      [
        "branding/raster-manifest.txt",
        `# Generated from design/brand.toml and design/tokens.toml. Do not edit directly.\ninput_sha256=${fingerprint}\nunlock=320x320\nlock=3840x2160\nplymouth=1920x1080\n`
      ],
      ["branding/brand.svg", markSvg],
      ["unlock.png", canonicalPng(fs.readFileSync(output))],
      [
        "branding/screens/lock.png",
        renderBrandRaster(brand, tokens, markSvg, 3840, 2160, "lock.png")
      ],
      [
        "branding/screens/plymouth.png",
        renderBrandRaster(brand, tokens, markSvg, 1920, 1080, "plymouth.png")
      ]
    ])
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true })
  }
}

function renderIntegrationCss(tokens) {
  const c = tokens.colors
  return `/* Generated from design/tokens.toml. Do not edit directly. */
:root {
  --aranea-background: ${c.background};
  --aranea-surface: ${c.lighter_background};
  --aranea-surface-raised: ${c.surface_raised};
  --aranea-surface-glass: ${c.surface_glass};
  --aranea-foreground: ${c.foreground};
  --aranea-muted: ${c.dark_foreground};
  --aranea-accent: ${c.accent};
  --aranea-focus: ${c.accent_secondary};
  --aranea-error: ${c.red};
  --aranea-ceremony: ${c.ceremony};
  --aranea-attention: ${c.yellow};
}
`
}

function tokenValue(tokens, expression) {
  const [pathName, format] = expression.split("|")
  const value = pathName.split(".").reduce((current, key) => current?.[key], tokens)
  if (value === undefined) throw new Error(`unknown token in template: ${expression}`)
  if (format === "hex") return String(value).replace(/^#/, "")
  return String(value)
}

function renderTemplate(template, tokens) {
  const rendered = template.replaceAll(/\{\{([^}]+)\}\}/g, (_, expression) =>
    tokenValue(tokens, expression.trim())
  )
  if (rendered.includes("{{")) throw new Error("template contains unresolved token placeholders")
  return rendered
}

function renderPlatformTemplates(tokens) {
  const files = [
    "cava-theme",
    "gtk.css",
    "integrations/terminal/alacritty.toml",
    "integrations/terminal/foot.ini",
    "integrations/terminal/kitty.conf",
    "integrations/developer/btop.theme",
    "integrations/developer/lazygit.yml",
    "integrations/developer/starship.toml",
    "integrations/developer/tmux.conf",
    "integrations/qt/kvantum/Aranea/Aranea.kvconfig"
  ]
  return new Map(
    files.map((relative) => {
      const template = fs.readFileSync(
        path.join(root, "design/templates", `${relative}.in`),
        "utf8"
      )
      return [relative, renderTemplate(template, tokens)]
    })
  )
}

function renderCursorAssets(tokens) {
  const families = {
    left_ptr: [
      "integrations/cursor/cursors/left_ptr.svg",
      "integrations/cursor/hyprcursor/hyprcursors/left_ptr/left_ptr.svg"
    ],
    hand2: [
      "integrations/cursor/cursors/hand2.svg",
      "integrations/cursor/hyprcursor/hyprcursors/hand2/hand2.svg"
    ],
    crosshair: [
      "integrations/cursor/cursors/crosshair.svg",
      "integrations/cursor/hyprcursor/hyprcursors/crosshair/crosshair.svg"
    ],
    watch: [
      "integrations/cursor/cursors/watch.svg",
      "integrations/cursor/hyprcursor/hyprcursors/watch/watch.svg"
    ]
  }
  const outputs = new Map()
  for (const [family, destinations] of Object.entries(families)) {
    const template = fs.readFileSync(
      path.join(root, "design/templates/assets", `cursor-${family}.svg.in`),
      "utf8"
    )
    const rendered = renderTemplate(template, tokens)
    for (const destination of destinations) outputs.set(destination, rendered)
    if (family === "watch") {
      for (const frame of Array.from({ length: 8 }, (_, index) =>
        String(index + 1).padStart(2, "0")
      )) {
        outputs.set(`integrations/cursor/cursors/watch-${frame}.svg`, rendered)
        outputs.set(`integrations/cursor/hyprcursor/hyprcursors/watch/watch-${frame}.svg`, rendered)
      }
    }
  }
  return outputs
}

function renderPaletteProjection(relative, tokens) {
  const current = fs.readFileSync(path.join(root, relative), "utf8")
  const palette = {
    "#3bff9e": tokens.colors.accent,
    "#7a5cff": tokens.colors.accent_secondary,
    "#08090b": tokens.colors.background,
    "#15121f": tokens.colors.cursor_shadow,
    "#151c24": tokens.colors.surface_raised,
    "#10151b": tokens.colors.lighter_background,
    "#edf3f6": tokens.colors.foreground,
    "#8b96a6": tokens.colors.dark_foreground,
    "#ff5f56": tokens.colors.red,
    "#ffbd2e": tokens.colors.yellow,
    "#7dffc0": tokens.colors.bright_green,
    "#10f0d0": tokens.colors.cyan
  }
  return current.replaceAll(/#[0-9a-fA-F]{6}/g, (value) => palette[value.toLowerCase()] || value)
}

function renderAssetSource(relative, tokens) {
  const current = fs.readFileSync(path.join(root, relative), "utf8")
  return current.includes("{{")
    ? renderTemplate(current, tokens)
    : renderPaletteProjection(relative, tokens)
}

function renderSvgAssets(tokens) {
  const directories = ["integrations/icons/aranea", "integrations/qt/kvantum/Aranea"]
  const outputs = new Map()
  for (const directory of directories) {
    const absolute = path.join(root, directory)
    if (!fs.existsSync(absolute)) continue
    const entries = fs.readdirSync(absolute, { recursive: true, withFileTypes: true })
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith(".svg")) continue
      const relative = path.relative(root, path.join(entry.parentPath, entry.name))
      outputs.set(relative, renderAssetSource(relative, tokens))
    }
  }
  return outputs
}

function renderBrandSvgAssets(tokens) {
  const outputs = new Map()
  const templateRoot = path.join(root, "design/templates/assets/branding")
  for (const entry of fs.readdirSync(templateRoot)) {
    if (!entry.endsWith(".svg.in")) continue
    const name = entry.slice(0, -7)
    const family = ["active", "ready", "power", "sleep", "warning", "attention", "error"].includes(
      name
    )
      ? "glyphs"
      : "motifs"
    outputs.set(
      `branding/${family}/${name}.svg`,
      renderTemplate(fs.readFileSync(path.join(templateRoot, entry), "utf8"), tokens)
    )
  }
  return outputs
}

function renderKvantumBrand(tokens, brand) {
  const markSvg = renderAssetSource(brand.assets.mark, tokens)
  const markData = Buffer.from(markSvg).toString("base64")
  const c = tokens.colors
  return `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256" fill="none">
  <rect width="256" height="256" fill="${c.background}"/>
  <g opacity=".28" stroke="${c.accent_secondary}" stroke-width="1">
    <path d="M0 32 64 96 128 32 192 96 256 32M0 224 64 160 128 224 192 160 256 224"/>
    <path d="M32 0 96 64 32 128 96 192 32 256M224 0 160 64 224 128 160 192 224 256"/>
  </g>
  <image href="data:image/svg+xml;base64,${markData}" x="38" y="24" width="180" height="208" preserveAspectRatio="xMidYMid meet"/>
</svg>
`
}

function loadTokens() {
  return validateTokens(parse(fs.readFileSync(sourcePath, "utf8")))
}

function loadBrand() {
  return validateBrand(parse(fs.readFileSync(brandSourcePath, "utf8")))
}

function outputs(tokens, brand) {
  return new Map([
    ["colors.toml", renderColorsToml(tokens)],
    ["shell.toml", renderShellToml(tokens)],
    ["plugins/araneadev.shared/DesignTokens.qml", renderQmlTokens()],
    ["plugins/araneadev.shared/BrandConfig.qml", renderBrandQml(brand)],
    ["integrations/aranea-colors.css", renderIntegrationCss(tokens)],
    ["integrations/browser/chromium/new-tab/index.html", renderBrowserIndex(brand)],
    ...renderBrandText(brand),
    ...renderPlatformTemplates(tokens),
    ...renderCursorAssets(tokens),
    ...renderSvgAssets(tokens),
    ...renderBrandSvgAssets(tokens),
    ["integrations/qt/kvantum/Aranea/Aranea.svg", renderKvantumBrand(tokens, brand)],
    ...renderBrandAssets(brand, tokens)
  ])
}

function checkOrWrite(write) {
  const expected = outputs(loadTokens(), loadBrand())
  let stale = false
  for (const [relative, content] of expected) {
    const target = path.join(root, relative)
    const current = fs.existsSync(target) ? fs.readFileSync(target) : Buffer.alloc(0)
    const matches = Buffer.isBuffer(content)
      ? current.equals(content) || (relative.endsWith(".png") && pngsMatch(current, content))
      : current.toString("utf8") === content
    if (!matches) {
      stale = true
      if (write) {
        fs.mkdirSync(path.dirname(target), { recursive: true })
        fs.writeFileSync(target, content)
      } else console.error(`generated token output is stale: ${relative}`)
    }
  }
  if (stale && !write) process.exitCode = 1
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes("--write")) checkOrWrite(true)
  else if (process.argv.includes("--check")) checkOrWrite(false)
  else {
    console.error("Usage: node tools/token-generator.mjs --write|--check")
    process.exitCode = 2
  }
}

export {
  flattenTokens,
  renderColorsToml,
  renderIntegrationCss,
  renderPlatformTemplates,
  renderCursorAssets,
  renderPaletteProjection,
  renderAssetSource,
  renderSvgAssets,
  renderBrandSvgAssets,
  renderBrandShellEnv,
  renderKvantumBrand,
  renderTemplate,
  renderQmlTokens,
  renderBrandQml,
  renderBrandText,
  renderBrandAssets,
  canonicalPng,
  validateBrand,
  renderShellToml,
  validateTokens
}
