# Development

Start with [Contributing](../CONTRIBUTING.md) for tool installation, Git hooks,
commit conventions, and pull requests. This guide covers source ownership,
local verification, and visual captures. [Architecture](architecture.md) explains
how the runtime pieces fit together.

## Repository map

| Path                        | Responsibility                                                         |
| --------------------------- | ---------------------------------------------------------------------- |
| `design/`                   | Canonical tokens and templates for generated projections               |
| `backgrounds/`, `branding/` | Wallpaper catalog, spider marks, motifs, and artwork                   |
| `integrations/`             | GTK, cursor, icons, terminal, browser, Qt, and application styling     |
| `plugins/`                  | Quickshell plugins, shared components, and pure logic modules          |
| `hooks/`, `scripts/`        | Installation, activation, state backends, and desktop helpers          |
| `tools/`                    | Quality gates, generators, preview renderers, and upstream reports     |
| `tests/`                    | Sandboxed shell contracts, JavaScript tests, and QML behavior fixtures |
| `screenshots/`              | Committed showcase PNGs and hero GIF                                   |

## Local checks

Use the smallest relevant check while editing, then run the full gate before
handoff:

```bash
tests/run json-events install uninstall doctor installer
node --test tests/js/graph-logic.test.js
tests/qml-behaviour.test.sh shared
tools/check
```

`tests/run` accepts bare test names. `tools/check` runs format, lint, inline
documentation, asset/link validation, QML analysis, QML behavior, contract tests,
and runtime smoke checks. `--only format,lint,validate` selects stages;
`--fast` skips smoke and slow shell tests. QML/runtime coverage depends on the
host's Quickshell, Omarchy shell, and headless compositor tools. A skipped check
is a limitation to report, not a passed check.

### Design tokens

Edit `design/tokens.toml` for palette, shell surfaces, spacing, typography, and
motion. Target formats and asset geometry live in `design/templates/`.
Aranea's identity and canonical spider mark are fixed in the generator; there
is no separate branding configuration.

```bash
scripts/generate-tokens --write
scripts/generate-tokens --check
```

The generator produces committed runtime inputs, including QML values, platform
styles, mark variants, boot artwork, motifs, and cursors. Review these diffs but
edit their source, not the projections. Raster regeneration requires
`rsvg-convert`. Xcursor and Hyprcursor share cursor geometry. Font-derived icons
are owned by `scripts/generate-font-icon-theme`, with their accent resolved by
the token generator.

### Shared QML components

`plugins/araneadev.shared` owns repeated presentation and input contracts.
Examples include `SurfaceCard`, `BrandHeader`, `StatusRow`, `EmptyState`,
`Typography`, and the focus/motion primitives. `KeyboardInputFrame` forwards
keys; `KeyboardPanelFrame` adds the layer-shell panel. `InkText` aligns glyph
ink instead of text advance width.

Give reusable components explicit properties and action signals, token-backed
defaults, and a `qmldir` registration. Keep plugin lifecycle, IPC, cursor
identity, and process management in the owning plugin.

### JavaScript facades

Generated compatibility facades preserve the function names QML imports. Change
the focused source module beside a facade, add direct module tests, and regenerate:

```bash
node tools/js-facade-generator.mjs --write
node tools/js-facade-generator.mjs --check
```

Keep generated JavaScript compatible with QML. Do not add Node `require`, ES
module imports, or nested QML `.import` statements to the generated output.

### Extraction boundaries

Use `RuntimePaths.qml` for shared state roots and branding URLs. Preserve the
lock screen's intentional fixed Omarchy paths. Extract one responsibility at a
time: search belongs in `MenuSearch.js`, tree traversal in `MenuTree.js`, and
notification preferences in `NotificationSettings.js`.

Shared components render supplied state. Composition roots retain filtering,
persistence, launch queues, and service ownership. For example, `EmojiCell` and
`EmojiGrid` render and emit selection, while `Emojis.qml` owns recents and insertion.

## Showcase captures

The public batch produces 38 surface PNGs and a 32-frame hero GIF. It mixes live
shell captures with production QML rendered in isolated hosts; lock and boot
previews never lock or reboot the active machine.

First switch to an intentionally empty workspace 2, then run:

```bash
scripts/capture-screenshots --all --output screenshots
```

The script refuses a batch started on another workspace, pins workspace 2, and
rechecks it before screen grabs. It parks and restores the real notification
inbox, restarts the shell, and returns to workspace 1. Notifications arriving
while the inbox is parked are discarded on successful restoration.

Captures preserve the real selected Usage provider. The Agents fixture displays
Codex without saving that preference. To intentionally change the real bar ring
before capturing, use `omarchy-shell omarchy.agents select codex`; that choice
persists across restarts.

