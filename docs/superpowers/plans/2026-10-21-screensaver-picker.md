# Automatic Screensavers and Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install the approved spider as the automatic screensaver and provide a visual catalog picker with optional shuffle for future scenes.

**Architecture:** Omarchy retains idle/lock authority. A managed user launcher selects a trusted catalog entry and starts one supervised custom session across monitors, with fixed web/video renderers and owned cleanup. The existing Settings controller/backend exposes catalog state and explicit selection/preview actions; the UI never executes catalog text.

**Tech Stack:** Bash, Python 3 standard library, Chromium/WebGL/Three.js, mpv/Lua, Hyprland IPC, QML/Quickshell, existing Node/shell/QML test harnesses.

**Spec:** `docs/superpowers/specs/2026-10-21-screensaver-picker-design.md` (user approved).

## Global Constraints

- Initial scenes: Silk Journey (`silk-journey`, web, default), Silk Chamber (`silk-chamber`, video), Omarchy (`omarchy`, stock).
- Preserve current 900-second screensaver and 1,200-second lock settings until explicit timing Apply. Provide editable idle deadlines backed by Omarchy shell.json; see Timing controls below.
- Keep Omarchy's idle service as authority for timing, stay-awake, screensaver-off, wake and lock; custom windows must use exact class `org.omarchy.screensaver`.
- Do not edit packaged Omarchy files or clone its idle state machine. Do not rewrite general PATH configuration.
- Install a user-owned, ledger-managed launcher shim, active only for Aranea. Verify resolution in the same login-shell context as idle launch.
- Config/catalog never contains executable command strings; supported renderer kinds map to fixed local argv. Validate IDs, asset containment, availability and config versions.
- Preview does not save selection; ordinary key/click/pointer motion dismisses the entire custom session after launch grace.
- One scene/session across active monitors. Duplicate starts cannot add another session. Restore focus/workspace, stop removed-monitor surfaces, include newly attached monitors next activation.
- Preflight failure before mapping can delegate to stock. Once mapped, failure tears down custom session and ends the idle cycle; no replacement after the final window closes.
- Require bounded renderer readiness; remove owned processes, profiles, socket and server on dismissal, lock, signals, startup failure or renderer failure.
- Preserve legacy `preview`, `video`, and `tools/spider/preview.py --serve-only` behavior. Preserve frame/pixel caps and existing artwork/model bytes.
- Shuffle selects available Aranea scenes once per automatic idle session, avoids previous when possible, excludes stock, and does not change saved selection.
- Reuse Settings styles, persistent controller ownership, typed argv and explicit Apply. No bar layout changes.
- All untrusted text uses plain text; new picker strings use `Commons.Translations` with English catalog initially.
- Normal commits, no hook bypass, warning suppression, weakened assertions or skipped required checks. Relevant focused gates per task; complete integration gate before installation.
- Root owns native QA/installation. Use sandboxed fake commands for automated tests; never run real lock/shutdown or mutate user's timers in tests.
- Work on `feat/screensaver-picker` in managed worktree `/home/tim/.codex/worktrees/df87/omarchy-aranea-theme`; no push/merge/release in this request.

## File and interface map

`branding/screensavers/catalog.json`: trusted versioned scene definitions. `tools/screensaver/catalog.py`: parsing, containment, availability and choice. `preferences.py`: locked atomic user config and last automatic scene. `cli.py`: owner command boundary. `http_server.py`: bounded asset serving and authenticated renderer events. `renderers.py`: fixed browser/video launch and owned process-group teardown. `hyprland.py`: bounded IPC and monitor/workspace snapshots/placement. `session.py`: one-session supervision, control socket, readiness and cleanup. Avoid growing these into interchangeable plugin frameworks.

Public scene projection: `{id,label,description,renderer,thumbnail,available,reason,shuffleEligible}`. `thumbnail` is absolute local path or null. Catalog source fields for web are `root`, `entry`, `publicPaths`; video uses `asset`; stock has no executable field. All file references are relative to repository root and resolve inside `branding/`.

Owner snapshot:
```json
{"availability":"available","catalogAvailable":true,"selectedId":"silk-journey","mode":"single","choices":[],"integration":{"installed":false,"reachable":false},"idle":{"screensaverSeconds":900,"lockSeconds":1200},"session":{"running":false,"ready":false,"sceneId":null,"preview":false},"error":null}
```
Unavailable runtime dependencies affect scene availability, not validity of the whole catalog; reads must not create directories. Invalid configuration reports an actionable error instead of silently overwriting it.

