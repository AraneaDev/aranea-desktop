# Desktop visual system: information and pickers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Execution:** User approved inline completion of the remaining families together. Delivery uses the existing PR #126 and one complete installed preview. Source commits are grouped by font/launcher, shared chrome, controls, information/time and secure surfaces; unchanged application/assets are recorded in the master coverage table without empty feature commits.

**Goal:** Complete notification, system-information, picker, clock and weather presentation.

**Architecture:** Use reviewed shared roles/chrome while keeping content-specific layouts, masking, disclosure and owner sampling intact.

**Tech Stack:** Qt Quick/QML, Quickshell, Omarchy shell, JavaScript, Bash and existing token generation.

**Spec:** [../specs/2026-10-06-desktop-visual-system-design.md](../specs/2026-10-06-desktop-visual-system-design.md)

**Prerequisite:** Plans 1 and 2 previewed; Typography and refined shared controls available.

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

### Task 1: Notifications

**Files:**

- `plugins/araneadev.notifications/Panel.qml`
- `plugins/araneadev.notifications/NotificationCenterContent.qml`
- `plugins/araneadev.notifications/NotificationList.qml`
- `plugins/araneadev.notifications/components/NotificationCard.qml`
- `plugins/araneadev.notifications/components/NotificationGroupRow.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Refine titles, descriptions, timestamps and group controls. Reduce redundant card framing and insets while keeping urgency labels/markers and readable content. Preserve two-step clear-all, grouping, expansion, app actions, inbox ownership, scroll limits and focus restoration. Ordinary notifications remain quiet; critical status remains unmistakable.

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
bash tests/qml-behaviour.test.sh notifications notification-components notification-list notification-center-components notification-center-header notification-center-fit notification-inbox-snapshot
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(notifications): refine card and group hierarchy`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 2: Health, Agents and updates

**Files:**

- `plugins/araneadev.health/HealthDropdown.qml`
- `plugins/araneadev.health/HealthSummary.qml`
- `plugins/araneadev.health/HealthResourceSection.qml`
- `plugins/araneadev.health/HealthProcessSection.qml`
- `plugins/araneadev.health/HealthProblemsSection.qml`
- `plugins/araneadev.agents/AgentsDropdown.qml`
- `plugins/araneadev.agents/AgentsHeader.qml`
- `plugins/araneadev.agents/AgentsSwitch.qml`
- `plugins/araneadev.agents/AgentsLimitsSection.qml`
- `plugins/araneadev.agents/AgentsBalanceSection.qml`
- `plugins/araneadev.agents/AgentsUsageSection.qml`
- `plugins/araneadev.updates/UpdatePanel.qml`
- `plugins/araneadev.updates/UpdatePanelHost.qml`
- `plugins/araneadev.shared/DisclosureSection.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Build on the current summary/details layout rather than reimplementing it. Use proportional labels, technical values with adjacent units, quieter charts and consistent section hierarchy. Keep actionable problems, all provider limits/balance and auth errors prominent. Preserve disclosure resets, sampling, refresh outcomes and process/provider keyed activation.

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
bash tests/qml-behaviour.test.sh health health-keyed health-panel-components agents-dropdown updates-dropdown disclosure-section panel-heights
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(status): refine system summaries and telemetry`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 3: Clipboard, emoji and image picker

**Files:**