Network hosts VPN and Bluetooth captures; System hosts Display and Health.
Health waits for live CPU history. Settings previews use Signal Shrine, and
`settings-schedule` shows the daily time/image editor. Nearby device names,
audio labels, provider details, and notification contents are staged for the
showcase. Audio transport and agent refresh/selection are refused while their
showcase fixtures are active. Wi-Fi QR codes are excluded.

A failed surface restores its previous PNG, fails the batch, and prevents a new
GIF. Rebuild only the GIF from existing stills with:

```bash
scripts/capture-screenshots --hero --output screenshots
```

Eight additional menu search fixtures are rendered separately:

```bash
for state in mixed no-match no-compositor vanished actions action-pending action-error action-long-label; do
  scripts/capture-screenshots --surface "menu-search-$state" --output /tmp/aranea-previews
done
```

`tools/render-lock-preview` renders the real `LockView` offscreen with a fixture
clock and empty password field. `tools/render-plymouth-preview` composes the
installed unlock artwork against Omarchy's boot geometry and refuses upstream
geometry drift. Polkit captures use a cancellable `/usr/bin/true` authentication
request without entering a password.

Capture overrides include `ARANEA_CAPTURE_WIFI_NAMES` and
`ARANEA_CAPTURE_BT_NAMES` (JSON arrays), `ARANEA_CAPTURE_AUDIO_SHOWCASE`
(`{outputs,inputs,apps,track}`), and `ARANEA_CAPTURE_AGENTS_SHOWCASE`
(`{agents:[...]}`). `ARANEA_NETWORK_GRAPH_DELAY` controls the live link-history
wait; `ARANEA_BLUETOOTH_SCAN_DELAY` controls the extra scan delay. See the
capture script header for other fixture inputs and defaults.

## Project acceptance and inert previews

`tests/run projects-flow` uses temporary Git repositories, explicit registration,
fake desktop evidence, and real sandbox helper processes. It checks owner/store
identity, reuse without duplicate launches, partial launches, and failed-role
retry. It does not establish native portal behavior or real compositor focus.

Render production project content without a live operation owner:

```bash
tools/render-projects-preview --output /tmp/projects.png --fixture project-details
tools/render-project-actions-preview --output /tmp/actions.png --scene editor-service --size large-font
scripts/capture-screenshots --surface workspaces --output /tmp/aranea-previews
```

Other project fixtures include `projects-empty`, `projects-discovery`,
`projects-grouped`, `projects-partial`, `project-search`, and
`project-launch-partial`. Fixtures use invented `/fixture/` paths and refuse
registry reads, owner actions, choosers, and execution. Workspace capture renders
only the production panel, before live compositor reads or focus dispatch.

Settings renderers accept `ARANEA_SETTINGS_RENDER_WIDTH`,
`ARANEA_SETTINGS_RENDER_HEIGHT`, `ARANEA_SETTINGS_RENDER_FONT_SCALE`, and
`ARANEA_SETTINGS_RENDER_SCROLL=bottom`. Use
`ARANEA_PROJECT_RENDER_STATE=pending` for pending project-launch previews.

### Projects presentation

`araneadev.projects` owns project views, registry/discovery clients, retained
drafts, and capture transactions. Its persistent operation owner stays separate
from window visibility. Shared controls live in `araneadev.shared`; Settings
uses compatibility wrappers.

For changes here, run registry, discovery, tool, CLI, and flow suites plus the
project JavaScript and QML fixtures. Coverage floors live in
`tools/baselines/coverage.txt`. Record live portal, application reuse, terminal
observation, and compositor checks separately from offscreen verification.

## Tracking upstream

`.omarchy-version` pins the Omarchy release last reviewed. Plugins declaring
`omarchy.clonedFrom` are forks, and all plugins depend on Omarchy shell modules.

```bash
tools/upstream-drift
tools/upstream-drift --diff
tools/upstream-drift --json
tools/upstream-drift --to quattro
```

The report watches forked plugin paths plus shell Commons, Ui, services, and
`shell.qml`. Port the intent into Aranea's decomposed files, run `tools/check`,
and update the pin in the same pull request. The Monday workflow maintains one
`upstream-drift` issue until the pin is current.

## Contributions

Document user-facing changes in the closest guide and update contract tests for
flags, JSON fields, and exit codes. Use conventional commits and a topic branch.
The release sequence is verified `master`, a release-please pull request, green
PR checks, then merge and version tag/GitHub release. Docs-only pushes are
excluded from the release workflow's push trigger; `workflow_dispatch` can run
it explicitly. See [Contributing](../CONTRIBUTING.md#releases) for token setup
and release-PR checks.
