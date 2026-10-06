# Desktop visual system: everyday controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Execution:** User approved inline completion of the remaining families together. Delivery uses the existing PR #126 and one complete installed preview. Source commits are grouped by font/launcher, shared chrome, controls, information/time and secure surfaces; unchanged application/assets are recorded in the master coverage table without empty feature commits.

**Goal:** Extend the reviewed foundation through Bluetooth, VPN, displays, power, tray and workspace/menu flows.

**Architecture:** Migrate existing hosts and sections to the reviewed shared role/opt-in contracts. Keep device operations and keyed actions in their current owners.

**Tech Stack:** Qt Quick/QML, Quickshell, Omarchy shell, JavaScript, Bash and existing token generation.

**Spec:** [../specs/2026-10-06-desktop-visual-system-design.md](../specs/2026-10-06-desktop-visual-system-design.md)

**Prerequisite:** Representative preview accepted; consume Typography font roles and shared refined properties from plan 1.

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

### Task 1: Bluetooth and VPN

**Files:**

- `plugins/araneadev.bluetooth/Panel.qml`
- `plugins/araneadev.bluetooth/BluetoothHeader.qml`
- `plugins/araneadev.bluetooth/BluetoothDropdown.qml`
- `plugins/araneadev.bluetooth/BluetoothDeviceSection.qml`
- `plugins/araneadev.vpn/Panel.qml`
- `plugins/araneadev.vpn/VpnHeader.qml`
- `plugins/araneadev.vpn/VpnDropdown.qml`
- `plugins/araneadev.vpn/VpnSection.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Use refined frames/headers/rows and native device/provider names. Keep connected state first and status/error text beside its row; retain readable forget/connect controls and technical identifiers. Preserve credential, discovery, keyed activation, forget-hover and connection-confirmation contracts.

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
bash tests/qml-behaviour.test.sh bluetooth-dropdown bluetooth-keyed bluetooth-forget-hover vpn-dropdown credential-prompt-texts
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(devices): refine bluetooth and vpn presentation`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 2: Displays and power

**Files:**

- `plugins/araneadev.monitor/Panel.qml`
- `plugins/araneadev.monitor/DisplaysDropdown.qml`
- `plugins/araneadev.monitor/DisplaysList.qml`
- `plugins/araneadev.monitor/DisplaysControlRow.qml`
- `plugins/araneadev.monitor/DisplaysToggles.qml`
- `plugins/araneadev.monitor/DisplaysCaption.qml`
- `plugins/araneadev.power/Panel.qml`
- `plugins/araneadev.power/PowerDropdown.qml`
- `plugins/araneadev.power/PowerHero.qml`
- `plugins/araneadev.power/PowerDraw.qml`
- `plugins/araneadev.power/PowerHistory.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Use refined frames and grouped compact preset actions. Lead with display/battery summary; use monospace for resolutions, scales, percentages, charge timing and chart data. Keep all display and profile operations, observed availability and existing safe change confirmation. Make supporting statistics visually secondary without deleting them.

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
bash tests/qml-behaviour.test.sh displays-dropdown power-dropdown panel-heights dropdown-hint-fit
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(hardware): refine displays and power controls`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 3: Tray and workspaces

**Files:**

- `plugins/araneadev.tray/Tray.qml`
- `plugins/araneadev.tray/TrayMenuView.qml`
- `plugins/araneadev.tray/TrayManageView.qml`
- `plugins/araneadev.workspaces/WorkspacePanelHost.qml`
- `plugins/araneadev.workspaces/WorkspacePanel.qml`
- `plugins/araneadev.workspaces/BarWidget.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Refine tray rows, management controls and workspace/window listings. Keep glyph alignment and quiet badges consistent with the bar; distinguish current workspace from keyboard focus. Use UI text for titles and technical text for workspace numbers and app identifiers when shown. Preserve tray provider menu semantics, item lifetime, keyed window activation and persistent hidden/pinned settings.

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
bash tests/qml-behaviour.test.sh tray-menu tray-manage workspaces-widget workspaces-keyed
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(navigation): refine tray and workspace surfaces`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 4: Complete command-menu variants

**Files:**

- `plugins/araneadev.menu/MenuAppLibrary.qml`
- `plugins/araneadev.menu/MenuAppHistory.qml`
- `plugins/araneadev.menu/MenuResultList.qml`
- `plugins/araneadev.menu/MenuDmenu.qml`
- `plugins/araneadev.menu/MenuCardChrome.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Review apps, favorites, recent, submenu, input and no-match/vanished search flows with the reviewed launcher typography and chrome. Preserve payload fonts, literal plain-text display, query filtering and current-target activation. Keep type labels and empty states readable and provide consistent selection/hover without enlarging rows.

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
bash tests/qml-behaviour.test.sh menu menu-app-history menu-dmenu menu-desktop-search menu-desktop-guards menu-search-pointer menu-pointer
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(menu): carry native presentation through command flows`. Record the concrete visual outcome in the checkpoint coverage table.

## Checkpoint delivery

- [x] Review the diff against the approved spec; request independent review using the requesting-code-review skill. Resolve concrete defects before publication.
- [x] Use the Omarchy skill for installed preview work. Back up the current theme, plugin/config files and owner state; create a committed local source with `preview_source=$(mktemp -d /tmp/aranea-desktop-preview.XXXXXX)` followed by `git clone --no-hardlinks . "$preview_source/source"`, then install with `OMARCHY_THEME_SKIP_BACKGROUND=1 scripts/install.sh --source "$preview_source/source" --profile full --yes`. Restore the installed clone's normal GitHub origin after local installation.
- [x] Capture the checkpoint surfaces with `for surface in bluetooth vpn monitor power tray tray-manage workspaces menu menu-submenu apps favorites recent; do scripts/capture-screenshots --surface "$surface" --output screenshots || exit 1; done`. Check every result and stop delivery if any capture fails. First verify the capture workspace is empty. Preserve and compare Settings/owner state, focus and workspace; never publish private app content. Secure/boot captures use the existing inert renderer flow.
- [x] Regenerate `scripts/capture-screenshots --hero --output screenshots` after PNGs are complete. Verify the existing 31-frame order/count and inspect changed frames. Keep cropped diagnostics out of published screenshots.
- [x] Run `tools/check` once on the stable checkpoint tree and inspect all eight stage results. Use `tools/check --only format,lint,docs,validate,qml` for earlier static checks; `--fast` also runs QML behavior and is not a static-only shortcut.
- [x] Publish a draft PR with the repository template after the gate and review pass. Leave the installed preview available, with an explicit list of covered and remaining families.
- [x] Ask for visual feedback on this concrete preview before the next checkpoint. Merge and release only when explicitly requested.
