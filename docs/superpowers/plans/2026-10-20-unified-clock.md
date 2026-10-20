# Unified Clock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make time open a single Calendar/World Clock/Weather dropdown while preserving preferences and legacy entry points.

**Architecture:** Reuse Clock as the only window owner and embed the existing Weather/World Clock controllers using the established System/Network pattern. Reuse pure Dropdown views; migrate standalone inline settings into reversible nested clock settings. Trusted bar alias fallback preserves focused-monitor routing without broadening plugin capabilities.

**Tech Stack:** Qt 6.12 QML, Quickshell, ES5-compatible JavaScript, Bash, jq, existing test harnesses.

**Spec:** docs/superpowers/specs/2026-10-20-unified-clock-design.md

## Global Constraints

- Install published 2.34.0 before source implementation starts; design and planning may precede installation.
- Qt 6.12/QML V4: no Intl dependency; no new dependencies.
- One native frame, anchored to the actual time button, centerOnBar:false.
- Calendar settings flat; nested clock.weather and clock.worldClock; current settings merged on every write.
- No moduleWidgets/service facade permission expansion; standalone entry precedence.
- No packaged Omarchy edits, privileged policy/session actions, baseline growth or warning suppression.
- New files tracked before all-file check discovery. Tests exercise real production code behind only external boundaries.

### Task 1: Embeddable Weather and World Clock controllers

**Files:** plugins/araneadev.weather/Panel.qml; plugins/araneadev.worldclock/Panel.qml; tests/qml/clock-embedded-controllers.qml; tests/qml-behaviour.test.sh only if native boundary adaptation needs extension.

**Interfaces:** Produce embedded, embeddingHost, hostedDropdown, hostedFocusTarget, activeDropdown; activateEmbedded()/deactivateEmbedded(); navigateKeyboard(dx,dy), activateKeyboard(), textKeyboard(text), deleteKeyboard(), disarmPointer(). embeddingHost provides openSection(page), close(), persistSection(page,values), activePage and opened. Embedded views stay owned by Clock. Public open/close/toggle delegate when embedded; standalone behavior remains.

- [ ] Write a real-controller fixture with inert host and native boundary adapter. Before implementation, assertions that no standalone frames exist in embedded mode and public open targets the correct host page must fail for missing embedded API. Add a city-write test with host capture and literal expected saved cities.
- [ ] Run `ARANEA_CHECK_REQUIRE_ALL=1 tests/qml-behaviour.test.sh clock-embedded-controllers` and record intended RED output.
- [ ] Add embedding properties and lifecycle adapters. Drive inherited PanelController.open from active embedded lifecycle; gate embedded Weather startup/background refresh while preserving standalone behavior. Do not overwrite nested World Clock settings with hostWidget.settings. Wrap Weather standalone IPC in Loader active:!embedded; embedded legacy IPC belongs to Task2 Clock widget. Use a Loader active:!embedded around the standalone frame and refer to its loaded frame through a variant interface. Replace private dropdown/frame references with activeDropdown/hostedFocusTarget. Preserve existing fetch sharing, refresh/probe, edit cleanup and cancellation. Gate delayed focus on active open section. Delegate embedded world-clock writes to host persistSection.
- [ ] Add explicit page keyboard adapters by moving the current frame handler bodies into functions, with the standalone frame forwarding to them. Do not duplicate logic or change key behavior.
- [ ] Run new fixture and existing worldclock-panel/weather/clock production-host fixtures, format/lint/docs/strict QML on touched files. Record GREEN and self-review. Commit only this task's files after root review.

### Task 2: One Clock-owned popup with three tabs

**Files:** plugins/araneadev.clock/Panel.qml; plugins/araneadev.clock/BarWidget.qml; create plugins/araneadev.clock/ClockTabs.qml, plugins/araneadev.clock/ClockCompatIpc.qml and optional focused settings helper; tests/qml/unified-clock.qml; tests/qml-behaviour.test.sh; tests/js/clock-settings.test.js if pure settings helper is introduced.

