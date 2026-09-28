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

### Design tokens

Edit `design/tokens.toml` to change the shared palette, shell surfaces,
spacing, typography, or motion defaults. Regenerate the committed projections
with `scripts/generate-tokens --write`; platform projections are templated in
`design/templates/`, and `scripts/generate-tokens --check` is the drift check
used by the token contract test.

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

Use `plugins/araneadev.shared` for visual contracts that are identical across
plugins: `SurfaceCard`, `PanelHeader`, `StatusRail`, `StatusTextPair`, and
`KeyboardPanelFrame`. Keep lifecycle, cursor, and plugin-specific interaction
logic in the owning plugin rather than adding it to shared components.

Generated asset outputs must not be edited directly. Change
`design/tokens.toml` or the relevant template, run
`scripts/generate-tokens --write`, and verify with
`scripts/generate-tokens --check`.

## Showcase captures

The README is a visual showcase as well as a project introduction. Refresh
captures with:

```bash
scripts/capture-screenshots --all --output screenshots
```

Lock and Plymouth use canonical artwork renders; the capture workflow should
not lock the active session or reboot the machine.

## Contributions

Keep user-facing behavior documented in `README.md` or `docs/`. Keep agent
interfaces stable and update the relevant contract tests when changing JSONL
events, flags, or exit codes. Prefer the existing script and sandbox patterns
for new operations.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for hooks, commit conventions, and
release workflow.
