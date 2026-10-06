// Header of the Aranea Bluetooth dropdown: the shared DropdownHeader with
// a power switch in its trailing slot. Pure view: plain inputs in,
// signals out. (glyph and caption come from DropdownHeader.) The switch
// pulses while a power change is in flight, and a click on it within
// 300 ms of the dropdown's layout shifting (pointerGate.layoutChangedAt)
// is ignored unless the pointer has really moved onto it since.
import QtQuick
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Aranea.DropdownHeader {
  id: header
  refined: true

  // Whether the adapter is powered on. Named "powered", not "enabled": the
  // latter shadows QQuickItem.enabled and would make the whole header stop
  // receiving events once the adapter is off.
  property bool powered: false
  // Whether a Bluetooth adapter is present at all; hides the switch without one.
  property bool hasAdapter: false
  // Whether a power change is in flight: the switch breathes until BlueZ
  // reports it.
  property bool busy: false
  // Whether the keyboard cursor is on the power switch.
  property bool hasCursor: false
  // The switch's tooltip, e.g. "Turn Bluetooth off".
  property string hint: ""
  // The switch's tooltip, exposed for tests.
  readonly property alias hintTip: tip
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from the
  // switch moving under a still pointer.
  property var pointerGate: null
  // When the gate last accepted a real pointer move onto the switch
  // (Date.now()), 0 for never.
  property real switchMovedAt: 0

  // Emitted when the power switch is toggled.
  signal toggleBluetooth
  // Emitted when the pointer enters the switch.
  signal entered

  // Whether a pointer click may toggle the switch (its clickGate): settled
  // since the dropdown's last layout shift, or moved onto since.
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      movedAt: header.switchMovedAt,
      layoutChangedAt: header.pointerGate ? Number(header.pointerGate.layoutChangedAt) || 0 : 0
    })
  }

  objectName: "bluetoothHeader"
  title: "Bluetooth"

  // Not anchored: the trailing slot sizes itself to this switch (its
  // childrenRect) and is centred already, so centring the switch on the
  // slot would make the slot's height depend on itself.
  Aranea.FilamentSwitch {
    objectName: "powerSwitch"
    visible: header.hasAdapter
    checked: header.powered
    busy: header.busy
    hasCursor: header.hasCursor
    clickGate: header
    onToggled: header.toggleBluetooth()
    HoverHandler {
      id: switchHover
      onHoveredChanged: if (hovered && !header.pointerGate)
        header.entered()
      onPointChanged: if (header.pointerGate && switchHover.hovered && header.pointerGate.moved(switchHover.parent, {
        x: switchHover.point.position.x,
        y: switchHover.point.position.y
      })) {
        header.switchMovedAt = Date.now()
        header.entered()
      }
    }
    PanelToolTip {
      id: tip
      fontFamily: Aranea.Typography.uiFamily
      visible: switchHover.hovered && header.hint !== ""
      text: header.hint
    }
  }
}
