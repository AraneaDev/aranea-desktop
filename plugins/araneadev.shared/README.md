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
- `FilamentSwitch` is the Filament-style compact on/off switch. An optional
  `clickGate` (the `NodeDeviceRow` hosting it, or anything with
  `clickSettled()`) makes its pointer clicks settle like that row's, as
  Network's VPN rows do.
- `FilamentPulse` is the Filament-style hairline strand that lights up (a
  travelling light, or a static lit strand with motion disabled) while a
  scan is running: Bluetooth's device discovery now, Wi-Fi scans later.
- `NodeDeviceRow` is the Filament-style selectable device row with glyph,
  label, and detail slots, an optional busy (breathing marker) and signal
  (marker glow strength) state, and an optional trailing action slot flush
  with the row's right edge. An optional `pointerGate` (a stock
  `PointerMoveGate`, `qs.Ui`) filters synthetic hover churn from the row
  moving under a still pointer: with a gate set, `entered` fires only on a
  real pointer move, never on the row sliding underneath a stationary
  cursor. `detailColor` recolours the detail (the network VPN rows use
  `DesignTokens.urgent` for "Couldn't connect"). A pointer click within
  `settleMs` (300 ms) of the row being created is ignored unless the gate
  accepted a real move over it since, so a Repeater rebuild never turns a
  click aimed at one row into a click on another.
- `ForgetButton` is the soft red "forget" button a row puts in its trailing
  slot (Bluetooth devices, Network's Wi-Fi and Saved rows). It shows on a
  `forgettable` row while the row (`rowHovered`), the button or the
  keyboard cursor (`hasCursor`) is on it, and draws bright when the
  cursor's action is on it (`cursorAction`). It sizes to zero while
  hidden. It emits `clicked` (also `activate()`), `pointerEntered` (gated
  through `pointerGate`) and `pointerLeft` (ungated). Its `hovered` lets a
  host hide its own row tooltip. `tooltipText` is the button's tooltip, and
  clicks settle like `NodeDeviceRow`'s.
- `FilamentPill` is the Filament-style choice pill (the network dropdown's
  band and DNS rows): a thin muted border, or an accent border with a 2 px
  accent underline when `selected`; the keyboard cursor (`hasCursor`) draws
  the same mint outline as `NodeDeviceRow`, pointer hover never does. A
  `busy` pill breathes. It emits `clicked`, and `hoveredMoved` on entering,
  or only on a real pointer move when a `pointerGate` is set.
- `DropdownHeader` is the Filament-style dropdown header with a glyph,
  title/caption pair, and a trailing slot.
- `LinkGraph` is the 60 s receive/send `Canvas` trace for a link's
  throughput, shared by the Network and VPN dropdowns. It draws
  `GraphLogic.graphPoints` and a bare baseline before there are samples.
- `InkText` aligns glyph ink rather than advance width.
- `KeyboardInputFrame` owns key forwarding and focus targeting, including a
  `deleteRequested` signal forwarded from the key catcher's "x" key, and a
  `blocked` alias to the key catcher's own `blocked` (an inline editor with
  focus short-circuits all key handling).
- `KeyboardPanelFrame` adds the layer-shell panel contract around keyboard
  input and forwards the same `deleteRequested` signal and `blocked` alias.
- `OverlayChrome` provides common overlay placement and dismiss behavior.
- `ServiceRegistry.js` publishes isolated service slots for dependent plugins.
- `CursorLogic.js` is the shared keyboard-cursor safety contract (moved from
  the Network plugin): a cursor follows the row key it was put on, never
  its position (`reselectIndex`, `followCursor`), a lost or evacuated key
  is refused rather than retargeted (`cursorConfirmed`), Enter/`x` only
  reveal a cursor the keyboard isn't showing before they act
  (`pressIntent`), a view's Repeater keeps its delegates across an
  unchanged refresh (`keepRows`), and a pointer action only lands on the
  row it names (`rowKeyMatches`). Network and VPN both import it directly.
- `GraphLogic.js` is the shared rolling-sample and plot-point math behind
  `LinkGraph` (`pushSample`, `graphPoints`), also moved from the Network
  plugin.
- `VpnApps.js` parses `~/.config/aranea/vpn-apps.json` (own-app VPNs,
  both the bare-array and `{apps, profiles}` object forms), matches an
  interface name against a glob (`globMatch`), derives an own-app VPN's
  `connected`/`present`/`absent` state and matched interface
  (`appState`, `appInterface`), and formats the Network dropdown's VPN
  status line (`statusLine`). Used by `araneadev.vpn`; kept here (not in
  `araneadev.network`) so Network can show the status line without
  importing from another plugin.

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
