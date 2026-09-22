# Aranea Reliability and Polish Implementation Plan

**Goal:** Remove the remaining runtime warnings, make local validation representative of QuickShell, improve health diagnostics and installation safety, and add small user-facing quality-of-life features without weakening Aranea’s dynamic plugin boundaries.

**Architecture:** Keep the existing shell/plugin architecture. Add focused validation and diagnostics at the repository and installer boundaries, fix the duplicate bar IPC registration at the plugin-configuration boundary, and implement user features through existing menu, wallpaper, and bar configuration APIs. Dynamic JSON, IPC, QObject, plugin-registry, and model-row data remains `var`.

**Tech Stack:** Bash, Node.js contract tests, QML/QuickShell, `qmllint`, Omarchy shell IPC, JSON/JSONC, and existing theme scripts.

**Spec:** This document is the approved design and execution plan; progress and evidence are recorded in `docs/aranea-improvement-ledger.md`.

## Global Constraints

- Do not edit `/usr/share/omarchy`; all fixes belong in this repository or user-owned generated configuration.
- Preserve dynamic `var` at plugin, QObject, IPC, JSON, desktop-entry, ListModel, and style-spec boundaries.
- Every behavior change starts with a failing contract test and ends with focused plus full-suite verification.
- Keep installer operations recoverable: stage changes, preserve the prior active theme reference, and report rollback instructions.
- Keep the default UI quiet; new features must be opt-in or low-noise unless they repair an existing failure.
- Update the ledger after each task with status, commit, verification, and remaining risk.

## Scope and task order

### Task 1: Eliminate duplicate `omarchy.bar` IPC registration

Inspect the active shell configuration and plugin loader contract. Add a regression test that detects duplicate IPC targets among enabled plugin entry points, then adjust Aranea’s generated/user shell configuration repair so the stock `omarchy.bar` entry cannot remain instantiated alongside `araneadev.bar`. Verify with a clean shell restart and a fresh log scan.

Files: `scripts/repair-shell-config`, `tests/shell-config.test.sh`, `tests/shell-running.test.sh`, and only the relevant shell configuration fixture. Do not touch `/usr/share/omarchy/shell/plugins/bar/Bar.qml`.

### Task 2: Make local QML validation representative

Extend `tests/qml-types.test.sh` to discover the installed Qt `qmllint`, construct a temporary `qs` import root pointing at Omarchy’s user-space shell modules, and pass the correct import paths. Keep missing optional runtime types as an explicit, documented warning class; fail on syntax, invalid signatures, and errors in Aranea-owned code. Add a concise summary with warning counts and tool version. CI must use the same script.

Files: `tests/qml-types.test.sh`, `.github/workflows/ci.yml`, and a small test fixture only if the script needs one.

### Task 3: Add runtime health checks to `aranea-doctor`

Add checks for shell IPC reachability, Aranea plugin enabled/active state, installed plugin directory freshness, duplicate IPC registrations, recent Aranea QuickShell `TypeError`/`ReferenceError` entries, and local `qmllint` availability/version. Emit stable text and JSON IDs, preserve `ok|repair|skipped` semantics, and keep the command safe when Omarchy or QuickShell is absent.

Files: `scripts/aranea-doctor`, `tests/doctor.test.sh`, and test doubles under `tests/fake-bin/` as needed.

### Task 4: Add safe local-source installation and rollback reporting

Add an installer option for a local checkout source, without changing the current remote default. Before installing, record the active theme path/ref and stage the new theme. On failure, restore the previous active theme selection where possible and print the exact recovery command. Add dry-run and failure-path tests; retain the existing profile and hook behavior.

Files: `scripts/install.sh`, `scripts/lib/manifest.sh` if source validation belongs there, `tests/install.test.sh`, and installer documentation in `README.md`.

### Task 5: Add menu favorites and recent applications

Use the existing normalized menu item model and application library. Add a small persisted favorites list, a bounded recent-launch list, menu routes for both, duplicate-resistant normalization, and graceful behavior when desktop entries disappear. Keep storage under the user state directory and make the feature opt-in through the menu’s existing configuration shape.

Files: `plugins/araneadev.menu/Menu.qml`, `plugins/araneadev.menu/MenuModel.js`, `tests/plugin-state.test.sh`, a focused menu contract test if needed, and `README.md` interaction documentation.

### Task 6: Add automatic day/night wallpaper scheduling

Extend the existing wallpaper script with an explicit schedule command and a user timer/service hook that uses local sunrise/sunset fallback times or configured clock times. Manual selection must override the next transition only, and invalid schedules must fail closed. Add pure schedule tests and dry-run documentation; do not make the installer enable a persistent service without an explicit profile/config choice.

Files: `scripts/aranea-wallpaper`, a new user-owned service/template only if the project’s hook model supports it, `tests/wallpaper.test.sh`, and `README.md`.

### Task 7: Add bar-profile switching and a lightweight health panel

Expose the existing bar profiles through menu actions and add a compact optional health panel showing shell/plugin/validation status. The panel must use existing bar widget contracts, avoid polling more often than necessary, and degrade to a static unavailable state when IPC is down.

Files: `plugins/araneadev.menu/MenuModel.js`, `plugins/araneadev.menu/Menu.qml`, `plugins/araneadev.bar/Bar.qml`, a new focused widget component/manifest if needed, `tests/plugin-state.test.sh`, and README documentation.

### Task 8: Final integration and release checks

Run the complete test suite, shellcheck, real local `qmllint`, live safe deployment, menu/notification/lock smoke checks that are safe in the current session, and a fresh log scan. Update the ledger with evidence and use the finishing-branch workflow to choose merge or PR handling.

## Definition of done

- No duplicate Aranea/stock IPC registration remains in the active configuration.
- Local and CI QML validation use the same command and fail on actionable Aranea-owned errors.
- `aranea-doctor --json` reports the new runtime checks without requiring a running shell.
- Installer local-source and rollback paths have automated dry-run/failure coverage.
- Favorites/recent apps, wallpaper scheduling, profile switching, and health panel each have focused contracts and documented opt-in behavior.
- Full repository tests, shellcheck, QML validation, live smoke checks, and ledger evidence are current.
