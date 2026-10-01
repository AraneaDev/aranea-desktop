# Development

## Repository map

| Directory       | Responsibility                                                            |
| --------------- | ------------------------------------------------------------------------- |
| `backgrounds/`  | Wallpaper artwork and manifest IDs                                        |
| `branding/`     | Marks, glyphs, motifs, fastfetch, and idle artwork                        |
| `integrations/` | Cursor, icons, terminal, browser, Qt, media, session, and app styling     |
| `plugins/`      | Aranea bar, menu, lock, notifications, health, pickers, and OSD           |
| `hooks/`        | Theme activation and post-boot behavior                                   |
| `scripts/`      | Installer, doctor, wallpaper, integrations, deployment, and capture tools |
| `tests/`        | Shell contracts, QML behavior, screenshots, and JavaScript tests          |
| `screenshots/`  | README showcase captures                                                  |

## Local checks

Run the focused installer checks:

```bash
tests/run json-events install uninstall doctor installer
```

Run the repository quality gates:

```bash
tools/check
```

### Design tokens and branding

Edit `design/tokens.toml` to change the shared palette, shell surfaces,
spacing, typography, or motion defaults. Regenerate the committed projections
with `scripts/generate-tokens --write`. Edit `design/brand.toml` for visible
identity strings and replace `branding/marks/aranea-primary.svg` for the source
mark. The generator color-projects that source into the runtime
`branding/brand.svg`, lock compatibility asset, static Plymouth/lock artwork,
the motif/status glyph family, the Kvantum splash artwork, and
`branding/brand.env` for shell scripts. The source templates for those
projections live under `design/templates/assets/branding/`; edit the templates
only when changing the shape or semantic role of an asset.
Platform projections are templated in
`design/templates/`, and `scripts/generate-tokens --check` is the drift check
used by the token contract test.

The source SVG and both TOML files are the customization surface. Generated
files, including `branding/brand.svg`, `unlock.png`, and the PNG artwork under
`branding/screens/`, must not be edited directly. `rsvg-convert` is required
when regenerating the raster outputs.

The GTK stylesheet and cursor families have explicit tokenized templates under
`design/templates/gtk.css.in` and `design/templates/assets/`. The generator
renders matching Xcursor and Hyprcursor files from the same cursor family
source. Font-derived icon geometry remains owned by
`scripts/generate-font-icon-theme`; its accent placeholder is resolved by the
token generator before the committed SVG outputs are installed.

The checks cover formatting, ShellCheck, Markdown, assets, QML, QML tests,
shell contracts, JavaScript behavior, and smoke validation. Some visual or
runtime checks require the Omarchy tooling available on the development host.

### Shared QML components

Use `plugins/araneadev.shared` for visual and input contracts that are
identical across plugins: `SurfaceCard`, `PanelHeader`, `StatusRail`,
`StatusTextPair`, `StatusRow`, `BrandHeader`, `KeyboardInputFrame`,
`KeyboardPanelFrame`, `EmptyState`, and `InkText`. `KeyboardInputFrame` owns
only key forwarding; `KeyboardPanelFrame` adds the layer-shell panel.
`EmptyState` is the shared centered empty-state presentation for menu and
picker surfaces. `InkText` is a `Text` whose glyph ink, rather than its
advance width, sits on the alignment line. Keep lifecycle, cursor, and
plugin-specific interaction logic in the owning plugin rather than adding it
to shared components.

Generated asset outputs must not be edited directly. Change
`design/tokens.toml` or the relevant template, run
`scripts/generate-tokens --write`, and verify with
`scripts/generate-tokens --check`.

### JavaScript facades

Large plugin logic files are generated compatibility facades. Put new logic in
the focused source module for its domain, keep existing exported function names
stable, and regenerate with:

```bash
node tools/js-facade-generator.mjs --write
node tools/js-facade-generator.mjs --check
```

Generated files remain plain QML-compatible JavaScript: do not add `require`,
ES module imports, or QML-only nested `.import` statements. The generator check
runs as part of `tools/check` and fails when a facade is stale.