Owner CLI:
```text
scripts/aranea-screensaver list --json
scripts/aranea-screensaver status --json
scripts/aranea-screensaver configure ID single|shuffle --json
scripts/aranea-screensaver start [force]
scripts/aranea-screensaver preview-scene ID --json
scripts/aranea-screensaver stop --json
```
`configure` prints updated owner snapshot. `preview-scene` returns a bounded JSON acknowledgment `{accepted:true,sessionId:...}` after a supervised launch is accepted; it never waits for dismissal or claims a rendered frame prematurely. Errors are one JSON object on JSON routes with nonzero status, diagnostics on stderr. Legacy `preview` and `video` remain explicit standalone previews.

Settings adapter adds `.state.screensaver` with owner snapshot and operations `configure screensaver ID MODE --json` and `preview screensaver ID --json`. Its existing schemaVersion1 envelope is retained. Preview acknowledgment is exposed as `.result.screensaverPreview`; a preference Apply result is determined from readback.

### Task 1: Catalog, preferences and owner read/configure commands

**Files:** Create `branding/screensavers/catalog.json`, `tools/screensaver/__init__.py`, `tools/screensaver/catalog.py`, `tools/screensaver/preferences.py`, `tools/screensaver/cli.py`, `tests/screensaver-catalog.test.py`, `tests/screensaver-catalog.test.sh`; modify `scripts/aranea-screensaver` dispatch without changing legacy branches.

**Produces:** `load_catalog(repo_root)` returns normalized scene objects/projections; `read_preferences(config_home)` returns version1 `{selectedId,mode}` or validation error; `configure_preferences(config_home,id,mode,catalog)` atomically updates under a stable adjacent flock; `choose_scene(catalog,prefs,last_id,rng)` returns one available scene. `read_last_scene`/`write_last_scene` use Aranea state storage and atomic writes. API may use dataclasses internally; report exact signatures for later tasks.

- [ ] Write failing real-filesystem tests. Cases: default reads create nothing; exact three entries; missing Chromium/mpv disables only relevant entry; invalid IDs/path traversal/symlink escape/unsupported renderer or version rejected; malformed config is retained; invalid mutations leave bytes unchanged; concurrent configure produces a complete allowed value; shuffle excludes stock, avoids last when two choices and handles one/zero choices.
```python
prefs = read_preferences(config_home)
assert prefs == {"version": 1, "selectedId": "silk-journey", "mode": "single"}
assert not config_home.exists()
assert choose_scene(catalog, {"selectedId": "silk-journey", "mode": "shuffle"}, "silk-journey", rng).id == "silk-chamber"
```
- [ ] Run `tests/run screensaver-catalog` and record the actual missing-feature failure before implementation.
- [ ] Implement catalog sources: web root `branding/3d`, entry `live/index.html`, allowed `live/` and `aranea-spider.glb`; video asset `branding/3d/silk-chamber.mp4`; thumbnails `branding/3d/live/preview.png` and `branding/3d/silk-chamber.png`; stock thumbnail null with terminal-text treatment in UI. Labels/descriptions are bounded plain text; IDs match `^[a-z][a-z0-9-]{0,63}$`.
- [ ] Store `~/.config/aranea/screensaver.json` as version1 object; respect XDG locations. Single mode requires available selected scene; shuffle requires a known remembered ID and a nonempty available Aranea pool. Only explicit configure creates/writes config. No runtime spawning in read routes.
- [ ] Wire only list/status/configure into Bash CLI via `exec python3 "$repo_root/tools/screensaver/cli.py" ...`; keep copied-launcher legacy tests working. Runtime fields are inactive until Task3; integration fields are unavailable until Task4, with actual timing read from valid shell config when present.
- [ ] Run new tests plus `tests/run spider-preview spider-runtime settings`; run affected format/lint/docs/validate. Commit `feat(screensaver): add scene catalog and saved selection`.

### Task 2: Shared local asset server and fixed renderer adapters

**Files:** Create `tools/screensaver/http_server.py`, `tools/screensaver/renderers.py`, `tests/screensaver-renderers.test.py`, `tests/screensaver-renderers.test.sh`; modify `tools/spider/preview.py`, `branding/3d/live/dismiss.js`, `branding/3d/live/scene.mjs`, relevant `tests/js/spider-live-input.test.mjs` and legacy server tests.

