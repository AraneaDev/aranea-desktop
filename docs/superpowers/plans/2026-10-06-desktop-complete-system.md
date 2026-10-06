# Desktop visual system: complete desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Execution:** User approved inline completion of the remaining families together. Delivery uses the existing PR #126 and one complete installed preview. Source commits are grouped by font/launcher, shared chrome, controls, information/time and secure surfaces; unchanged application/assets are recorded in the master coverage table without empty feature commits.

**Goal:** Complete Settings, immediate feedback, secure/ceremonial surfaces and application/asset integrations, then review the entire desktop.

**Architecture:** Consolidate reviewed font/control defaults after every shared consumer is migrated. Generated integrations keep canonical token/template ownership and native content fonts.

**Tech Stack:** Qt Quick/QML, Quickshell, Omarchy shell, JavaScript, Bash and existing token generation.

**Spec:** [../specs/2026-10-06-desktop-visual-system-design.md](../specs/2026-10-06-desktop-visual-system-design.md)

**Prerequisite:** Plans 1-3 accepted; preserve and adapt PR #125 Settings changes rather than duplicating them.

## Global constraints

- Keep the obsidian palette, mint interaction, violet identity, spider mark and filament motifs.
- UI text defaults to the system `sans-serif` alias, without bundling a new font.
- Technical text uses the desktop monospace family.
- An explicit override takes precedence over the proportional default.
- Keep icon glyphs on their existing dedicated font paths.
- Use existing host font-size tokens and `Style.space` scaling.
- Preserve the user's panel corner radius and border-width preferences.
- All motion respects reduced motion and has an equally clear static state.
- Preserve backend commands, IPC, routes, dmenu results, authentication protocols, clipboard masking, notification ownership, persistent settings and owner readback.
- This design introduces no new runtime dependency or backend feature.
- Feature hosts own lifecycle, focus, selection, scrolling and owner operations.
- Update canonical tokens/templates and regenerate projections. Never edit `/usr/share/omarchy`.
- Cosmetic work uses existing meaningful behavior/geometry tests and visual inspection. Add a failing regression test before changing behavior or fixing an uncovered bug; do not write tests that duplicate decoration.
- Document root QML properties/signals/functions inline; format owned QML files with `/usr/lib/qt6/bin/qmlformat -i`.
- Keep each task in a focused commit. Preserve clean master, independent review and installed preview checkpoints.

### Task 1: Settings and OSD integration

**Files:**

- `plugins/araneadev.settings/SettingsLabel.qml`
- `plugins/araneadev.settings/SettingsButton.qml`
- `plugins/araneadev.settings/SettingsNavigation.qml`
- `plugins/araneadev.settings/SettingsPageHeader.qml`
- `plugins/araneadev.settings/SettingsSurface.qml`
- `plugins/araneadev.settings/AppearancePage.qml`
- `plugins/araneadev.settings/DisplayPage.qml`
- `plugins/araneadev.settings/SchedulePage.qml`
- `plugins/araneadev.settings/IntegrationsPage.qml`
- `plugins/araneadev.settings/NotificationsPage.qml`
- `plugins/araneadev.osd/Osd.qml`
- `plugins/araneadev.osd/OsdStrand.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Replace pilot hardcoded font families with shared roles while preserving PR #125 typography/gallery refinements. Keep compact Settings, exact decimal drafts, owner metadata and scrolling. Refine OSD labels/levels with minimal chrome; preserve timing and input/owner contracts. Scope status copy changes to wording that preserves the observed outcome.

```qml
// UI text; technical values and glyphs bind their separate roles.
font.family: Aranea.Typography.uiFamily
// Numeric fields, paths, commands and telemetry use this instead:
// font.family: Aranea.Typography.technicalFamily
// Glyph-only Text items retain this instead:
// font.family: Aranea.Typography.iconFamily
```

- [x] Format changed QML files and run the focused command below. Expected: all selected suites pass; no binding, assignment or runtime errors. If a regression appears, reproduce it with a failing behavior test, fix it and run the affected suite again.

```bash
bash tests/qml-behaviour.test.sh settings-scroll settings-components settings-pages settings-density settings-scale settings-showcase settings-thumbnail settings-toggle osd-strand
bash tests/run settings settings-capture settings-preview
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(settings): integrate shared desktop visual roles`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 2: Authentication and lock/idle

**Files:**

- `plugins/araneadev.polkit/PolkitWindow.qml`
- `plugins/araneadev.polkit/PolkitPromptCard.qml`
- `plugins/araneadev.polkit/PolkitAuthField.qml`
- `plugins/araneadev.polkit/PolkitDetails.qml`
- `plugins/araneadev.lock/LockView.qml`
- `plugins/araneadev.lock/LockBranding.qml`
- `plugins/araneadev.lock/LockClock.qml`
- `plugins/araneadev.lock/LockAuthPanel.qml`
- `branding/screensaver.txt`
- `design/brand.toml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Use proportional human-facing prompts and retain monospace commands/action identifiers. Coordinate title/mark proportions and input focus states; keep ceremonial framing restrained. Preserve auth agents, challenges, cancel/error, secure-session lifecycle and input ownership. Verify lock through the inert renderer and tests, without locking the live session. Review idle identity against the same branding proportions.

