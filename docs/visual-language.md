# Visual language

Aranea uses dark instrument surfaces, mint signals, and violet depth around a
quiet working center. Signal Shrine places the spider in a rain-soaked alley;
Neural Deck depicts a physical command room. The thirteen wallpapers vary their
setting and contrast while leaving room for readable desktop controls.

The launcher leads with identity, search, and Files, Terminal, and Projects.
Its commands form a compact single column of six groups. Search and submenus
use smaller headers, and short screens compress the opening composition to
preserve useful result space. Settings, Projects, and dropdowns share the same
shaded material. The bar's obsidian shelf keeps controls legible over bright
wallpapers. Status graphics represent available system evidence.

Settings, Projects, and popup reading surfaces use opaque fills. Decorative
corner traces and header gradients stay dimmer than the keyboard focus reticle.
Ordinary popups use neutral borders, preserving configured edge widths.

## Material and color

| Role                 | Default   | Use                                            |
| -------------------- | --------- | ---------------------------------------------- |
| Background           | `#08090b` | Obsidian base                                  |
| Foreground           | `#edf3f6` | Primary names, values, and decisions           |
| Secondary foreground | `#8b96a6` | Supporting text                                |
| Mint                 | `#3bff9e` | Active, ready, healthy, and keyboard selection |
| Violet               | `#7a5cff` | Identity and secondary emphasis                |

Amber and red identify attention and critical states. Neutral frames let content
lead; error and urgent surfaces retain semantic colors. Secondary captions and
hints use the shared 64% foreground opacity role.

## Proportion and rhythm

Panels follow the desktop's configured window rounding and border width,
including square corners and zero-width borders. Compact spacing separates
sections, rows, and adjacent labels without crowding content. Long device details
elide before colliding with names or trailing controls. Wallpaper choices reduce
from four columns to two or one as width narrows.

Inter is the default interface family, with JetBrains Mono for technical values.
Regular carries body text; Medium and Semibold add emphasis. Appearance offers
installed interface and monospace choices, samples, and explicit Apply. Shared
`Typography` keeps those roles separate from the dedicated Nerd Font glyph face.
Menu-specific font/payload overrides retain precedence.

Current choices use a soft mint/violet tint and inset marker. Tabs and actions
use an illuminated underline, a restrained bezel, and clearance below the label.
Keyboard targets use four corner brackets and a mint side tick. Shared focus
components draw that treatment; hosts own cursor identity and activation.

## Motion

Dropdowns, modal cards, pickers, Projects, Settings, notifications, and OSD use a
spring from 94% scale to full size. Opacity remains monotonic: 220 ms on opening
and 120 ms on closing. Hover and selection feedback takes 120 ms. The permanent
bar and lock screen do not spring.

The launcher reveals identity, then tiles, then results. Artwork moves while
hit targets remain stationary. Its spider stays fixed inside moving bezel
accents. Reading surfaces keep ambient edge sweeps off; explicitly enabled sweeps
stop when the window is hidden or motion is disabled.

`SurfaceMotion` and `SpringValue` preserve the current presentation when a
transition reverses. Reduced motion stops active transitions and ambient loops
and assigns the final state immediately. Logical close releases input before
any decorative closing frame finishes. Busy states retain a static fallback.

Spring strength, damping, and scale come from `design/tokens.toml`. Desktop
windows use the matching `araneaSpring` Hyprland curve for opening/movement and
a quick monotonic close. `scripts/aranea-motion` supports legacy keywords and
Lua configuration. Shell cards animate themselves, avoiding a second compositor
scale transition on transparent layers.

## Identity system

Aranea's identity and canonical spider are fixed in the token generator.
Primary, reduced, and ceremony marks share their visual grammar with status
glyphs, menu motifs, and network lines. Keep their geometry consistent across
lock, idle, boot, and cursor surfaces.

Edit `design/tokens.toml` or a template, then run
`scripts/generate-tokens --write` and `--check`. Committed platform styles, QML
tokens, cursor files, and generated artwork are projections. Xcursor and
Hyprcursor share geometry; wallpaper IDs live in `backgrounds/manifest.toml`.
See [Development](development.md#design-tokens) for the editing workflow.

## Information panel hierarchy

Health and Agents lead with identity and decision state, then compact context
and optional details. Summary values use bold subtitle text. Shared spacing is
16 units between sections, eight between rows, and four between adjacent labels.
Neutral hairlines divide content; the fixed keyboard hint remains reachable.

Health shows issue rows before Resource details. CPU history has a full trace;
memory and disk sit side by side. Processes starts collapsed, and issues open
guided diagnostics. Missing evidence uses an unavailable summary and a missing
value marker.

Agents shows authentication errors, limit windows, and prepaid balance before
collapsed Usage history and Models. Sections reset on close and provider change.
Headings support pointer and keyboard activation and scroll into the available
height. Long primary content gets a bounded viewport. Expansion and keyed
navigation remain host responsibilities; reduced motion presents the same state.