**Consumes:** Task1 normalized scenes with validated root/entry/publicPaths/asset.
**Produces:** context-managed `SceneServer(scene, token, screen_ids)` with `.url(screen_id)`, `.drain_events()` and shutdown; events `{kind:"ready"|"dismiss"|"failed",screenId:...,message:...}`. Fixed `launch_web(url,profile_dir,app_id)`, `launch_video(asset,ipc_path,app_id,lua_path)` return owned Popen records. `terminate_group` kills only the record's owned session/group, including descendants after leader exit. `video_ready` reads bounded mpv JSON IPC. Use constructor dependencies for fake processes, not persisted executable commands.

- [ ] Add failing HTTP and real-child tests: valid assets served; traversal, encoded traversal, symlink escape, oversized requests/assets, bad token/unknown screen rejected; request body bounded; exactly one ready event per screen; dismissal available even on WebGL failure; server socket closes; stubborn child/descendant cleanup; exact argv has isolated profile, no extension/sync/network player config and correct app ID. Supervised web sessions use Chromium kiosk mode for exact Wayland identity; standalone legacy preview retains app mode.
```python
with SceneServer(scene, "token", ["DP-1"]) as server:
    post(server, "/__ready", token="wrong", body={"screenId":"DP-1"}, expected=403)
    post(server, "/__ready", token="token", body={"screenId":"DP-1"}, expected=204)
    assert server.drain_events()[0]["kind"] == "ready"
```
- [ ] Run new tests red before changing production files.
- [ ] Extract old preview HTTP behavior into shared server, preserving `/live/` relative imports and legacy URL/token/serve-only semantics. Serve only catalog-approved paths inside validated branding root; cap individual asset at32MiB and event body at8KiB. No directory listings. Readiness must reflect first rendered frame, not merely page load.
- [ ] Extend browser-side independent controls to send token-authenticated ready/failure/dismiss events. Keep frame cap30fps and pixel cap2.1million. Ready observer sends once; event text remains bounded/local. Keep legacy input behavior and existing fallback error display.
- [ ] Implement mpv fixed flags and Lua input via the existing `branding/3d/preview.lua`; add an owned IPC socket for readiness. Do not change animation/model assets.
- [ ] Run new server/renderer tests, legacy spider tests and JS input/gait/journey suites; format/lint/docs/validate. Commit `feat(screensaver): add supervised renderer protocol`.

### Task 3: Monitor-aware supervised sessions and control commands

**Files:** Create `tools/screensaver/hyprland.py`, `tools/screensaver/session.py`, `tests/screensaver-session.test.py`, `tests/screensaver-session.test.sh`; extend `tools/screensaver/cli.py`, `scripts/aranea-screensaver`, test guard registrations only for new effect boundaries if needed.

**Consumes:** Task1 catalog/preferences/shuffle and Task2 SceneServer/renderer functions.
**Produces:** `start_session(scene_id=None, preview=False, force=False)` acquires one stable user runtime lock; `preview-scene` detaches the supervised process with bounded acceptance handshake; `session_status` reads a versioned owned state/control socket; `stop_session` signals only the owned session. Normal `start` is blocking until its owned session ends. Stock scene delegates to fixed packaged launcher and keeps packaged lifecycle.