```qml
// UI text; technical values and glyphs bind their separate roles.
font.family: Aranea.Typography.uiFamily
// Numeric fields, paths, commands and telemetry use this instead:
// font.family: Aranea.Typography.technicalFamily
// Glyph-only Text items retain this instead:
// font.family: Aranea.Typography.iconFamily
```

- [x] Format changed QML files and run the focused command below. Expected: all selected suites pass; no binding, assignment or runtime errors. If a regression appears, reproduce it with a failing behavior test, fix it and run the affected suite again.

```bash
bash tests/qml-behaviour.test.sh polkit polkit-components lock-components lock-clock-components overlay-components
bash tests/run branding brand-assets
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(secure): refine prompt and lock presentation`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 3: Application integrations and identity assets

**Files:**

- `design/tokens.toml`
- `design/templates/gtk.css.in`
- `design/templates/integrations/qt/kvantum/Aranea/Aranea.kvconfig.in`
- `design/templates/integrations/terminal/alacritty.toml.in`
- `design/templates/integrations/terminal/foot.ini.in`
- `design/templates/integrations/terminal/kitty.conf.in`
- `design/templates/integrations/developer/btop.theme.in`
- `design/templates/integrations/developer/lazygit.yml.in`
- `design/templates/integrations/developer/starship.toml.in`
- `design/templates/integrations/developer/tmux.conf.in`
- `design/templates/cava-theme.in`
- `integrations/browser/aranea.css`
- `integrations/browser/firefox/userChrome.css`
- `integrations/browser/firefox/userContent.css`
- `integrations/browser/chromium/new-tab/style.css`
- `integrations/media/pavucontrol.css`
- `design/templates/assets/cursor-left_ptr.svg.in`
- `design/templates/assets/cursor-hand2.svg.in`
- `design/templates/assets/cursor-watch.svg.in`
- `scripts/generate-font-icon-theme`
- `integrations/icons/aranea/scalable/`
- `design/brand.toml`
- `unlock.png`
- `backgrounds/manifest.toml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Inspect GTK/Qt/file-manager/browser presentation against the reviewed neutral surfaces, selection palette and UI typography. Modify canonical templates and regenerate outputs with scripts/generate-tokens --write; keep terminal/editor content monospace. Review Cava/media contrast and motion. Review icon weight from `scripts/generate-font-icon-theme` and its projected `integrations/icons/aranea/scalable/` SVGs; change tracing only if the visual review requires it and regenerate with `scripts/generate-font-icon-theme`. Review both cursor families from the listed canonical SVG templates; retain assets that already satisfy the direction and record the reason. Coordinate boot mark through the existing generated unlock asset and tools/render-plymouth-preview, preserving packaged boot geometry. Verify every wallpaper variant for text contrast without redesigning images merely to create a diff. Do not reboot or edit system-owned boot files.

```bash
# Update canonical token/template sources first, then regenerate projections.
scripts/generate-tokens --write
scripts/generate-tokens --check
```

GTK/Qt UI surfaces follow native UI font preferences. Terminal, editor, code,
paths and process telemetry retain their existing monospace content fonts.
Boot prompt text remains host-owned; review its stock UI typography and theme
mark/palette without changing `/usr/share/omarchy/default/plymouth`.

- [x] Format changed QML files and run the focused command below. Expected: all selected suites pass; no binding, assignment or runtime errors. If a regression appears, reproduce it with a failing behavior test, fix it and run the affected suite again.

```bash
scripts/generate-tokens --check
bash tests/run tokens icons brand-assets branding application-integrations plymouth-render
tools/render-plymouth-preview --output /tmp/aranea-visual-system-boot.png
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(integrations): align application and desktop presentation`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 4: Consolidation and complete visual inventory

**Files:**

- `plugins/araneadev.shared/Typography.qml`
- `plugins/araneadev.shared/DropdownHeader.qml`
- `plugins/araneadev.shared/NodeDeviceRow.qml`
- `plugins/araneadev.shared/FilamentPill.qml`
- `plugins/araneadev.shared/KeyboardPanelFrame.qml`
- `plugins/araneadev.shared/OverlayChrome.qml`
- `docs/visual-language.md`
- `docs/superpowers/plans/2026-10-06-desktop-visual-system.md`
- `screenshots/`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Audit every shared consumer before consolidating refined defaults. Preserve legacy behavior wherever a third-party or externally loaded consumer still depends on it; remove redundant opt-in bindings only when consumer coverage proves equivalence. Complete the inventory for every component family with concrete outcome, capture and checks. Update public visual-language documentation to describe the delivered system. Close the Settings-only draft as superseded only once the broader PR demonstrably contains its approved changes.

```qml
// UI text; technical values and glyphs bind their separate roles.
font.family: Aranea.Typography.uiFamily
// Numeric fields, paths, commands and telemetry use this instead:
// font.family: Aranea.Typography.technicalFamily
// Glyph-only Text items retain this instead:
// font.family: Aranea.Typography.iconFamily
```

- [x] Format changed QML files and run the focused command below. Expected: all selected suites pass; no binding, assignment or runtime errors. If a regression appears, reproduce it with a failing behavior test, fix it and run the affected suite again.

```bash
bash tests/qml-behaviour.test.sh shared filament-components highlight-components overlay-components panel-heights dropdown-hint-fit
tools/check
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `docs: document and verify complete desktop refinement`. Record the concrete visual outcome in the checkpoint coverage table.