**Interfaces:** Consume Task1 controller API. Produce activePage, activePageController, selectPage(page), openSection(page), toggleSection(page), persistSection(page,values). Clock widget forwards section methods and isSectionOpen(page); exposes weatherPanel/worldClockPanel aliases. Weather sees the clock's own entry ID for peer discovery. Migration provides settings.weather/settings.worldClock.

- [ ] Write a production Clock BarWidget default-loader fixture with only native window and command/network boundaries adapted. Assert actual loaded Clock panel, one frame, real anchor, Calendar default; selecting World Clock/Weather activates one controller and keeps only one owner/window. Assert city writes merge nested worldClock while preserving literal format/weekStartDay/weather keys, and calendar writes preserve nested sections.
- [ ] Run fixture to capture intended missing-tabs/section-method RED failures.
- [ ] Add three FilamentPill tabs, matching SystemTabs styling. Compose existing Dropdowns in the single screen-fitted frame; retain scrolling/reveal for long world city lists. Set centerOnBar:false. Load controllers with embedded:true, embeddingHost and nested settings as INITIAL Loader.setSource properties before their Component.onCompleted. Provide reactive bar/settings/hosted view/focus bindings and own-ID peer aliases. Start normal opens at Calendar; selectPage cancels unsubmitted edits/disarms pointers and restores focus only when still open.
- [ ] Route keyboard input to the active controller or existing calendar actions, including edit blocking. Clock widget/ClockCompatIpc owns embedded native Weather and Elsewhen handlers gated off whenever matching standalone IDs exist in public bar.layoutConfig. Weather edit selects its page before guarded focus; Elsewhen showcase finds an open own-clock peer. No permission expansion. Retain normal clock right/middle click format/timezone behavior and existing calendar IPC.
- [ ] Run fixture, existing clock civil-date/dropdown/production-host tests and Task1 fixture. Add two-monitor sharing and deferred-focus tests. Count cumulative native frame creation and external helper/network calls before first page selection to catch transient standalone construction. Install all inert command/network boundaries before real controllers load. Confirm no extra hidden frames and no cross-page polling after close. Record GREEN and root self-review.

### Task 3: Reversible consolidation and focused legacy routing

**Files:** create scripts/lib/clock-shell-config.jq; scripts/repair-shell-config; scripts/release-shell-config; plugins/araneadev.bar/Bar.qml; create tests/clock-shell-config.test.sh and tests/qml/clock-aliases.qml; update existing affected shell/QML fixture expectations without weakening assertions.

**Interfaces:** jq repair_clock($worldclock;$weather) and release_clock (module names may be adjusted together before integration). Consume Task2 widget openSection/toggleSection/isSectionOpen. Requested exact standalone widget wins; otherwise weather/worldclock aliases map to the focused clock. Own-ID facade remains unchanged. Root owns Clock widget and controllers; task must not edit those files without coordination.

- [ ] Write real JSON repair/release lifecycle tests using deployed plugin manifests. Hand-check expected nested cities and weather settings, removed standalone IDs and exact restored sections/positions, unrelated settings, original string shape, custom sections, user edits/additions, absent clock/plugin and symlink behavior. Run intended RED failures.
- [ ] Implement module projection/restoration after/before existing ID retargets. Preserve metadata on the owning clock entry and current nested preferences on release. Idempotent repair must not overwrite edits, duplicate entries or recreate user-removed controls.
- [ ] Write a trusted real-Bar alias fixture with two output identities and actual method contract. Assert focused clock section routing, matching-section isOpen semantics, hide only when matching section, existing standalone precedence and foreign moduleWidgets still denied. Run RED before modifying Bar.
- [ ] Implement narrow trusted Bar fallback only in summonBarWidget/hideBarWidget/isBarWidgetOpen, using findPanelWidget's existing screen selection. Coordinate legacy IPC handlers with Task2 so no duplicates are introduced. No facade permission changes.
- [ ] Run migration/new alias and existing shell-config/deploy/uninstall/consolidation/native widget tests, format/lint/docs/diffcheck. Record GREEN and self-review. Commit only task-owned files after review.

