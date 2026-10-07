# Whole-desktop visual refinement

Date: 2026-10-07

Status: Chat design approved; written specification awaiting review.

## Purpose and sequence

Refine the existing quiet Aranea visual language across the whole desktop.
This follows the search and quick-actions stage, whose search treatments serve
as the first reference implementation. Keep the existing palette, font choices,
wallpapers, branding, and filament identity.

Deliver through shared primitives, followed by review of their consumers. Avoid
a global density reduction that sacrifices legibility or pointer targets.
Whole desktop includes bar, dropdowns, Settings, notifications, pickers, OSD,
lock, and authentication. Application themes and boot artwork are outside this
pass; their existing visual identity remains the reference context.

## Visual contract

| Area        | Refined treatment                                                                                                                       |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Headers     | Align title, summary, and trailing actions; use existing title/body/caption roles.                                                      |
| Spacing     | Use the existing 4/8/16 spacing rhythm for related labels, rows, and sections, with font and display scaling respected.                 |
| Icons       | Consistent visual centers, stable icon columns, and existing dedicated icon font roles; retain recognizable app and service identities. |
| Text        | Primary names and decisions lead; descriptions and hints stay quieter but readable. Technical values use the selected monospace family. |
| Surfaces    | Neutral frames and restrained fills; keep user-configured rounding, border width, zero width, and edge overrides.                       |
| Interaction | Neutral hover, mint keyboard focus, explicit selected state, and distinct disabled/busy state. Hover does not change keyboard targets.  |
| Status      | Mint for activity and readiness, violet for identity, amber/red for attention and errors. State must also have text or a glyph.         |

Improve alignment and hierarchy in shared contracts before changing individual
surfaces. Do not add decorative lines, brighter glows, or additional animations
to fill otherwise quiet space. Secondary text must remain legible against the
actual surface and wallpaper composition.

## Motion

Use 120 ms for hover and selection feedback and 160 ms for panel and disclosure
settling where animation already exists. Never delay activation or service
feedback until an animation finishes. Do not animate list reordering in a way
that moves an actionable target under the pointer.

When reduced motion is enabled, show the final visual state immediately.
Pending state remains understandable through static text or glyph treatment;
pulsing is optional feedback, never the only indication of progress. Retain
ceremonial lock and authentication identity without adding entrance delays.

## Ownership and rollout

Canonical palette, spacing, typography, and motion values belong in
`design/tokens.toml` or the relevant source templates. Regenerate projections;
do not hand-edit generated TOML, CSS, QML tokens, SVG assets, or JS facades.

Stable presentational contracts belong in `plugins/araneadev.shared`, including
surface frames, headers, status rows, typography, and hover/focus treatments.
Introduce a shared component only when at least two consumers need the same
contract. Keep external shared-component defaults compatible through explicit
opt-in properties where new behavior would otherwise break consumers.

Each plugin owns its cursor, pointer settling, expansion, service state,
timeouts, placement, and lifecycle. Visual refinement must preserve the
existing safety around rows that move, disappear, or change identity.

Roll out in this order:

1. Shared frame, header, row, text, and interaction primitives, using search,
   audio, and notifications as representative previews.
2. Bar and remaining system dropdowns, including Health, Agents, network, VPN,
   Bluetooth, power, displays, updates, tray, clock, and weather.
3. Settings, clipboard, emoji, wallpaper picker, and OSD.
4. Lock and authentication, using inert renderers rather than locking the live
   session or initiating privileged actions.

Review each group before moving on. Handle local layout exceptions explicitly
rather than adding special service behavior to shared components.

## Validation and acceptance

Create before/after renders at matching viewport, scale, fonts, and fixture
state. Include empty, populated, long-content, selected, pending, unavailable,
and error states where applicable. Check compact screens, enlarged fonts,
multiple display scales, square corners, zero borders, and reduced motion.

Verify headers, summaries, scroll areas, and keyboard hints stay reachable;
labels and values cannot overlap controls. Check secondary text readability,
pointer targets, and keyboard focus against each actual surface. Preserve
service-specific semantic colors and visible failure information.

Run focused shared and consumer QML behavior checks, token/facade drift checks,
and the full `tools/check` gate before declaring implementation complete.
Refresh relevant showcase captures and `docs/visual-language.md` only after
visual review; never use fixtures to execute live actions.

Acceptance means the listed surfaces share a coherent visual rhythm, hover and
focus are distinguishable, current personalization remains respected, and
refinement introduces no changes to service or authentication behavior.
