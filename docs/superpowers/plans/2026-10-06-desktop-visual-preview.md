# Desktop visual system: representative preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Establish the shared foundation and a coherent bar, launcher, audio and network preview.

**Architecture:** Add opt-in presentation to the existing shared kit; migrate only representative hosts. Preserve font overrides, icon fonts and owner contracts.

**Tech Stack:** Qt Quick/QML, Quickshell, Omarchy shell, JavaScript, Bash and existing token generation.

**Spec:** [../specs/2026-10-06-desktop-visual-system-design.md](../specs/2026-10-06-desktop-visual-system-design.md)

**Prerequisite:** Approved desktop visual system spec; base master 62fe5fb. Preserve the already installed Settings pilot by reusing PR #125 commits on the execution branch, then consolidate its font bindings at checkpoint 4.

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

## File boundaries and produced contracts

Create `plugins/araneadev.shared/Typography.qml` and register it in `qmldir`.
Shared components gain `refined: bool = false`, which preserves legacy appearance
until their host opts in. Header, device-row and pill font properties remain
explicitly overridable. `KeyboardPanelFrame.refined` selects neutral chrome while
retaining the host border width and corner radius. Later plans consume these
contracts and never reimplement focus or activation.

### Task 1: Shared typography and opt-in presentation

**Files:**

- `plugins/araneadev.shared/Typography.qml`
- `plugins/araneadev.shared/PanelChrome.qml`
- `plugins/araneadev.shared/qmldir`
- `plugins/araneadev.shared/DropdownHeader.qml`
- `plugins/araneadev.shared/NodeDeviceRow.qml`
- `plugins/araneadev.shared/FilamentPill.qml`
- `plugins/araneadev.shared/KeyboardPanelFrame.qml`
- `plugins/araneadev.shared/StatusTextPair.qml`
- `plugins/araneadev.shared/README.md`
- `tests/qml/panel-border-preferences.qml`
- `tests/qml/shared.qml`
- `tests/qml/filament-components.qml`

**Interfaces:** Consume `Style.font.family` and the existing host action signals. Produce singleton string properties `Typography.uiFamily`, `Typography.technicalFamily`, `Typography.iconFamily`; opt-in boolean `refined = false` on DropdownHeader, NodeDeviceRow, FilamentPill and KeyboardPanelFrame; and an overridable `StatusTextPair.valueFontFamily` defaulting to its current `fontFamily`. Preserve every existing signal and view-model key.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Create the font roles below. Add documented `refined` properties defaulting false to the existing header, row, pill and panel frame. Keep header and row glyph Text on `iconFamily`; refine labels/captions without uppercasing or tracking. Preserve explicit font properties. Use `PanelChrome.popupBorder(refined)` to start from `Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))`, retaining its resolved widths. For refined frames replace only color with `DesignTokens.surfaceBorder` and disable the gradient. The popup width preferences, including zero and side overrides, remain authoritative. Add a separately overridable value font to StatusTextPair, defaulting to its existing fontFamily. Keep pointer gates, key handling and selected/focus rectangles intact.

```qml
pragma Singleton
import QtQuick
import Quickshell
import qs.Commons

QtObject {
  // Preserve an explicit menu font override for UI surfaces.
  readonly property string uiFamily: Quickshell.env("OMARCHY_MENU_FONT") || "sans-serif"
  // Keep technical content on the desktop monospace alias.
  readonly property string technicalFamily: Style.font.family
  // Keep Nerd Font glyphs independent from proportional UI labels.
  readonly property string iconFamily: Style.font.family
}
```

Register `singleton Typography 1.0 Typography.qml`. On `FilamentPill`, retain
`labelFontFamily` but default it to `refined ? Typography.uiFamily : Style.font.family`;
add `labelLetterSpacing` defaulting to `refined ? 0 : 0.6` and bind the label to it.
On `NodeDeviceRow`, keep label and detail font properties separately overridable.
On `DropdownHeader`, refined caption text uses the original string, regular weight
and zero tracking; legacy captions retain their uppercase treatment.

- [x] Format changed QML files and run the focused command below. Expected: all selected suites pass; no binding, assignment or runtime errors. If a regression appears, reproduce it with a failing behavior test, fix it and run the affected suite again.

```bash
bash tests/qml-behaviour.test.sh shared filament-components highlight-components dropdown-hint-fit
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(shared): add opt-in native visual roles`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 2: Bar and tooltip balance

**Files:**

