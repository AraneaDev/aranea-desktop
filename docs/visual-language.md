# Visual language

Aranea combines cinematic atmosphere with operational clarity. It should feel
like a quiet obsidian control surface: luminous filaments and sparse nodes,
with enough neutral space for information to remain legible.

## Material and color

- Obsidian background: `#08090b`
- Mint signal accent: `#3bff9e`
- Violet secondary accent: `#7a5cff`
- Foreground: `#e7ecf3`
- Muted foreground: `#8b96a6`

Mint communicates active, ready, or healthy. Violet marks identity and
secondary emphasis. Amber and red are reserved for attention and critical
state rather than decoration.

## Proportion and rhythm

Controls use a compact spacing rhythm and panels that stay subordinate to
content. Panel corner radius and border width follow the desktop's own
window rounding and border width rather than a fixed Aranea value, so a
square-cornered Hyprland config gets square Aranea panels. Typography
separates proportional UI labels from monospace telemetry and technical
values. The center of a wallpaper stays quiet so bars, menus, and lock
surfaces remain readable.

Settings uses the desktop `sans-serif` alias for headings, labels and actions.
Monitor observations, scale presets and editable scales and times retain the
desktop monospace family. Its compact controls use neutral hover and press
feedback, with mint reserved for selection and keyboard focus. Wallpaper
choices adapt from four columns to two or one as the content width narrows.

Shared `Typography` keeps UI labels, technical values and icon glyphs on
separate roles across the launcher, bar tooltips, device/control panels,
notifications, Health, Agents, updates, pickers, calendar, weather, Settings,
OSD, authentication and lock. Appearance can select installed interface and
monospace families with samples and explicit Apply. Icon glyphs remain on
the dedicated font, including mixed icon/label actions. Explicit menu font
and payload overrides retain precedence.

Refined frames use neutral borders while preserving configured widths,
including zero and individual edge overrides. Urgent/error surfaces retain
semantic colors; the launcher and lock keep their restrained ceremonial marks.
The launcher adapts its row viewport to available logical screen height rather
than forcing early scrolling at a fixed 250-pixel ceiling. Shared controls
retain legacy opt-in defaults for external consumers.

## Motion

Feedback should feel immediate, panels should settle gently, and ceremonial
transitions should have room to breathe. Reduced motion is a first-class
behavior, not an afterthought. A static state must remain understandable when
animations are disabled.

## Identity system

The spider mark has primary, reduced, and ceremony variants. Shared ready,
active, and attention glyphs use the same visual grammar as menu motifs and
network lines. Keep the mark optically consistent across branding, cursor,
lock, idle, and boot surfaces.

The canonical design tokens live in `design/tokens.toml`. The checked-in
`colors.toml`, `shell.toml`, and shared QML token projection are generated
outputs; update the source and run `scripts/generate-tokens --write` instead
of editing those projections directly. GTK, terminal, developer-tool, Cava,
cursor, icon, and Qt palette outputs follow the same generation path. Cursor
families intentionally share one geometry source so Xcursor and Hyprcursor
variants stay visually identical. Stable wallpaper IDs live in
`backgrounds/manifest.toml`.

## Information panel hierarchy

Health and Agents use shared font roles and neutral panel frames.
Identity leads, followed by the decision state, compact context and optional details.
Summary values use the subtitle token with bold weight. Sections use `Style.space(16)`,
rows use `Style.space(8)`, and adjacent labels use `Style.space(4)`. Neutral hairlines
separate content; mint outlines identify keyboard targets. Pilot keyboard hints use the
existing muted-caption foreground treatment (55% foreground alpha).

Health keeps its severity text and actionable problems visible before Resource details
and Processes. Unavailable data displays an em dash and an explicit unavailable summary.
Agents keeps authentication errors, all limit windows and prepaid balance above Usage
history and Models. These technical details begin collapsed and reset on close; Agents
also resets them when providers change. Hosts own expansion and keyed navigation.
Headings show expansion, accept pointer and keyboard activation, and scroll into view
within the available panel height. Long primary Agents content gets a capped fallback
viewport. The fixed hint stays reachable. Layout changes preserve pointer settling and
reduced motion conveys the same state without animation.
