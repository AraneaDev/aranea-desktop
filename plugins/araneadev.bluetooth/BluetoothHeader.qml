// Header of the Aranea Bluetooth dropdown: the shared DropdownHeader with
// a power switch in its trailing slot. Pure view: plain inputs in,
// signals out. (glyph and caption come from DropdownHeader.)
import QtQuick
import qs.Ui
import "../araneadev.shared" as Aranea

Aranea.DropdownHeader {
  id: header

  // Whether the adapter is powered on. Named "powered", not "enabled": the
  // latter shadows QQuickItem.enabled and would make the whole header stop
  // receiving events once the adapter is off.
  property bool powered: false
  // Whether a Bluetooth adapter is present at all; hides the switch without one.
  property bool hasAdapter: false
  // Whether the keyboard cursor is on the power switch.
  property bool hasCursor: false
  // The switch's tooltip, e.g. "Turn Bluetooth off".
  property string hint: ""
  // The switch's tooltip, exposed for tests.
  readonly property alias hintTip: tip
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from the
  // switch moving under a still pointer.
  property var pointerGate: null

  // Emitted when the power switch is toggled.
  signal toggleBluetooth
  // Emitted when the pointer enters the switch.
  signal entered

  objectName: "bluetoothHeader"
  title: "Bluetooth"

  // Not anchored: the trailing slot sizes itself to this switch (its
  // childrenRect) and is centred already, so centring the switch on the
  // slot would make the slot's height depend on itself.
  Aranea.FilamentSwitch {
    visible: header.hasAdapter
    checked: header.powered
    hasCursor: header.hasCursor
    onToggled: header.toggleBluetooth()
    HoverHandler {
      id: switchHover
      onHoveredChanged: if (hovered && !header.pointerGate)
        header.entered()
      onPointChanged: if (header.pointerGate && switchHover.hovered && header.pointerGate.moved(switchHover.parent, {
        x: switchHover.point.position.x,
        y: switchHover.point.position.y
      }))
        header.entered()
    }
    PanelToolTip {
      id: tip
      visible: switchHover.hovered && header.hint !== ""
      text: header.hint
    }
  }
}
