# Aranea desktop visual system

Status: design direction approved in conversation; written specification awaiting review.

## Objective

Refine design and UX across the entire Aranea desktop. Visual quality leads;
functional work supports readability, navigation and feedback for existing actions.
The scope includes every shell component and the application integrations.
Settings is one participant, rather than the focus of this project.

Keep the obsidian palette, mint interaction, violet identity, spider mark and
filament motifs. Everyday panels should feel calm and precise. The launcher,
lock and boot surfaces can carry more expressive branding.

## Approved direction and priorities

Use proportional UI typography throughout Aranea, retaining monospace for
technical values, commands, paths, resolutions and telemetry. Keep icon glyphs
on their existing dedicated font paths.

1. Establish shared typography, spacing, panel chrome and control states.
2. Refine the bar, launcher/search and everyday device controls.
3. Improve information presentation and carry the system through the remaining
   shell surfaces, secure prompts, desktop identity and application integrations.

The first installed preview contains the bar, launcher and audio/network panels.
It establishes the direction for the complete rollout. The remaining component
families stay explicitly scheduled and receive their own visual review.

## Shared visual foundation

### Typography

Introduce shared UI, technical and icon font roles in `araneadev.shared`.
UI text defaults to the system `sans-serif` alias, without bundling a new font.
Technical text uses the desktop monospace family. Preserve explicit user font
and menu payload overrides at the surfaces that already support them; an
explicit override takes precedence over the proportional default.

Use existing host font-size tokens and `Style.space` scaling. Headings use
sentence case, medium or bold weight and little tracking. Action labels have
normal tracking. Secondary descriptions remain readable against the panel
background. Reserve uppercase or spaced text for brief identity captions.

Numeric data keeps consistent alignment and adjacent units. A technical value
inside a sentence must not force the entire description into monospace.
Glyph-only controls and mixed icon/text rows retain their icon font explicitly.

### Surface and spacing

Everyday panels use a neutral border and an opaque enough obsidian surface to
read over every wallpaper. Concentrate mint on selection, focus and active
state. Use restrained violet accents for identity and selected chart motifs.
The launcher, lock and boot may retain expressive mint/violet framing.

Preserve the user's panel corner radius and border-width preferences. Use the
existing compact spacing scale, common content insets, aligned icon columns and
consistent section gaps. Group related controls; avoid nested outlined boxes
and dividers that duplicate an already clear hierarchy.

Provide distinct header, primary content, supporting context and optional
technical details. Content determines each panel's composition; a calendar,
device list and notification center should not share an identical layout.

### Controls and feedback

Keep compact visible controls with reliable pointer and keyboard targets.
Selection uses a restrained fill and marker. Hover and press use neutral
feedback; keyboard focus retains a clearly visible mint outline. Disabled
controls remain legible and do not activate. Pending state appears beside the
specific action and never implies completion before owner readback.

Use the existing settled-click, keyed-selection and first-key reveal policies.
All motion respects reduced motion and has an equally clear static state.
Show error and unavailable states in text as well as color. Preserve existing
retry and diagnostic actions and the distinction between loading, unavailable,
empty and successful states.

## Component coverage and intended outcomes

| Group                                | Components                                                                                                  | Visual and UX outcome                                                                                                                                                                                |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Desktop navigation                   | Bar, workspaces, tray and tray management                                                                   | Consistent icon size and spacing; quiet badges; clear workspace, hover and open-panel states; readable tooltips and tray actions.                                                                    |
| Command navigation                   | Launcher/menu, submenus, unified search, apps, favorites, recent, dmenu and input                           | Smaller introductory chrome, stronger search/result hierarchy, compact quick actions and consistent result labels; preserve payload and scoped-search behavior.                                      |
| Everyday devices                     | Audio, Bluetooth, network and VPN                                                                           | Current device or connection leads; primary controls stay together; device names and state are easy to scan; progress and errors belong to the affected row.                                         |
| Desktop hardware                     | Displays/monitor and power                                                                                  | Readable device summaries, aligned values, connected preset controls and secondary technical information with appropriate emphasis.                                                                  |
| System information                   | Health, Agents and updates                                                                                  | Preserve the existing summary/disclosure improvements; strengthen metric hierarchy, units, charts and actionable issues. Keep all limits, balance and authentication errors visible as required.     |
| Notifications                        | Notification center, groups, cards and empty state                                                          | Compact cards, clear title/message separation, quiet timestamps, consistent disclosure/dismiss actions and readable urgency. Preserve inbox and clear-all behavior.                                  |
| Pickers                              | Clipboard, emoji and image picker                                                                           | Balanced browsing and preview areas, consistent search fields, clear selected/pinned state, useful empty states and adaptive list/grid layouts. Preserve masking and copy/paste/insert distinctions. |
| Time and weather                     | Clock/calendar and weather                                                                                  | Calendar, current conditions and forecast lead; secondary statistics recede; selected dates, navigation and chart labels remain clear.                                                               |
| Settings                             | Appearance, Display, Schedule, Integrations and Notifications                                               | Participate in shared typography and controls while retaining the compact centered window, local drafts, custom decimal scales and scrolling.                                                        |
| Immediate feedback                   | Volume/brightness and other OSD surfaces                                                                    | Compact, readable feedback using the same typography, level bars and state colors; avoid unnecessary chrome.                                                                                         |
| Secure and ceremonial surfaces       | Authentication/polkit, lock, idle identity and Plymouth/boot                                                | Clear request and input states; coordinated spider proportions, typography and restrained ceremony; preserve security and authentication lifecycles.                                                 |
| Application and desktop integrations | GTK, Qt, file manager, terminal, browser, editor/developer tools, media/Cava, icons, cursors and wallpapers | Consistent contrast, selection palette, icon weight and motion intensity. Retain monospace where the application's content requires it and preserve intentional wallpaper variation.                 |