### Extraction boundaries

Shared runtime paths belong in `plugins/araneadev.shared/RuntimePaths.qml`.
Use its branding URLs and state-root properties instead of rebuilding
`XDG_STATE_HOME`, `HOME`, or the current-theme branding path in a plugin. Keep
lock-screen paths fixed to Omarchy's documented state root where that behavior
is intentional.

Large JavaScript facades should expose a stable compatibility surface while
delegating focused pure domains to sibling modules. The menu model keeps
search in `MenuSearch.js` and route/tree traversal in `MenuTree.js`; notification
settings parsing lives in `NotificationSettings.js`. New extractions must add
direct module tests and preserve the facade's exported function names.

Shared QML primitives may own visual contracts, tokens, and layout defaults,
but not plugin lifecycle, cursor state, IPC, or process management. `BrandHeader`
and `StatusRow` are intentionally presentational: callers provide text,
colors, trailing content, and click policy through properties and signals.
Keep a large QML entry point as a composition root while moving one
responsibility at a time behind tested properties and signals.

Presentational picker components follow the same boundary: `EmojiCell` owns
cell rendering and click emission, while `EmojiGrid` owns result rendering and
selection reporting; `Emojis.qml` retains filtering, recents, persistence, and
insertion. New components should expose explicit properties and signals, keep
their defaults tied to shared tokens, and receive dynamic state from the
composition root instead of reaching into root-only ids.

## Showcase captures

The README is a visual showcase as well as a project introduction. Refresh
captures with:

```bash
scripts/capture-screenshots --all --output screenshots
```

Lock and Plymouth use canonical artwork renders; the capture workflow should
not lock the active session or reboot the machine.

The Network and Bluetooth captures never show real nearby names. After
summoning the dropdown, the script hands it stand-in names through the
dropdown's `showcase` IPC method. The names are display only and are cleared
when the dropdown closes. If the dropdown doesn't answer `ok` (for example,
the stock panel is active), that surface fails and no screenshot is written.
These variables override the defaults:

| Variable                      | Default                                                      |
| ----------------------------- | ------------------------------------------------------------ |
| `ARANEA_CAPTURE_WIFI_NAMES`   | JSON array of eight made-up SSIDs (`Aranea-Home`, ...)       |
| `ARANEA_CAPTURE_BT_NAMES`     | JSON array of eight common device models (`WH-1000XM5`, ...) |
| `ARANEA_NETWORK_GRAPH_DELAY`  | `20`: seconds the link graph records before the grab         |
| `ARANEA_BLUETOOTH_SCAN_DELAY` | `3`: extra seconds for the scan to find devices              |

## Tracking upstream

Eight plugins are forks of Omarchy's first-party shell plugins (their
manifests set `omarchy.clonedFrom`), and every plugin depends on Omarchy's
shell modules. `.omarchy-version` pins the Omarchy release they were last
brought up to date with. `tools/upstream-drift` reports what changed upstream
since that pin:

```bash
tools/upstream-drift                # Markdown: commits and diffstat per path
tools/upstream-drift --diff         # with the full upstream diff per path
tools/upstream-drift --json         # one JSON document, "drift" true or false
tools/upstream-drift --to quattro   # against a branch (Omarchy develops on quattro) or tag
```

It watches `shell/plugins/<name>` for each fork and `shell/Commons`,
`shell/Ui`, `shell/services` and `shell/shell.qml` for everyone. The forks
are decomposed differently from upstream, so there is no merge: read each
commit, port its intent into the matching Aranea files, run `tools/check`,
and bump `.omarchy-version` in the same pull request.

The `Upstream drift` workflow runs the report every Monday and keeps one
issue labelled `upstream-drift` open while there is anything to port. It
updates that issue as upstream moves and closes it once the pin is current.

## Contributions

Keep user-facing behavior documented in `README.md` or `docs/`. Keep agent
interfaces stable and update the relevant contract tests when changing JSONL
events, flags, or exit codes. Prefer the existing script and sandbox patterns
for new operations.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for hooks, commit conventions, and
release workflow.
