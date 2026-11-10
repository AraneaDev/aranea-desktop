# Task 8a implementation report

## Result

Added native notification keyboard acceptance and strict Arch CI wiring. Production notification APIs, action policy, windows, keyboard handlers, timers, inbox and center are unchanged. `.omarchy-version`, reviewed Quickshell package/checksum, Qt requirement and archive pin are unchanged.

Status: DONE_WITH_CONCERNS. Automatic center focus is observed before any pointer input, through its unchanged Exclusive-prime policy. Sway subsequently drops focus at the OnDemand transition. Sustained automatic OnDemand retention on Hyprland remains platform acceptance; this private Sway test cannot prove it. The controller explicitly accepted this boundary with the concern retained.

## Coverage

- Two actual headless Wayland outputs instantiate actual production Toasts PanelWindows.
- The public `notifications keyboard` IPC enters keyboard mode; exactly one native output requests Exclusive focus and both copies pause expiry.
- Real wtype Down/Return invokes sender 81's second action once; real numeric 1 invokes sender 82's first action once. Assertions compare full literal invocation histories, detecting duplication across outputs.
- Real Escape releases native ownership and the production countdown advances again.
- Removal of the selected notification before the next numeric key invokes no replacement action. The replacement remains live and timers resume.
- An ordinary FloatingWindow TextInput receives actual typing initially and after Escape, removal, center close, and toast destruction.
- The real notification Panel opens while toast keyboard mode is active. A read-only active-focus observer latches automatic compositor focus before pointer input; the actual service releases toast ownership and timers, preserving the inbox and live popup count.
- Sway OnDemand receives an explicit private virtual-pointer click before real Down/Escape verify the production center cursor and close behavior. No native window, focus binding, prime interval or production key handler is replaced.
- Actual private Sway `output HEADLESS-2 unplug` releases ownership without transferring it; the remaining real output can acquire ownership, then dynamic Toasts destruction releases it again.
- Runtime errors and failed QML assertions fail the runner.

## TDD and debugging evidence

This is an acceptance-test-only change, with no production implementation added. Mutation testing demonstrates the new test detects broken native dispatch.

RED command: a disposable `tests/.native-notifications-mutation.test.sh` copied the new runner and added one staging-only substitution:

```sh
sed -i 's/event.accepted = toasts.root.keyboardPressed(event.key, event.text)/event.accepted = true/' "$stage/cfg/plugins/araneadev.notifications/Toasts.qml"
ARANEA_QML_SHELL_DIR=/tmp/aranea-omarchy-4.5.0/shell ARANEA_CHECK_REQUIRE_ALL=1 bash tests/.native-notifications-mutation.test.sh
```

Observed exit 1 with:

```text
QMLTEST FAIL native key invokes exactly the selected action once: got [], expected ["81-two"]
QMLTEST FAIL action releases toast native ownership
QMLTEST FAIL action resumes expiry
```

The test mutation and temporary runner were removed; production source was never mutated. This severs precisely the production Keys handler, while leaving real surfaces, focus requests and input injection intact.

Initial debugging also caught a meaningful harness false positive: `command -v wtype` resolved `tests/guard-bin/wtype`, a successful logging stub. It produced no native input. The final runner resolves the real executable with `type -ap`, excluding guard-bin like the existing Quickshell resolver, and includes initial ordinary typing as a positive control.

The dedicated preflight test exercises the complete runner with a controlled PATH containing guard-only wtype. Ordinary mode explicitly skips; strict mode exits nonzero. With prerequisites present but a failed compositor backend, strict mode exits nonzero with `FAIL: private compositor did not expose a Wayland socket`, never a skip. No real compositor starts in these probes.

A persistent idle wtype process retains keyboard capability on the otherwise device-free private seat. Without it, repeated temporary virtual keyboard removal caused Qt unexpected `wl_keyboard.leave` warnings. The idle keyboard is test owned and is terminated during cleanup.

