# Visual language

Aranea combines a hacker cockpit atmosphere with operational clarity:
layered obsidian instruments, mint illumination, violet depth, and a quiet
working center. Signal Shrine places a sculptural spider in a rain-soaked alley;
Neural Deck is a physical hacker command room. The thirteen-scene collection
varies setting, composition, materials, lighting, and contrast.

The launcher is a command deck with a large identity heading, the canonical
spider in an instrument bezel, an explicit search console, and chamfered
Files, Terminal, and Projects controls. Short screens compress this deck to
preserve the result viewport. Search and submenus use compact headers.
Root commands use a narrow single column after folding redundant destinations
into six groups. Up/Down select a command and Enter opens it. Search, submenus,
and dmenu keep their own scoped list behavior.
Settings, Projects, and dropdowns share a shaded instrument material under
their content. The bar uses an obsidian shelf to remain readable over the
wallpaper's illuminated structures. These surfaces show actual system state;
decorative instrumentation does not invent telemetry.

## Material and color

- Obsidian background: `#08090b`
- Mint signal accent: `#3bff9e`
- Violet secondary accent: `#7a5cff`
- Foreground: `#edf3f6`
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

Inter is the default for interface headings, labels and actions, paired with
JetBrains Mono for technical text. Its clean, neutral forms keep compact
controls legible while the monospace gives telemetry a clear, stable rhythm.
Regular handles body text; Medium and Semibold provide emphasis, with Bold
reserved for existing headings. IBM Plex Sans offers a more engineered
character; Source Sans 3 is the softer, humanist alternative in the picker.
Inter's display and variable cuts and the no-ligature JetBrains Mono NL are
also available. Nerd Font glyphs keep their dedicated face.
Monitor observations, scale presets and editable scales and times retain the
selected technical family. Its compact controls use neutral hover and press
feedback. Current choices use a soft mint-to-violet tint and an inset marker;
tabs and buttons use a short illuminated underline with a quiet bezel and
roughly three pixels of extra clearance below the label.
Keyboard targets use four corner brackets and a mint side tick, with a brief
fade and settle. The shared `FocusFrame` stays decorative: hosts own focus,
cursor identity and activation. Wallpaper
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
retain legacy opt-in defaults for external consumers. Refined headers separate
related labels by four pixels. Secondary captions and hints use the shared 64%
foreground role, leaving primary names and decisions brighter. Device rows bound
and elide long details before they can crowd labels or trailing controls.

## Motion

Feedback stays immediate. Dropdowns, modal cards, pickers, Projects and Settings
use a spring scale from 94% to full size; disclosures and the tray
drawer use the same spatial spring. Notification entrances and OSD cards follow
that policy. Opacity fades without overshoot: 220 ms on opening and 120 ms on
closing. Hover and selection feedback remains 120 ms. Busy pulses retain their
established ceremonial rhythm and static fallback.

The command deck opens in sequence: identity first, tiles at 70/125/180 ms,
then results at 180 ms, with each reveal taking 320 ms. Tile artwork rises
14 pixels into place while hit targets stay stationary. Hover lights spring
into place, with a small icon lift and directional arrow response. The spider
stays fixed inside counter-rotating bezel accents. Panel edge highlights
travel over 5.2 seconds and stop when their containing window is hidden.
Reduced motion cancels pending reveals and hover transitions immediately,
shows their final state, and disables ambient loops.

Spring strength, damping and card scale come from `design/tokens.toml`.
`SurfaceMotion` and `SpringValue` preserve the current presentation when a
transition reverses. Turning motion off stops active animations and assigns the
exact final state immediately. Logical close releases input at once; retained
closing frames are decorative. The lock screen and permanent bar do not spring.

Desktop windows use the matching `araneaSpring` Hyprland overshoot curve for
opening and movement, with a quick monotonic close. The compositor curve
approximates the QML spring. `scripts/aranea-motion` supports both legacy
keywords and Lua-configured Hyprland; shell cards own their animations so
full-screen transparent layers do not receive a second scale transition.

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
separate content; corner brackets and a mint side tick identify keyboard targets. Pilot keyboard hints use the
shared secondary foreground treatment (64% foreground alpha).

Health keeps compact issue rows above expanded Resource details: a full CPU
trace and memory/disk values side by side. Processes starts collapsed. Issue rows
lead to guided diagnostics instead of merely naming a problem. Unavailable data
displays an em dash and an explicit unavailable summary.
Agents keeps authentication errors, all limit windows and prepaid balance above Usage
history and Models. The Agents detail sections begin collapsed and reset on close; Agents
also resets them when providers change. Hosts own expansion and keyed navigation.
Headings show expansion, accept pointer and keyboard activation, and scroll into view
within the available panel height. Long primary Agents content gets a capped fallback
viewport. The fixed hint stays reachable. Layout changes preserve pointer settling and
reduced motion conveys the same state without animation.
