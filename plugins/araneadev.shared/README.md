# Shared Aranea components

`araneadev.shared` is the reusable QML and JavaScript infrastructure module.
It is not a plugin surface. It provides stable visual, input, path, token, and
service contracts to the feature plugins.

## Components

- `DesignTokens`, `MotionState`, and `RuntimePaths` expose canonical runtime
  values and paths.
- `SurfaceCard`, `PanelHeader`, `BrandHeader`, `StatusRail`,
  `StatusTextPair`, `StatusRow`, `EmptyState`, and `InkText` provide
  presentational contracts.
- `FilamentSlider` is the Filament-style hairline slider/handle used by
  volume and level controls.
- `FilamentSwitch` is the Filament-style compact on/off switch.
- `NodeDeviceRow` is the Filament-style selectable device row with glyph,
  label, and detail slots.
- `DropdownHeader` is the Filament-style dropdown header with a glyph,
  title/caption pair, and a trailing slot.
- `InkText` aligns glyph ink rather than advance width.
- `KeyboardInputFrame` owns key forwarding and focus targeting.
- `KeyboardPanelFrame` adds the layer-shell panel contract around keyboard
  input.
- `OverlayChrome` provides common overlay placement and dismiss behavior.
- `ServiceRegistry.js` publishes isolated service slots for dependent plugins.

## Ownership rules

Shared components may own visual defaults, token usage, layout, and signals.
They must not own plugin lifecycle, cursor state, IPC, process management, or
feature-specific persistence. Plugin entry points remain composition roots and
provide dynamic state through explicit properties.

Register new QML types in `qmldir`, add direct behavior coverage under
`tests/qml/shared.qml`, and document the extraction boundary here.

## Validation

Run `tests/qml-behaviour.test.sh shared overlay-components polkit-components`
and `tests/qml/shared.qml` through the normal QML behavior suite.
