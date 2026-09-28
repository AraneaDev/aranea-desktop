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

Controls use a compact spacing rhythm, restrained borders, and rounded panels
that stay subordinate to content. Typography separates proportional UI labels
from monospace telemetry and technical values. The center of a wallpaper stays
quiet so bars, menus, and lock surfaces remain readable.

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

The source tokens live in `colors.toml` and `shell.toml`; stable wallpaper IDs
live in `backgrounds/manifest.toml`.