- `plugins/araneadev.clipboard/ClipboardWindow.qml`
- `plugins/araneadev.clipboard/components/ClipboardResultsPane.qml`
- `plugins/araneadev.clipboard/components/ClipboardResultRow.qml`
- `plugins/araneadev.clipboard/components/ClipboardPreview.qml`
- `plugins/araneadev.emojis/EmojiWindow.qml`
- `plugins/araneadev.emojis/EmojiPickerContent.qml`
- `plugins/araneadev.emojis/EmojiPickerChrome.qml`
- `plugins/araneadev.emojis/EmojiGrid.qml`
- `plugins/araneadev.emojis/EmojiCell.qml`
- `plugins/araneadev.shared/OverlayChrome.qml`
- `design/tokens.toml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Balance list/grid and preview width at constrained sizes. Use proportional labels and technical code/path previews; preserve secret masking, pin/copy/paste/insert actions and keyed pointer activation. Add documented `OverlayChrome.refined: bool = false`; its existing chrome remains the default, while `refined` selects neutral borders and proportional heading/label fonts through `Typography.uiFamily`, keeping icon glyphs on `Typography.iconFamily`. Set `refined: true` explicitly in the Clipboard and Emojis hosts. Review the stock image-picker against supported [shell.image-picker] tokens and existing payload options; its labels inherit the stock UI font. Do not edit or fork packaged ImagePicker.qml. Record its inspected outcome and any host limitation explicitly.

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
bash tests/qml-behaviour.test.sh clipboard clipboard-components clipboard-pointer clipboard-preview-components emoji-components emoji-pointer overlay-components
bash tests/run tokens capture-showcase
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(pickers): refine browsing and preview layouts`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 4: Calendar and weather

**Files:**

- `plugins/araneadev.clock/ClockDropdown.qml`
- `plugins/araneadev.clock/ClockGrid.qml`
- `plugins/araneadev.clock/ClockSky.qml`
- `plugins/araneadev.clock/ClockLife.qml`
- `plugins/araneadev.clock/ClockLink.qml`
- `plugins/araneadev.weather/WeatherDropdown.qml`
- `plugins/araneadev.weather/WeatherHero.qml`
- `plugins/araneadev.weather/WeatherDetails.qml`
- `plugins/araneadev.weather/WeatherDays.qml`
- `plugins/araneadev.weather/WeatherHourly.qml`
- `plugins/araneadev.weather/WeatherAir.qml`
- `plugins/araneadev.weather/WeatherPlaceEdit.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Let the calendar/current temperature and forecast lead. Use proportional headings/place names and technical times/statistics; keep selected dates and keyboard targets distinct. Reduce repeated outlining and improve chart labels. Preserve calendar navigation, place search, refresh timing, timezone/date math and all unavailable/weather states.

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
bash tests/qml-behaviour.test.sh clock-dropdown weather-dropdown dropdown-hint-fit panel-heights
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(time): refine calendar and weather composition`. Record the concrete visual outcome in the checkpoint coverage table.

## Checkpoint delivery

- [x] Review the diff against the approved spec; request independent review using the requesting-code-review skill. Resolve concrete defects before publication.
- [x] Use the Omarchy skill for installed preview work. Back up the current theme, plugin/config files and owner state; create a committed local source with `preview_source=$(mktemp -d /tmp/aranea-desktop-preview.XXXXXX)` followed by `git clone --no-hardlinks . "$preview_source/source"`, then install with `OMARCHY_THEME_SKIP_BACKGROUND=1 scripts/install.sh --source "$preview_source/source" --profile full --yes`. Restore the installed clone's normal GitHub origin after local installation.
- [x] Capture the checkpoint surfaces with `for surface in notifications notifications-empty health agents updates clipboard emojis image-picker clock weather; do scripts/capture-screenshots --surface "$surface" --output screenshots || exit 1; done`. Check every result and stop delivery if any capture fails. First verify the capture workspace is empty. Preserve and compare Settings/owner state, focus and workspace; never publish private app content. Secure/boot captures use the existing inert renderer flow.
- [x] Regenerate `scripts/capture-screenshots --hero --output screenshots` after PNGs are complete. Verify the existing 31-frame order/count and inspect changed frames. Keep cropped diagnostics out of published screenshots.
- [x] Run `tools/check` once on the stable checkpoint tree and inspect all eight stage results. Use `tools/check --only format,lint,docs,validate,qml` for earlier static checks; `--fast` also runs QML behavior and is not a static-only shortcut.
- [x] Publish a draft PR with the repository template after the gate and review pass. Leave the installed preview available, with an explicit list of covered and remaining families.
- [x] Ask for visual feedback on this concrete preview before the next checkpoint. Merge and release only when explicitly requested.
