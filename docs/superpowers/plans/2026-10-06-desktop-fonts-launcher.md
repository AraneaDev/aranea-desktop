# Desktop font preferences and taller launcher Implementation Plan

> **For agentic workers:** Use executing-plans inline in the existing isolated desktop visual worktree. User approved this design and continued the complete rollout.

**Goal:** Let Appearance configure shared interface and monospace fonts, and give the launcher more vertical room without enlarging controls.

**Architecture:** A focused `aranea-fonts` owner validates installed font families and atomically persists `fonts.json` in the Aranea config directory. The settings adapter exposes catalog/readback and allowlisted mutation; Typography watches this config and supplies the existing shared roles. Icons keep their current dedicated family. Launcher geometry uses the available logical screen height instead of the 250-pixel root-list ceiling.

**Tech Stack:** Existing Bash, fontconfig, QML/Quickshell and JavaScript.

**Spec:** Approved chat follow-up plus `../specs/2026-10-06-desktop-visual-system-design.md`.

## Constraints

- Font families only; retain existing size tokens and display scaling.
- Empty family means default. Reset is a draft requiring Apply; preview samples change before application.
- Preserve explicit environment/menu-payload overrides, dedicated icon fonts and existing owner preferences.
- Search installed families, restrict technical selection to English-capable monospace families, reject unknown selections without changing config.
- Use argv arrays, never evaluate font text. Atomic writes preserve unrelated config and do not create state on reads.
- Settings remains compact, scrollable and keyboard usable at constrained resolutions.
- User asked to continue all remaining components; follow the three existing child plans without requiring renewed authorization between families.

## Task 1: Launcher space

- [x] Exercise real Menu geometry with a long root list at normal and constrained logical screen heights. Assert more than six rows fit at a normal height and the card remains within screen margins at a small height.
- [x] Replace the root-only fixed ceiling in `Menu.qml` with a screen-relative ceiling; retain frozen search top/height and current folding math.
- [x] Run menu-root/menu-pointer/menu-search-pointer/menu-dmenu and JavaScript menu-layout tests, then inspect renders at scale 1, 2.5 and 2.667.

## Task 2: Persisted fonts and settings boundary

- [x] Add `tests/fonts.test.sh` exercising real `scripts/aranea-fonts` against isolated XDG config. Confirm missing helper fails before implementation. Check default read has no writes, named families survive spaces, unknown/non-monospace family rejection preserves prior config, reset and malformed config fallback.
- [x] Implement `scripts/aranea-fonts status --json` and `configure UI MONO` using `fc-list`, validated catalogs and atomic `mktemp`/`mv`; add `RuntimePaths.fontsConfigPath` and watched Typography config.
- [x] Add adapter `configure fonts UI MONO --json`, a fonts section in status, and SettingsLogic allowlist/outcome coverage. Run fonts/settings shell contracts and settings-logic JavaScript tests.

## Task 3: Appearance controls

- [x] Create focused `FontSelector.qml` and `FontsSection.qml`: searchable installed-family lists, default choice, compact controls, keyboard selection, independent drafts, UI/technical samples, Apply and Reset to defaults.
- [x] Wire Appearance to the controller; persist drafts across reopen, acknowledge only successful independent readback, and guard inert/pending/unavailable states.
- [x] Replace hardcoded Settings font families with shared Typography roles. Exercise real controls for filtering, selection, reset, explicit Apply, unavailable/pending guards and narrow scrolling; inspect renders.

## Task 4: Complete consistency rollout

- [x] Execute the remaining everyday-controls, information-pickers and complete-system plans. Apply shared role choices to labels/technical values/glyphs deliberately, preserving host lifecycle and actions.
- [x] Review generated application integrations/assets against the same visual language, retaining native content fonts and documenting unchanged outcomes with visual evidence.
- [x] Run the stable full gate, independent review and complete visual captures. Update PR #126 and install the reviewed source with backup/background-preservation and owner-state comparison. No merge or release.