- [ ] Add failing process-backed supervisor tests with fake Hyprland/lock I/O and actual fake renderer children. Test two monitors choose one scene, shared dismissal, first-window recognition deadline, ready timeout, duplicate starts, lock-before-start, lock during run, inaccessible lock state, removed monitor, individual child exit/failure, SIGTERM, orphan descendant cleanup, socket/profile/server cleanup and focus/workspace restoration. Assert no host guard escapes.
```python
session = start_fixture(monitors=["DP-1", "HDMI-A-1"], mode="shuffle")
assert len(session.windows) == 2
assert len({w.scene_id for w in session.windows}) == 1
session.dismiss("DP-1")
assert session.wait_closed(timeout=5)
assert session.children_alive() == []
assert session.restored_focus == session.initial_focus
```
- [ ] Run `tests/run screensaver-session` red.
- [ ] Implement bounded argv-only Hyprland monitor/client/event adapter. Record monitor, active and special workspaces. Subscribe to window events before spawning. Place sequentially and verify each owned window/class before advancing focus, following packaged special-workspace behavior. Use fixed allowlisted typed Lua calls for the current Hyprland API, with every data value encoded as a Lua string literal and passed through separate `hyprctl` argv; never execute catalog text or arbitrary Lua/shell input. First mapping must fit the actual upstream3second idle launch grace; use a2.5second first-map deadline and a20second renderer-ready deadline.
- [ ] Supervisor owns one selection, server, profiles, child groups, socket and runtime state. One-second bounded monitor/lock readback complements compositor events and packaged lock's class-based process kill. Reject unknown/unreadable lock state for start; terminate if lock cannot be safely observed during run. Both automatic and forced/manual starts refuse a locked session. Preserve screensaver-off except manual force/Preview.
- [ ] On a removed monitor, remove its child from the expected set before termination; remaining surfaces continue. Any other child close/input dismisses all. Restore original focus/workspaces only through saved/validated monitor identities, preserving preexisting special workspaces. Cleanup must not kill an unrelated browser or rewrite global desktop state.
- [ ] Choose/store last automatic scene only after all remaining expected renderers are ready. Preview neither writes preferences nor updates automatic shuffle history. Preflight stock fallback occurs before mapping; mapped failures end session instead of starting a fresh untracked saver.
- [ ] Expose start/stop/preview-scene/status owner routes. For JSON Preview, acknowledge acceptance without keeping Settings pending for session lifetime; running/ready/error state is independently readable. Busy/invalid/unavailable/locked errors are explicit and bounded. Preserve standalone legacy preview/video.
- [ ] Run new session tests, catalog/renderer suites, legacy spider/guard contracts and quality gates. Commit `feat(screensaver): supervise idle sessions across monitors`.

### Timing controls (user scope addition)

The user requested editable screensaver and lock times on the picker and approved enabling automatic idle behavior at installation. Both deadlines count from last activity. Add two duration fields with a Disabled option and independent Apply timing/Discard draft; preserve current values until explicit Apply. UI minutes1..1440 or Disabled; preserve exact existing seconds without rounding on read. When both deadlines are enabled, require lock later than screensaver. Backend strict integer seconds0..86400, compatible with unchanged preexisting exact seconds, including sub-minute values. No Preview or scene Apply timer side effects.

Task4 adds owner `configure-idle SCREENSAVER_SECONDS LOCK_SECONDS --json` and Settings `configure screensaver-timing SCREENSAVER_SECONDS LOCK_SECONDS --json`. Serialize adjacent-lock/same-directory atomic mutation of only idle.screensaver/idle.lock, preserve unrelated shell data and symlink targets, reject malformed existing documents. Missing config uses trusted packaged defaults on explicit save. Request bounded shell reloadConfig and distinguish persisted from applied; failed application is reported honestly. No restart or Stay awake toggle during timing Apply. Reads create no state.

Task5 adds local timing draft, errors, Apply/Discard, disabled support and explanatory labels; capture snapshot/reset/restore includes draft fields. Task4 tests real persistence, validation, byte preservation, symlinks, concurrency, missing/corrupt config and reload failure. Task5 tests production controls, draft/readback/error/discard and Preview/showcase isolation. Root installation enables idle via omarchy-shell idle enable; retains900/1200.

Task3 also adds actual upstream Idle Service QML lifecycle fixture (not a reimplemented model), with fake external effects and only native IdleMonitor boundary replacement if needed. Verify startup activity preserves pending lock, early last-window close cancels and lock timeout dispatches fake lock. See task-3-idle-contract.md.

### Task 4: Managed automatic activation and Settings backend

**Files:** Create `tools/screensaver/idle.py`, `integrations/session/bin/omarchy-launch-screensaver`, `tests/screensaver-integration.test.sh`, `tests/screensaver-settings.test.sh`; modify `scripts/install-integration`, `scripts/lib/ownership.sh` only if existing integration-root ownership needs adjustment, `scripts/aranea-settings`, `tools/screensaver/cli.py`, `integrations/session/README.md`, `tests/install.test.sh`/`tests/uninstall.test.sh`/existing integration tests as necessary.

**Consumes:** Task3 start/preview/status operations and stable installed theme layout.
**Produces:** user managed shim in `xdg_bin_home()/omarchy-launch-screensaver`; `.state.screensaver` in Settings readback; typed configure/preview adapter operations matching shared schema.

