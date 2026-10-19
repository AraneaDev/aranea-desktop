# Aranea bar

`araneadev.bar` is the Aranea composition of the Omarchy status bar. Its
manifest exposes `Bar.qml` as the `bar` entry point and declares the plugin as
a clone of `omarchy.bar`.

## Responsibilities

- Compose the left, center, and right bar sections.
- Provide the Aranea token-backed bar surface and drag behavior.
- Load configured modules through the Omarchy bar contract.
- Keep module placement and visibility in `bar.layout` from
  `~/.config/omarchy/shell.json`.

The bar is a composition root. Shared visual contracts belong in
`../araneadev.shared/`; bar-specific layout and host integration stay here.

## Entry points and components

- `Bar.qml` owns the bar window, configured sections, and host-facing properties.
- `BarModuleSlot.qml` loads one configured module.
- `BarDragOverlay.qml` owns drag and transparency gestures.
- `CenterGestureArea.qml` handles center-bar interactions.
- `CustomCommandModule.qml` renders user-defined command modules.
- `TooltipBubble.qml` renders the bar tooltip surface.
- `BarModel.js` owns pure layout, color, and configuration normalization.

## Configuration

The everyday right-hand controls are Network, Audio, Battery/System,
Notifications and Agents. Network contains Wi-Fi, VPN and Bluetooth; Audio
contains output and microphone controls, with a capture-only microphone badge;
Battery/System contains Power, Display and Health. The app tray stays behind its
disclosure. A conditional Health shortcut appears only for open issues, or while
its issue panel remains open. Separate child controls remain available when their
owning panel is absent.

Connections uses a linked-node symbol for Network, VPN and Bluetooth. System
uses adjustment controls for Power, Display and Health, with a small battery
level cue and optional percentage. Tooltips name the contents of both groups.

The host supplies `barConfig`. The supported layout shape is:

```json
{
  "bar": {
    "position": "top",
    "transparent": false,
    "centerAnchor": "araneadev.clock",
    "layout": {
      "left": [{ "id": "araneadev.menu" }],
      "center": [],
      "right": [{ "id": "araneadev.notifications" }]
    }
  }
}
```

Use the host commands for user configuration. Do not hard-code module order
or user paths in QML. Plugin availability and per-section visibility are
separate concerns.

## Plugin code reloads

The bar's persistent companion service watches the user plugin directory and requests a native
Quickshell configuration reload when plugin files change. This refreshes QML and
JavaScript imports while keeping the shell process. It survives stock Omarchy temporarily unmounting the bar during a rescan.
The adapter ships with Aranea;
packaged Omarchy files are unchanged.

Reloads wait until Aranea's lock and polkit services are ready and idle. Only
boolean activity flags are shared. Git metadata and hidden staging files are
ignored. Separate preview/test shells do not start the watcher.

For an explicit reload, run `omarchy-shell aranea.reload reload`; it returns
`queued` or `deferred`. `omarchy-shell aranea.reload status` reports pending state.
The normal installer restarts the shell once when deploying updated plugin files,
which also activates this adapter on the first install.

## Validation

Bar behavior is covered by `tests/qml/bar-components.qml`,
`tests/qml/bar-surface-components.qml`, `tests/qml/bar.qml`, and the bar
model tests under `tests/js/`. Run:

```bash
tests/qml-behaviour.test.sh bar-components bar-surface-components
tests/run plugin-state
tests/plugin-reload.test.sh
tests/plugin-reload-host.test.sh
```
