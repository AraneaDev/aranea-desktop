# Aranea Improvement Ledger

This ledger is updated during execution. A task is not marked complete without command evidence.

| Task | Status | Commit | Evidence | Remaining risk |
|---|---|---|---|---|
| 1. Duplicate `omarchy.bar` IPC registration | in progress | — | Aranea’s handler was removed and the regression test passes, but a fresh shell still reports the warning; installed `tim.bar` is a second user-owned `clonedFrom: omarchy.bar` manifest | Need identify why the disabled legacy clone is still loaded without deleting user-owned plugin data |
| 2. Local QML validation | complete | pending commit | `tests/qml-types.test.sh` passes with `qmllint 6.11.2` and a temporary `qs` import root; 373 non-fatal runtime-context warnings remain | Need decide which warnings are actionable versus QuickShell-only context |
| 3. Runtime doctor checks | complete | pending commit | Test overrides pass; live `aranea-doctor --json` reports shell `ok`, plugins `ok`, runtime `ok`, and `qmllint 6.11.2` `ok` | Doctor’s shell IPC check requires the real user session, as intended |
| 4. Local install and rollback | pending | — | Current installer fetches remote source by default | Local source and recovery path not implemented |
| 5. Favorites and recent apps | pending | — | Menu model already normalizes item records and application rows | Persistence and UI routes not implemented |
| 6. Wallpaper scheduling | pending | — | Existing wallpaper command supports list/set and has pure manifest tests | Schedule model and timer integration not implemented |
| 7. Profile switching and health panel | pending | — | Bar profiles and plugin IPC already exist | Menu exposure and panel design not implemented |
| 8. Final integration | pending | — | Branch created from merged `master` | Depends on tasks 1–7 |

## Evidence log

| Timestamp | Task | Command/result |
|---|---|---|
| 2026-09-22 | Baseline | `git pull --ff-only`: master at `c433233` (merged PR #8) |
| 2026-09-22 | Tooling | `qmllint --version`: `6.11.2`; `tests/qml-types.test.sh`: exit 0 with import-context warnings |
| 2026-09-22 | Runtime | Shell ping `ok`; fresh log reports duplicate stock/custom `omarchy.bar` IPC registration |
| 2026-09-22 | Task 1 | `tests/shell-config.test.sh` and `tests/shell-running.test.sh` pass; safe deploy/restart still logs duplicate `omarchy.bar`, so Task 1 remains open |
| 2026-09-22 | Task 2 | `bash tests/qml-types.test.sh`: exit 0; `qmllint 6.11.2`; temporary `qs` import root created and cleaned; 373 warnings, no errors |
| 2026-09-22 | Task 3 | `bash tests/doctor.test.sh`, `shellcheck -x scripts/aranea-doctor tests/doctor.test.sh`, and live `scripts/aranea-doctor --json`: all passed; live statuses shell/plugins/runtime/qmllint are `ok` |