### Task 4: Integration, independent review, release and native verification

**Files:** plugin READMEs, manifest descriptions, README.md, docs/features.md; new files from Tasks1-3 must be tracked before checks.

- [ ] Independently inspect actual source and all changed default-loader paths; ensure no test-only concrete cast narrows a real loaded production host.
- [ ] Run `ARANEA_CHECK_REQUIRE_ALL=1 tools/check --only format,lint,docs,validate,qml --fast`, full QML fixtures and smoke; focused shell regressions and relevant JS tests. Fix failures from their causes; no broad suppressions.
- [ ] Review production-host/two-monitor/alias/migration evidence and obtain independent spec+quality review. Verify no unresolved important findings and no changes to live policy/session state.
- [ ] Commit/push, open a conventional feature PR with final-scope problem/behavior/validation. Require fresh exact-head CI, normal squash merge, green master release-please, reviewed generated release PR with fresh required checks, publication workflows/tag verification.
- [ ] Install clean pinned published tag with normal guard and waited hooks. Check deployed plugin bytes, profile, city migration and boot hooks; use safe native clock click/section shortcuts/screenshots to confirm one anchored popup and retained data, then close it. Report release URL/version and any material verification limits.

## Contract examples for task implementers

Task1's real-controller fixture must use the production controller after installing command/network stubs. The host capture is a boundary; assert the production controller delegates the correct section and saved data:

```qml
world.writeCities([{name: "London", zone: "Europe/London", home: true}])
t.equal(host.lastSection, "worldclock", "embedded writes target the world-clock section")
t.equal(host.lastValues.cities, [{name: "London", zone: "Europe/London", home: true}], "city edits reach their owning clock")
t.equal(nativeWindowsCreated, 0, "embedded construction never creates a standalone window")
```

Task2's pure merge operation (if factored into a helper) and actual production writer must preserve both pages and existing calendar settings. Use this independent literal contract:

```javascript
const initial = {format: "HH:mm", weekStartDay: 1,
  weather: {unit: "f"}, worldClock: {cities: [{name: "UTC", zone: "UTC"}]}}
const expected = {format: "HH:mm", weekStartDay: 1,
  weather: {unit: "f"}, worldClock: {cities: [{name: "London", zone: "Europe/London", home: true}]}}
// Invoke production persistSection("worldclock", {cities: ...}) through the real loaded widget.
// Compare the captured own-entry update to expected, and verify the input remains unchanged.
```

The host maps the page token explicitly rather than writing a wrong-case key:

```javascript
var key = page === "worldclock" ? "worldClock" : page === "weather" ? "weather" : ""
if (!key) return false
```

Task3's migration fixture starts with:

```json
{"bar":{"layout":{"center":[{"id":"araneadev.clock","format":"HH:mm"},{"id":"araneadev.worldclock","cities":[{"name":"UTC","zone":"UTC"}]},{"id":"araneadev.weather","unit":"f"}]}}}
```

After repair assert center has only the clock, its format is unchanged, `worldClock.cities` equals the literal UTC list and `weather.unit` is `f`. Edit the nested city to London through jq, release the config, and assert the restored Elsewhen entry contains London while the weather entry remains in its original position/unit. Run repair twice and compare complete JSON, then exercise the actual symlink path. Do not replace this lifecycle test with source-text assertions.

Task4 exact verification commands:

```sh
ARANEA_CHECK_REQUIRE_ALL=1 tools/check --only format,lint,docs,validate,qml --fast
ARANEA_CHECK_REQUIRE_ALL=1 tools/check --only qmltest --fast
ARANEA_CHECK_REQUIRE_ALL=1 tools/check --only smoke --fast
bash tests/clock-shell-config.test.sh
bash tests/shell-config.test.sh
bash tests/shell-deploy.test.sh
bash tests/uninstall.test.sh
git diff --check
```

Ruling: Elsewhen showcase remains display-only and returns `closed` unless the World Clock section is already open; it must not open a section just for a screenshot override. A direct closed-to-World-Clock open is a required regression for zero unrelated Calendar/Weather network calls.