- [ ] Add failing sandbox contracts: active Aranea dispatches exactly stable installed owner+start+[force]; other theme/classic/unavailable preflight uses fixed `$OMARCHY_PATH/bin/omarchy-launch-screensaver` or packaged `/usr/bin` equivalent without recursion; off and locked behavior preserved; altered shim/user files respected; ownership backup/restoration; same-login-shell resolution diagnostics. Test actual shell adapter JSON envelopes and readback without creating state on read.
```bash
"$settings" configure screensaver silk-journey single --json >"$TMPDIR/result.json"
jq -e '.ok and .state.screensaver.selectedId=="silk-journey" and .state.screensaver.mode=="single"' "$TMPDIR/result.json"
"$settings" preview screensaver silk-journey --json >"$TMPDIR/preview.json"
jq -e '.ok and .result.screensaverPreview.accepted==true' "$TMPDIR/preview.json"
```
- [ ] Run new contracts red before implementation.
- [ ] Install shim through existing session integration/ownership ledger, using source under `integrations/` so normal ownership recognition applies. Read authoritative current theme name (Omarchy's theme.name) and stable installed root; no dependence on development checkout. Preserve no-arg/force stock compatibility. Do not change PATH: calculate and report login-shell reachability; unavailable reachability prevents claiming automatic activation.
- [ ] Extend owner integration/timing status and `scripts/aranea-settings` operation validation/readback. Validate ID/mode against catalog; preserve independent partial-state behavior. Missing renderer is a per-scene unavailable state, not a failure of unrelated Settings. Preview response is acceptance, not saved selection or guaranteed rendered readiness.
- [ ] Ensure deactivate/uninstall removes only owned shim and restores predecessor; inactive theme always stock. Verify no installed wrapper requires source checkout path.
- [ ] Run new contracts, install/uninstall/hooks/integration and existing settings/spider focused groups; format/lint/docs/validate. Commit `feat(screensaver): integrate automatic activation and settings owner`.

### Task 5: Picker page, typed menu/search routes and capture-safe state

**Files:** Create `plugins/araneadev.settings/ScreensaversPage.qml`, `plugins/araneadev.settings/i18n/en.json` (extend if exists), `tests/qml/settings-screensavers.qml`, focused JS policy tests; modify `SettingsLogic.js`, `SettingsController.qml`, `SettingsNavigation.qml`, `SettingsSurface.qml`, `Settings.qml`, `manifest.json` in settings plugin; `DesktopSearchTargets.js`, canonical settings-target allowlists in menu/search and regenerate any affected facade through generator; `tests/qml/fixtures/settings-preview.qml` inert fixture and `tools/render-settings-preview` allowlist if needed; relevant Settings/menu/search JS/QML tests; architecture/user docs.

**Consumes:** Task4 `.state.screensaver` and configure/preview operations. Do not add a second preference store or derive executable commands from labels.
**Produces:** `screensavers` destination, explicit local draft `{selectedId,mode}`, thumbnail preview/Apply, authoritative current summary and editable timing.

- [ ] Write failing real-component QML tests for initial owner state, selecting without mutation, Preview without save, Apply/readback, failed Apply retains draft, shuffle mode, scene click returns to single mode, unavailable entry, current mode summary, keyboard/pointer gates, narrow/short layout, plain-text labels and capture read-only behavior. JS tests assert exact allowlisted argv and unknown ID/mode/section rejection.
```javascript
assert.deepEqual(Logic.command("/adapter", "configure screensaver", ["silk-journey", "single"], state), ["/adapter", "configure", "screensaver", "silk-journey", "single", "--json"])
assert.equal(Logic.command("/adapter", "preview screensaver", ["unknown"], state), null)
```
- [ ] Run focused JS/QML tests red.
- [ ] Build dedicated page with existing Settings primitives, thumbnail aspect ratio, responsive gallery, current marker, independent editable timing controls with Apply/Discard, Preview and explicit Apply/Discard. Use English Commons.Translations; existing fields remain PlainText. Selecting a tile sets single mode; shuffle clears tile highlight while retaining remembered single choice. Preview applies chosen tile only and cannot alter persisted mode/selection.
- [ ] Extend persistent Settings controller typed result keys/readback and preview acceptance handling; process lifetime must not depend on page visibility. Do not call Preview from rendering/state sync. Show runtime startup errors from owner state; no promise of readiness from an accepted launch.
- [ ] Add navigation/menu/search route to same page, preserve all current routes and bar layout. Regenerate canonical facades; do not hand-edit generated regions.
- [ ] Extend capture snapshot/reset/restore for local screensaver draft/mode/gallery state, `captureBegin` allowlist and inert fixture. A showcase never starts a renderer or mutates selection. Keep new page out of declared full capture manifest until Task6 provides its real PNG.
- [ ] Run new+existing Settings/menu/search QML/JS suites, adapter contracts and format/lint/docs/validate/qml. Commit `feat(settings): add visual screensaver picker`.

### Task 6: Installed behavior, complete capture coverage and final integration

**Root operational prerequisite:** Tasks1–5 implemented and independently reviewed. Run the complete repository gate on that core tree and resolve failures before installing. Local prior baseline is v2.37.0 with CI success; do not repeatedly rerun unaffected long shell groups during task implementation.

**Files:** Modify `scripts/capture-screenshots`, `tests/screenshot-coverage.test.sh`, `tests/capture-batch.test.sh` and capture/showcase guards if their exact lists change; add `screenshots/settings-screensavers.png`; refresh `screenshots/settings.png`, `screenshots/settings-scaling.png`, `screenshots/settings-schedule.png`, `screenshots/hero-showcase.gif` and README reference; update `branding/3d/README.md`, session/features/configuration guides to describe actual installed functionality.

**Interfaces:** Settings capture section `screensavers` from Task5; new surface `settings-screensavers`; existing shell capture-session ownership/traps remain the only capture authority. No new application runtime behavior belongs here.

- [ ] Root verifies core tree via `tools/check` (full non-fast). Record actual exit status, QML skip assertions and counts; fix real regressions, do not suppress failures.
- [ ] Root reads approved installer/deployer source, snapshots relevant user state and installs source from this managed worktree using existing safe installer/owned integration path. Keep installed theme independent of worktree. Enable managed session integration, persist Silk Journey/single for initial automatic selection and preserve900/1200 timings. Installing this approved feature needs no further user confirmation; sandbox escalation is still required for protected paths. Stop existing owned preview before replacing code.
- [ ] Root confirms installed runtime/UI files match source hashes, both configured scene readback and actual login launcher resolution, idle status, approved automatic enablement and preserved current timers. Use native multi-monitor preview on live compositor to verify class/placement, focus restore, ordinary input dismissal and no orphan processes/profiles/server. Do not force-lock or change the user's idle deadlines. Use isolated idle/lock fixtures for deadline behavior.
- [ ] Add failing capture contract for new declared surface/hero entry and inert section. Add exact `settings-screensavers` surface after `settings-schedule`; total47 surfaces, hero39 frames. Preserve real notification/clipboard backups, fixture read-only guards, named-key input only and background set once per batch.
```bash
scripts/capture-screenshots --surface settings-screensavers --output screenshots
# Full capture tests use fake effects; real images are from installed production UI.
tests/run capture-batch capture-showcase screenshot-coverage
```
- [ ] Capture actual installed production Settings pages using existing safe script; all backgrounds Silken Vault. Regenerate hero with the added page in declared order and refreshed stills. Never mask old shots with fabricated images. If capture fails, retain prior assets and fix readiness/cleanup before retrying.
- [ ] Run affected capture/session/showcase/settings/screenshot coverage contracts, full relevant quality/QML gates and meaningful JS checks after final code edits. An unchanged runtime does not require repeating its already passing long groups for binary/docs-only updates; verify all final source changes have applicable passing evidence. Commit `docs(screensaver): capture picker and document installed behavior`.
- [ ] Fresh task review plus broad final review of entire feature. Resolve integration findings and reinstall if runtime/UI changes after native QA. If only capture script/assets changed after core install, synchronize those owned theme files through existing deployment rather than claiming they match while stale.
- [ ] Root final verifies stable installed launcher/assets/UI, Silk Journey single selection, unchanged900/1200 timing, no lingering QA session, and clean committed feature branch. Retain managed worktree/branch; do not publish another release. Archive proof/reviews before cleaning only this plan's scratch workspace.

## Final review and completion evidence

Full source/asset manifest; per-task commits and independent spec/quality review; runtime/idle lifecycle fixtures; native actual window identity/monitor placement/dismissal/focus; installed-file hashes and login command resolution; complete gate results plus affected final capture gate;47still assets/39hero frames. Report any unverified hardware/monitor condition honestly instead of claiming it passed.