## Checkpoint delivery

- [x] Review the diff against the approved spec; request independent review using the requesting-code-review skill. Resolve concrete defects before publication.
- [x] Use the Omarchy skill for installed preview work. Back up the current theme, plugin/config files and owner state; create a committed local source with `preview_source=$(mktemp -d /tmp/aranea-desktop-preview.XXXXXX)` followed by `git clone --no-hardlinks . "$preview_source/source"`, then install with `OMARCHY_THEME_SKIP_BACKGROUND=1 scripts/install.sh --source "$preview_source/source" --profile full --yes`. Restore the installed clone's normal GitHub origin after local installation.
- [x] Capture the checkpoint surfaces with `for surface in settings settings-scaling osd lock polkit dawn plymouth btop file-manager neovim desktop; do scripts/capture-screenshots --surface "$surface" --output screenshots || exit 1; done`. Check every result and stop delivery if any capture fails. First verify the capture workspace is empty. Preserve and compare Settings/owner state, focus and workspace; never publish private app content. Secure/boot captures use the existing inert renderer flow.
- [x] Regenerate `scripts/capture-screenshots --hero --output screenshots` after PNGs are complete. Verify the existing 31-frame order/count and inspect changed frames. Keep cropped diagnostics out of published screenshots.
- [x] Run `tools/check` once on the stable checkpoint tree and inspect all eight stage results. Use `tools/check --only format,lint,docs,validate,qml` for earlier static checks; `--fast` also runs QML behavior and is not a static-only shortcut.
- [x] Publish a draft PR with the repository template after the gate and review pass. Leave the installed preview available, with an explicit list of covered and remaining families.
- [x] Ask for visual feedback on this concrete preview before the next checkpoint. Merge and release only when explicitly requested.
