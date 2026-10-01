// The "forget" button the Aranea Network dropdown's Wi-Fi and Saved rows
// show at their right edge: Bluetooth's forget button (BluetoothDevice-
// Section.qml), soft red with a hairline border, brighter when the
// keyboard cursor's action is on it. It sizes to zero while hidden so a
// NodeDeviceRow's trailing slot, which sizes to its children, never
// reserves room for it.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Item {
  id: forgetBtn

  // Whether the row can be forgotten at all.
  property bool forgettable: false
  // Whether the pointer is over the row the button sits in.
  property bool rowHovered: false
  // Whether the keyboard cursor is on the row.
  property bool hasCursor: false
  // Whether the keyboard cursor's action (not just the row) is here.
  property bool cursorAction: false
  // Optional PointerMoveGate (qs.Ui): only a real pointer move onto the
  // button reports pointerEntered.
  property var pointerGate: null
  // The tooltip.
  property string tooltipText: "Forget network"
  // Whether the pointer is over the button itself.
  readonly property alias hovered: forgetHover.hovered
  // Whether the button shows: a forgettable row under the pointer (the
  // row or the button, which takes the hover from the row's MouseArea) or
  // the keyboard cursor.
  readonly property bool shown: forgettable && (rowHovered || forgetHover.hovered || hasCursor)
  // Whether it's drawn bright: the keyboard cursor's action is on it.
  readonly property bool bright: hasCursor && cursorAction

  // Emitted when the button is clicked.
  signal clicked
  // Emitted when the pointer moves onto the button (through the gate).
  signal pointerEntered
  // Emitted when the pointer leaves the button.
  signal pointerLeft

  // Clicks the button; directly callable from tests.
  function activate() {
    forgetBtn.clicked()
  }

  objectName: "forgetButton"
  visible: shown
  width: shown ? forgetLabel.implicitWidth + Style.space(12) : 0
  height: shown ? forgetLabel.implicitHeight + Style.space(4) : 0

  Rectangle {
    objectName: "forgetBorder"
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: forgetBtn.bright ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.foreground, 0.22)
  }
  Text {
    id: forgetLabel
    objectName: "forgetLabel"
    anchors.centerIn: parent
    text: String.fromCodePoint(0xf0156) + " forget"
    color: forgetBtn.bright ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.urgent, 0.7)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: forgetBtn.activate()
  }
  // Observes hover only. Entering is gated so a button sliding under a
  // still pointer never takes the cursor; leaving is not.
  HoverHandler {
    id: forgetHover
    onHoveredChanged: {
      if (!hovered)
        forgetBtn.pointerLeft()
      else if (!forgetBtn.pointerGate)
        forgetBtn.pointerEntered()
      else if (forgetBtn.pointerGate.moved(forgetHover.parent, {
        x: forgetHover.point.position.x,
        y: forgetHover.point.position.y
      }))
        forgetBtn.pointerEntered()
    }
  }
  PanelToolTip {
    objectName: "forgetTip"
    visible: forgetHover.hovered
    text: forgetBtn.tooltipText
  }
}