- `plugins/araneadev.bar/Bar.qml`
- `plugins/araneadev.bar/BarModuleSlot.qml`
- `plugins/araneadev.bar/TooltipBubble.qml`
- `plugins/araneadev.menu/BarWidget.qml`
- `plugins/araneadev.clock/BarWidget.qml`
- `plugins/araneadev.workspaces/BarWidget.qml`
- `tests/qml/bar-components.qml`
- `tests/qml/bar-surface-components.qml`
- `tests/qml/workspaces-widget.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Use proportional tooltip and textual bar labels, retaining clock/workspace numeric alignment and explicit icon fonts. Align slot hover/open indicator insets through existing Style spacing; retain vertical bar, custom widget registry, drag persistence and visibility contracts. Quiet ordinary badges and preserve urgent indicators. Avoid changing user bar composition or replacing third-party widgets.

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
bash tests/qml-behaviour.test.sh bar-components bar-surface-components workspaces-widget workspaces-keyed
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(bar): refine typography and interaction balance`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 3: Launcher and unified search composition

**Files:**

- `plugins/araneadev.menu/MenuStyle.qml`
- `plugins/araneadev.menu/MenuCardChrome.qml`
- `plugins/araneadev.menu/MenuRootTile.qml`
- `plugins/araneadev.menu/MenuResultList.qml`
- `plugins/araneadev.menu/MenuDmenu.qml`
- `plugins/araneadev.menu/MenuWindow.qml`
- `plugins/araneadev.menu/MenuSurface.qml`
- `tests/qml/menu-root.qml`
- `tests/qml/menu-style.qml`
- `tests/qml/menu-desktop-search.qml`
- `tests/qml/menu-dmenu.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Default MenuStyle.fontFamily to Typography.uiFamily while preserving payload overrides. Keep icon glyphs explicitly on iconFamily. Reduce root tiles from 96 to 64 scaled units and context/footer decoration without changing root routes. Keep menu font sizes on host tokens, action tracking at zero and result metadata readable. Make the existing root search hint prominent; preserve query focus, result selection, vanished-target guards, submenu scoping and dmenu output. Retain ceremonial outer framing while quieting internal dividers.

```qml
// MenuStyle keeps its public fontFamily contract for payload overrides.
property string fontFamily: Aranea.Typography.uiFamily
property int rootTileHeight: Style.space(64)
readonly property real menuLetterSpacing: 0
```

In MenuRootTile, leave each glyph Text on `Aranea.Typography.iconFamily` even
when the supplied style uses proportional labels. Retain the current selected
row focus treatment and the measured chrome/card-height formulas.

- [x] Format changed QML files and run the focused command below. Expected: all selected suites pass; no binding, assignment or runtime errors. If a regression appears, reproduce it with a failing behavior test, fix it and run the affected suite again.

```bash
bash tests/qml-behaviour.test.sh menu-root menu-style menu-components menu-desktop-search menu-search-pointer menu-query-header menu-dmenu menu-pointer menu-window-components
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(menu): refine launcher and search hierarchy`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 4: Audio presentation

**Files:**

- `plugins/araneadev.audio/Panel.qml`
- `plugins/araneadev.audio/AudioHeader.qml`
- `plugins/araneadev.audio/AudioDropdown.qml`
- `plugins/araneadev.audio/AudioChannelSection.qml`
- `plugins/araneadev.audio/AudioSourcesSection.qml`
- `plugins/araneadev.audio/AudioNowPlaying.qml`
- `tests/qml/audio-dropdown.qml`
- `tests/qml/audio-keyed.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Opt the host frame/header/device rows/actions into refined presentation. Keep Output and Input volume/device controls together, with current device selection prominent. Use UI type for device/track names and technical type for level percentages and timing. Maintain compact transport controls, slider/switch actions, now-playing availability, node-key checks, layout stamps and stream mute feedback. Reduce redundant decorative separators without hiding available controls.

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
bash tests/qml-behaviour.test.sh audio-dropdown audio-keyed dropdown-hint-fit panel-heights
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(audio): refine device and level hierarchy`. Record the concrete visual outcome in the checkpoint coverage table.

### Task 5: Network presentation

**Files:**

- `plugins/araneadev.network/Panel.qml`
- `plugins/araneadev.network/NetworkHeader.qml`
- `plugins/araneadev.network/NetworkDropdown.qml`
- `plugins/araneadev.network/NetworkWifiSection.qml`
- `plugins/araneadev.network/NetworkLinkSection.qml`
- `plugins/araneadev.network/NetworkInterfacesSection.qml`
- `plugins/araneadev.network/NetworkBandSection.qml`
- `plugins/araneadev.network/NetworkDnsSection.qml`
- `plugins/araneadev.network/NetworkSavedSection.qml`
- `tests/qml/network-dropdown.qml`
- `tests/qml/network-sections.qml`

**Interfaces:** Consume `Aranea.Typography.uiFamily`, `technicalFamily`, `iconFamily` (string font families) and the opt-in `refined` boolean where the shared header, row, pill or panel frame exposes it. Preserve every host's current action signals and view-model keys. No new backend interface is produced.

- [x] Read these files and their listed behavior tests. Confirm the baseline with the command below before editing.
- [x] Opt the host/header/device rows/actions into refined presentation. Lead with current connection and actionable state; keep Wi-Fi and saved-network rows readable. Use UI type for network names and labels; use technical type for addresses, rates, ping and loss. Group band and DNS choices compactly. Retain all observed metadata, credential prompts, scan/readback, busy/error state, keyed network actions and scroll/focus behavior.

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
bash tests/qml-behaviour.test.sh network-dropdown network-sections credential-prompt-texts dropdown-hint-fit panel-heights
```