The native center handoff was traced with temporary focus observers: the unchanged frame reported active focus while `focusPrimed=false`, then lost focus with `focusPrimed=true`. A subsequent private pointer click into the real card restored focus; actual Down changed its cursor and actual Escape closed it. The production and target KeyboardPanel comments explicitly describe Hyprland-specific OnDemand retention. No production policy change or Sway-only focus adapter was made. The final observer latches any actual automatic focus before the pointer step, rather than testing the contemporaneous QML prime flag: Wayland delivery can arrive after the local 75ms timer changes that flag.

## Verification

All commands used the exact target shell at `/tmp/aranea-omarchy-4.5.0/shell` (target commit `ac2690cd7be4f47e4a255f5e2e78d904d436b068`).

```sh
ARANEA_QML_SHELL_DIR=/tmp/aranea-omarchy-4.5.0/shell ARANEA_CHECK_REQUIRE_ALL=1 tests/run native-notifications native-notifications-preflight qml-host
```

Result: 3 passed in 10.77s, no skips. Native QML completion: `QMLTEST DONE 0`. A final standalone repeat after observer cleanup also passed all 46 native assertions; only the three expected host warnings remained.

```sh
ARANEA_QML_SHELL_DIR=/tmp/aranea-omarchy-4.5.0/shell ARANEA_CHECK_REQUIRE_ALL=1 tests/qml-behaviour.test.sh notification-toasts notification-center-keyboard
```

Result: notification-toasts 21 checks; notification-center-keyboard 26 checks; both pass.

```sh
shellcheck -x tests/native-notifications.test.sh tests/native-notifications-preflight.test.sh
shfmt -d tests/native-notifications.test.sh tests/native-notifications-preflight.test.sh
tools/check-docs tests/native-notifications.test.sh tests/native-notifications-preflight.test.sh tests/qml/fixtures/native/notifications.qml
node --test tests/js/facade-generator.test.js
node_modules/.bin/prettier --check .github/workflows/ci.yml
actionlint .github/workflows/ci.yml
git diff --check
```

Result: all pass. `tools/check --staged --only format,lint,docs,validate` also reports all four stages ok. QML formatted using the installed Qt 6.12 qmlformat. The full branch gate belongs to the controller after Task 8b.

## Isolation and teardown

The runner sources sandbox.sh and qml-host.sh. HOME/XDG paths are private; inherited compositor/session-bus addresses are cleared. The native compositor has a mode-0700 temporary runtime and uses headless/pixman/no-libinput devices under `setpriv --no-new-privs`. Qt uses software-backed OpenGL RHI and a private `dbus-run-session`. wtype connects only after the test's Wayland socket is found and exported. All qs IPC addresses the unique temporary config and runtime. swaymsg always receives the explicit private socket.

Service uses `serverEnabled:false` and test-owned sender action callbacks. Only external Hyprland records are replaced in copied Service/Toasts imports. Shared production SpringPanel and native Wayland windows are unchanged. No actual notification server, clipboard, physical seat, uinput, ydotool, lock, suspend or installation is involved.

The private-pointer helper verifies the runtime pathname, owner, permissions, marker and socket before connecting. Cleanup terminates/waits only the recorded wtype PID and newly created qs/Sway process groups, then removes the native stage and sandbox. Both success and failure paths use this cleanup.

Remaining harmless host diagnostics are Quickshell module-name warnings for dotted plugin directories and the expected missing Hyprland signature from upstream modules. No TypeError, ReferenceError, binding loop, assignment error, output-loss error or teardown error occurs in the passing flow.

## Files and self-review

- `tests/native-notifications.test.sh`: focused real-native runner, strict preflight, safe setup/teardown and IPC/input sequence.
- `tests/qml/fixtures/native/notifications.qml`: production Service/Panel/Toasts fixture, test sender boundary and read-only state assertions.
- `tests/native-notifications-preflight.test.sh`: guard-only wtype and failed-backend strict refusal checks.
- `.github/workflows/ci.yml`: adds wtype to the existing pinned package set and native-notifications to the strict native acceptance list.
- This report.

Self-review confirmed production files and `.omarchy-version` are untouched; CI pins are unchanged; no broad helper refactor or production test knob was added. Center handoff limitations are explicit in the runner and this report. No push, PR, merge, release or desktop installation was performed.
