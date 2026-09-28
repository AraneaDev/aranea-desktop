import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { parse } from "smol-toml"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const sourcePath = path.join(root, "design/tokens.toml")

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
  if (!Number.isFinite(tokens.dimensions.corner_radius))
    throw new Error("dimensions.corner_radius must be numeric")
  return tokens
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

function renderQmlTokens(tokens) {
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
  // Shared surface border colour.
  readonly property color surfaceBorder: Color.tooltip.border
  // Shared panel corner radius.
  readonly property int cornerRadius: Style.cornerRadius
  // Shared panel padding.
  readonly property int panelPadding: Style.spacing.panelPadding
  // Shared row horizontal padding.
  readonly property int rowPadding: Style.spacing.rowPaddingX
  // Whether motion effects are enabled.
  readonly property bool motionEnabled: ${tokens.motion.enabled ? "true" : "false"}
}
`
}

function renderIntegrationCss(tokens) {
  const c = tokens.colors
  return `/* Generated from design/tokens.toml. Do not edit directly. */
:root {
  --aranea-background: ${c.background};
  --aranea-surface: ${c.lighter_background};
  --aranea-surface-raised: ${c.surface_raised};
  --aranea-foreground: ${c.foreground};
  --aranea-muted: ${c.dark_foreground};
  --aranea-accent: ${c.accent};
  --aranea-focus: ${c.accent_secondary};
  --aranea-error: ${c.red};
  --aranea-ceremony: ${c.ceremony};
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

function loadTokens() {
  return validateTokens(parse(fs.readFileSync(sourcePath, "utf8")))
}

function outputs(tokens) {
  return new Map([
    ["colors.toml", renderColorsToml(tokens)],
    ["shell.toml", renderShellToml(tokens)],
    ["plugins/araneadev.shared/DesignTokens.qml", renderQmlTokens(tokens)],
    ["integrations/aranea-colors.css", renderIntegrationCss(tokens)],
    ...renderPlatformTemplates(tokens),
    ...renderCursorAssets(tokens),
    ...renderSvgAssets(tokens)
  ])
}

function checkOrWrite(write) {
  const expected = outputs(loadTokens())
  let stale = false
  for (const [relative, content] of expected) {
    const target = path.join(root, relative)
    const current = fs.existsSync(target) ? fs.readFileSync(target, "utf8") : ""
    if (current !== content) {
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
  renderTemplate,
  renderQmlTokens,
  renderShellToml,
  validateTokens
}