- [x] Inspect real render/capture at scales 1, 2.5 and 2.667, plus a constrained logical viewport. Check long labels, errors, pending state, keyboard focus, overflow and reduced motion. Technical values and icons must retain their role.
- [x] Commit only the task's owned files with `feat(network): refine connection and control hierarchy`. Record the concrete visual outcome in the checkpoint coverage table.

## Checkpoint delivery

- [x] Review the diff against the approved spec; request independent review using the requesting-code-review skill. Resolve concrete defects before publication.
- [x] Use the Omarchy skill for installed preview work. Back up the current theme, plugin/config files and owner state; create a committed local source with `preview_source=$(mktemp -d /tmp/aranea-desktop-preview.XXXXXX)` followed by `git clone --no-hardlinks . "$preview_source/source"`, then install with `OMARCHY_THEME_SKIP_BACKGROUND=1 scripts/install.sh --source "$preview_source/source" --profile full --yes`. Restore the installed clone's normal GitHub origin after local installation.
- [x] Capture the checkpoint surfaces with `for surface in desktop menu menu-submenu menu-search menu-input apps favorites recent audio network; do scripts/capture-screenshots --surface "$surface" --output screenshots || exit 1; done`. Check every result and stop delivery if any capture fails. First verify the capture workspace is empty. Preserve and compare Settings/owner state, focus and workspace; never publish private app content. Secure/boot captures use the existing inert renderer flow.
- [x] Regenerate `scripts/capture-screenshots --hero --output screenshots` after PNGs are complete. Verify the existing 31-frame order/count and inspect changed frames. Keep cropped diagnostics out of published screenshots.
- [x] Run `tools/check` once on the stable checkpoint tree and inspect all eight stage results. Use `tools/check --only format,lint,docs,validate,qml` for earlier static checks; `--fast` also runs QML behavior and is not a static-only shortcut.
- [ ] Publish a draft PR with the repository template after the gate and review pass. Leave the installed preview available, with an explicit list of covered and remaining families.
- [ ] Ask for visual feedback on this concrete preview before the next checkpoint. Merge and release only when explicitly requested.

## Checkpoint evidence

Source preview: `606c6b2` on `feat/desktop-visual-system`, preserving the
Settings pilot from PR #125. Full `tools/check` passed all eight stages
(78 QML suites / 3,679 checks and 985 JavaScript tests). The final root-search
guidance received four focused QML suites / 35 checks and a fresh passing
format/lint/docs/validate/QML gate. Independent review found the popup-width
compatibility issue; the corrected policy passed six zero/asymmetric-width
regressions after the old policy failed five checks.

The shared popup policy resolves the host's border widths and changes only
color/gradient for refined panels. Legacy shared defaults remain available.
Bar tooltips migrated; registry fonts, numeric workspace labels and bar
composition retain their existing contracts. MenuDmenu and MenuWindow use the
shared MenuStyle changes without a separate visual fork. Launcher chrome keeps
ceremonial framing and presents search guidance without masking notices.

Inert render inspections covered the launcher root, audio, network and tooltip
at scale 1, 2.5 and 2.667 with reduced motion. Narrow audio/network diagnostics
used 320 logical pixels of width. Existing geometry, long-label, pending/error,
focus and credential suites remained green. Ten real desktop captures were
refreshed at 3840x2160 / scale 2.6666667 on empty workspace 2; all seven launcher
variants plus desktop/audio/network were inspected. Hero regeneration retained
31 frames and the established ordering. Diagnostic renders remain in `/tmp`.

The live source was installed through the full profile with background changes
skipped. Owner snapshots compared equal before/after installation; workspace
and focus were restored after capture. Backup: `/tmp/aranea-before-desktop.fSNhjJ`.
The next checkpoint remains everyday controls, after visual feedback on this
concrete preview.
