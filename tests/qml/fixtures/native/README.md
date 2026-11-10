# Native rendering acceptance

Run `ARANEA_QML_SHELL_DIR=/path/to/omarchy/shell tests/native-rendering.test.sh`.
Individual fixtures accept `bar`, `tray` or `picker`. CI sets
`ARANEA_CHECK_REQUIRE_ALL=1`, so missing dependencies fail rather than skip.

Each invocation creates a private headless Sway compositor, runtime directory,
D-Bus session, HOME and XDG state through the test sandbox. It disconnects
inherited desktop sockets and uses command guards. Cleanup stops only its own
process groups and removes its socket directory. The virtual pointer helper
rejects runtimes outside the owned, mode-0700 `/tmp/aranea-native.*/runtime`
fixture and has an eight-second deadline. It never uses uinput or a real seat.
IPC success alone is insufficient: the bar fixture checks an actual QML sink click.

Qt uses the real RHI/OpenGL backend with Mesa llvmpipe. `LIBGL_ALWAYS_SOFTWARE`
selects CPU OpenGL; it does not select Qt Quick's shaderless software backend.
The fixtures reject that backend and sample captured pixels from the actual
production tray and management view, including dark/light symbolic and color icons. The picker captures an empty and
a populated clipboard and verifies the separator pixels against its background.

The bar copy replaces only Hyprland records and adds read-only observers.
Sway always places Top layers below fullscreen, whereas the target Hyprland bug
lifts them above it; the disposable copy uses Overlay stacking to reproduce that
condition. Its production input mask, geometry, tooltip lifecycle and gesture
handlers remain unchanged. The tray replaces only external SNI item records.
No production files or host compositor configuration are changed by the runner.

The notification runner (`tests/native-notifications.test.sh`) uses actual native
windows and real key input to cover actions, focus handoff, toast timers and
output loss in the same private compositor. It asserts automatic center focus
before any pointer input during the unchanged Exclusive prime. It then explicitly
refocuses the center with the private pointer for subsequent OnDemand key dispatch
on Sway. This does not establish sustained automatic OnDemand focus retention on
actual Hyprland; the production focus policy is unchanged.
