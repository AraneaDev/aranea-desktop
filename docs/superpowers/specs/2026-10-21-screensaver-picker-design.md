# Automatic screensavers and picker , approved design

Date: 2026-10-21. Baseline: v2.37.0, master `071aa17`.

## Requested outcome

Install the animated spider as the automatic screensaver and add a visual picker that can accommodate future scenes. Reuse the approved spider animation. The approved design includes optional shuffle alongside single-scene selection.

## Approach

Use a small trusted scene catalog, one launch supervisor, and a page in the existing Settings application. Reuse Chromium for the live journey and mpv for the existing rendered loop. A new native Qt renderer would duplicate the approved scene and introduce a larger dependency/build surface. A launcher without a picker would leave scene selection and future additions unfinished.

## Picker and initial choices

Add Settings → Screensavers and a menu/search destination opening the same page. Match current Settings typography, spacing, thumbnail treatment, pointer gating and explicit Apply behavior; add no bar item.

Initial choices:

- **Silk Journey**: the live articulated spider, moving chamber and occasional cyberpunk kanji events. Default on first activation.
- **Silk Chamber**: the existing rendered video loop, a lightweight alternative.
- **Omarchy**: the packaged terminal screensaver.

Show the current choice, thumbnail gallery, Preview and Apply. Selecting a thumbnail is a local draft; Preview does not save it. Apply persists the validated selection and refreshes authoritative state. Missing dependencies/assets produce an unavailable entry and an actionable message.

Optional **Shuffle** chooses an available Aranea scene once per idle session, avoiding the previous scene when more than one is available. The packaged Omarchy choice remains a selectable fallback rather than joining shuffle. There is no playlist editor or mid-session scene switching in this version.

Display existing idle timing so the user knows when activation and locking occur. Preserve this machine's current 900-second screensaver and 1,200-second lock settings. Timer editing is outside this change.

## Catalog and persistence

A versioned catalog under branding defines stable scene IDs, names, thumbnail/asset references and one supported renderer kind. Adding a future scene of a supported kind means adding assets and a catalog entry, without changing the picker or idle integration.

Catalog renderer kinds map to fixed, locally implemented launch paths. Configuration never contains executable command strings. Validate IDs, file containment and required assets/dependencies. Unknown IDs are rejected on mutation and shown as unavailable on read.

Keep scene choice and single/shuffle mode in Aranea's user config. Keep the last randomly used ID and live-session lock in runtime/state storage. Use atomic preference writes and serialize concurrent mutations. Use the existing Settings backend/operation/result conventions, with persistent process ownership separate from presentation.

## Idle and launch integration

Keep Omarchy's idle service as the authority for timing, stay-awake, screensaver-off, wake and lock. It currently launches the bare `omarchy-launch-screensaver` command and tracks the exact `org.omarchy.screensaver` window class.

Install a user-owned, ledger-managed launcher shim that dispatches to Aranea only while the Aranea theme is active. Classic selection, inactive theme and unavailable custom runtime delegate to the explicitly resolved packaged launcher without recursive PATH lookup. Do not edit packaged Omarchy files or clone its idle state machine.

Verify command resolution using the same login-shell context used by Omarchy's idle service. This machine has a user-bin directory before the packaged commands. If another installation cannot resolve the managed shim first, report that automatic integration is unavailable rather than silently claiming activation; do not rewrite general PATH configuration.

Normal activation respects screensaver-off and an already locked session. Manual Preview may bypass screensaver-off but must not appear over the lock screen. Retain existing `preview` and `video` CLI compatibility while adding catalog/status/selection/start operations.

## Runtime lifecycle and monitors

Use one supervised session, with one selected scene shared across all active monitors. Launch a fullscreen surface on each monitor using Omarchy's screensaver window identity and special-workspace conventions. Preserve and restore the original focused monitor/workspace.

Mouse movement, click or ordinary key input dismisses the entire session after a short launch grace period. Closing one surface closes the others. Use authenticated local dismissal, isolated browser profiles, bounded asset serving and fixed local resources. Preserve the current frame/pixel caps.

The supervisor owns its children, temporary profiles and asset server. Dismissal, lock, termination, renderer failure and partial startup failure must clean up the entire owned session. Duplicate starts must not create another session. Track monitor removal and stop orphaned surfaces; a newly connected monitor is included on the next activation.

Check assets, dependencies, selection and session startup before opening surfaces. An automatic preflight failure before any custom window maps delegates to the packaged saver. Once a custom window has mapped, renderer or partial startup failure tears down the owned session and lets Omarchy end that idle cycle; do not start an untracked replacement after the last window closes. Require a bounded renderer-ready handshake and report failed startup instead of leaving an empty fullscreen window. A manual preview reports failure rather than silently previewing a different choice. Missing one scene does not prevent valid choices from being selected.

Omarchy must observe the custom surfaces so that starting the saver leaves its pending lock armed, while dismissing it before the lock deadline cancels that cycle exactly as the stock saver does. Lock activation must terminate the owned browser/video/server session promptly.

## Installation and removal

Integrate launcher ownership into the existing session integration and installer. Respect existing user-owned files and the managed-file backup/restore policy. Keep assets/runtime in the stable installed theme, independent of the development checkout. Theme switching falls back to stock behavior; uninstall removes only owned integration and restores replaced files.

After implementation passes review and checks, install the completed source on this machine and select Silk Journey for automatic activation. Keep existing idle and lock timing. Confirm the actual installed version/assets, launcher resolution, Settings readback and live window identity. Publishing another release is not part of this request.

## Verification

- Catalog and config validation, unavailable assets/dependencies, atomic saves and concurrent selection.
- Settings draft/Preview/Apply behavior, keyboard navigation, availability and error/readback handling.
- Fixed dispatch arguments, packaged fallback, ownership restoration, active-theme checks and login-shell resolution.
- Runtime single-instance behavior, shared multi-monitor dismissal, focus restoration, startup grace, renderer failures, signals and child/profile/server cleanup.
- Real Omarchy idle lifecycle contract with isolated fixtures: custom window recognition, pending lock preservation, early dismissal, and lock-driven teardown.
- Native preview checks on this machine: monitor placement, actual window class, keyboard/mouse dismissal and clean teardown. Preserve user timing and avoid disruptive forced locking.
- Relevant repository quality gates and full integration verification before installation. Use fresh review for lifecycle/lock integration and final behavior.

## Scope boundaries

This change delivers the runtime integration, picker and extensible catalog using existing visuals. New scenes, wallpaper coupling, arbitrary executable plugins, scene editing, custom lock-screen rendering and a native Qt renderer are separate future work.