## Architecture and ownership

Build on the existing `SurfaceCard`, header, row, disclosure, empty-state and
Filament controls rather than introducing a parallel UI kit. New font roles
belong in the shared module. Feature hosts continue to own lifecycle, focus,
selection, scrolling and owner operations; shared components remain presentation
and input contracts.

Keep color, size and motion values in `design/tokens.toml` and their canonical
integration templates. Update `scripts/generate-tokens` and regenerate outputs
when a new token is required. Do not hand-edit generated projections.

Pilot surfaces opt into changed presentation explicitly. A global default must
not silently redesign unreviewed panels. After pilot review, migrate each family
and consolidate the shared defaults with regression coverage for every consumer.

PR #125 contains a Settings-only typography/gallery pilot. It remains a separate
draft until integration is chosen. Reuse or adapt its compatible changes during
the Settings migration; do not assume it is merged or repeat its work blindly.

## Rollout and review checkpoints

1. Shared foundation and representative preview: bar, launcher/search, audio
   and network. Include native typography, neutral everyday chrome, icon
   alignment and consistent control feedback. Install for visual inspection.
2. Complete everyday controls: Bluetooth, VPN, displays, power, tray,
   workspaces and remaining command-menu flows.
3. Complete information and pickers: notifications, Health, Agents, updates,
   clipboard, emoji, image picker, clock and weather.
4. Complete the remaining system: Settings, OSD, authentication, lock/idle,
   boot and application/asset integrations. Verify the full desktop together.

Each checkpoint has before/after captures, behavior checks and an installed
preview. Continue through every group after direction review. Publishing,
merging and releasing remain explicit delivery decisions.

## Behavior and data constraints

Preserve backend commands, IPC, routes, dmenu results, authentication protocols,
clipboard masking, notification ownership, persistent settings and owner
readback. Layout changes must not dispatch mutations or change a selected target
under a stationary pointer. Keep existing disclosure reset behavior, drafts and
scroll restoration. This design introduces no new runtime dependency or backend
feature.

## Acceptance and verification

- Every component in the coverage table has an explicit reviewed outcome.
- Proportional labels and technical monospace are visibly consistent; icon
  glyphs remain intact and explicit font overrides continue to work.
- Primary content is easy to scan without excessive branding or decoration.
- Selection, hover, press, keyboard focus, disabled and pending states remain
  distinct; unavailable information never appears as a successful observation.
- Existing keyboard actions and focus restoration pass their meaningful tests.
- Layouts adapt to the available logical viewport and scroll where needed.
  Verify native 1920x1080 at scale 1, 3840x2160 at 2.5 and 2.667, and constrained
  1920x1080 and 1280x720 displays at high scale, including long labels and errors.
- Existing behavior and geometry tests cover affected hosts and shared consumers.
  Add tests for changed behavior or uncovered regressions; avoid assertions
  that merely duplicate decorative implementation choices.
- Changed surfaces receive real full-desktop screenshots in the normal flow.
  Keep offscreen diagnostic renders separate from published screenshots.
  Capture must restore user state and exclude private desktop content.
- Run the appropriate focused checks during development and the complete
  `tools/check` gate on each stable delivery checkpoint. Independent review
  assesses the affected shared contracts before publication.

## Specification review

This document describes the approved visual direction and full component scope.
The written specification is the next review checkpoint before a concrete
implementation plan is prepared. The plan must preserve the complete coverage
and representative-first rollout above.
