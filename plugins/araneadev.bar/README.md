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

- `Bar.qml` owns the bar window and host-facing properties.
- `BarSections.qml` composes the configured sections.
- `BarModuleSlot.qml` loads one configured module.
- `BarDragOverlay.qml` owns drag and transparency gestures.
- `CenterGestureArea.qml` handles center-bar interactions.
- `CustomCommandModule.qml` renders user-defined command modules.
- `TooltipBubble.qml` renders the bar tooltip surface.
- `BarModel.js` owns pure layout, color, and configuration normalization.

## Configuration

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

## Validation

Bar behavior is covered by `tests/qml/bar-components.qml`,
`tests/qml/bar-surface-components.qml`, `tests/qml/bar.qml`, and the bar
model tests under `tests/js/`. Run:

```bash
tests/qml-behaviour.test.sh bar-components bar-surface-components
tests/run plugin-state
```
