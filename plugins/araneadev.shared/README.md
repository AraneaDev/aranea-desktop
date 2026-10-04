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
- `FilamentBar` is the read-only strand bar for a level (`value`, 0..1,
  clamped into `fraction`): a hairline track whose lit part runs mint to
  violet like the slider's, with no node and no pointer input. Health's
  memory and disk bars use it; the OSD's level bar will too. An optional
  `pace` (0..1, negative hides it, the default) draws a thin tick across
  the track, as the Agents limit windows' pace marker.
- `FilamentSwitch` is the Filament-style compact on/off switch. An optional
  `clickGate` (the `NodeDeviceRow` hosting it, or anything with
  `clickSettled()`) makes its pointer clicks settle like that row's, as
  the VPN dropdown's rows do.
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
  `DesignTokens.urgent` for "Couldn't connect"), and `nodeColor` recolours
  the lit node and its glow (Health tints a problem's node urgent or amber).
  A pointer click within `settleMs` (300 ms) of the row being created, or
  of its dropdown's layout shifting, is ignored unless the gate accepted a
  real move over it since, so neither a Repeater rebuild nor a section
  growing turns a click aimed at one row into a click on another. A
  dropdown reports layout shifts by declaring `layoutChangedAt` (a
  `Date.now()` stamp) on the gate it hands down; `ClickSettle.clickSettled`
  holds the rule.
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
  or only on a real pointer move when a `pointerGate` is set. A pill on a
  row a Repeater can rebuild takes the row as `clickGate` (VPN's "open app"
  chip), as `FilamentSwitch` does; without one, a pill with a gate settles
  its clicks after the dropdown's layout shifts on its own. `pressCanceled`
  fires when a press ends without a choice (released outside, canceled or
  refused by the settle), so a host can forget what it noted on `pressed`.
  Its label, like `DropdownHeader`'s title and caption, is plain text.
- `DropdownHeader` is the Filament-style dropdown header with a glyph
  (tinted by `glyphColor`), title/caption pair, and a trailing slot. An
  optional `markSource` (an image url, e.g. the Agents tool logo) replaces
  the glyph once it loads; empty or failing, the glyph shows as before.
- `CredentialPrompt` is the inline credential prompt (Network's passphrase,
  VPN's password and 2FA code, the Polkit password): an accent-to-violet
  frame around `fields` (each
  `{key, label, placeholder, secret, readOnly, optional, hidden, value, glyph}`)
  and a check-glyph connect button. Opening focuses the first editable
  field; Enter moves on and `submit`s from the last; Esc `cancel`s; typing
  emits `edited(key, text)`; the button emits `connectClicked`, settled
  through an optional `pointerGate`. `busy`/`failed` show `busyText` /
  `failedText` instead of the fields; with `inlineStatus` (Polkit) they show
  on the fields instead: busy pulses them read-only, failed turns them
  urgent with `failedText` as the placeholder. `connectShown: false` hides
  the button, `clearFields()` empties the fields, and keys other than
  Enter/Esc reach `unhandledKey(event)`. Its Repeater counts fields, so a
  host echoing typed values back never rebuilds a field.
- `LinkGraph` is the 60 s receive/send `Canvas` trace for a link's
  throughput, shared by the Network and VPN dropdowns. It draws
  `GraphLogic.graphPoints` and a bare baseline before there are samples.
  Health's CPU trace reuses it with `slots: 60` and `floor: 100`, no send
  line (`secondary: false`) and a soft mint fill under the line
  (`softFill: true`); both default to the network look.
- `InkText` aligns glyph ink rather than advance width.
- `KeyboardInputFrame` owns key forwarding and focus targeting, including a
  `deleteRequested` signal forwarded from the key catcher's "x" key, and a
  `blocked` alias to the key catcher's own `blocked` (an inline editor with
  focus short-circuits all key handling). Keys the catcher leaves unaccepted
  (Delete, for example) arrive as `unhandledKey(event)` while not blocked.
- `KeyboardPanelFrame` adds the layer-shell panel contract around keyboard
  input and forwards the same `deleteRequested` and `unhandledKey` signals
  and `blocked` alias.
- `OverlayChrome` provides common overlay placement and dismiss behavior.
- `ServiceRegistry.js` publishes isolated service slots for dependent plugins.
- `ClickSettle.js` is the shared click-settling rule (`clickSettled`): a
  click on a control that was just created, or that a layout shift just
  moved under a still pointer, waits for the pointer to really move onto it
  or for 300 ms to pass. `NodeDeviceRow`, `ForgetButton`, `FilamentPill`,
  `CredentialPrompt` and Network's band switch use it.
- `CursorLogic.js` is the shared keyboard-cursor safety contract (moved from
  the Network plugin): a cursor follows the row key it was put on, never
  its position (`reselectIndex`, `followCursor`), a lost or evacuated key
  is refused rather than retargeted (`cursorConfirmed`), Enter/`x` only
  reveal a cursor the keyboard isn't showing before they act
  (`pressIntent`), a view's Repeater keeps its delegates across an
  unchanged refresh (`keepRows`), and a pointer action only lands on the
  row it names (`rowKeyMatches`). `araneadev.network`'s `Panel.qml` imports
  it directly (a real QML/JS import) for `keepRows`, `followCursor` and
  `rowKeyMatches`; `NetworkLogic.js`'s own `keyTargetConfirmed`/
  `pressOutcome` instead get a generated copy of `cursorConfirmed`/
  `pressIntent` via `tools/js-facade-generator.mjs` (see
  docs/development.md's "JavaScript facades"), since a plain `.js` logic
  file can't import another `.js` file in a way both QML and Node can
  load. Either way there is exactly one hand-written implementation, here.
- `GraphLogic.js` is the shared rolling-sample and plot-point math behind
  `LinkGraph` (`pushSample`, `graphPoints`), also moved from the Network
  plugin. `Panel.qml` and `LinkGraph.qml` both import it directly.
- `NmcliTerse.js` holds `splitTerse`, the `nmcli -t` terse-output field
  splitter both `araneadev.network/NetworkLogic.js` and
  `araneadev.vpn/VpnLogic.js` need. Neither imports it (the same QML/Node
  constraint as `CursorLogic.js`'s inlined pair): both get a generated copy
  via `tools/js-facade-generator.mjs`.
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
