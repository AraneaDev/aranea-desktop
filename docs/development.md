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

The checks cover formatting, ShellCheck, Markdown, assets, QML, QML tests,
shell contracts, JavaScript behavior, and smoke validation. Some visual or
runtime checks require the Omarchy tooling available on the development host.

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
