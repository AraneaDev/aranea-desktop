// The "forget" button a dropdown row shows at its right edge (Bluetooth's
// devices, Network's Wi-Fi and Saved rows): soft red with a hairline
// border, brighter when the keyboard cursor's action is on it. It shows on
// a forgettable row under the pointer or the keyboard cursor, and sizes to
// zero while hidden so a NodeDeviceRow's trailing slot, which sizes to its
// children, never reserves room for it. Entering it is gated (pointerGate)
// so a button sliding under a still pointer never takes the cursor;
// leaving it, and its own hover and visibility, are not. Like NodeDeviceRow, a click within settleMs of
// the button being created is ignored unless the gate accepted a real
// pointer move onto it since.
import QtQuick
import qs.Commons
import qs.Ui

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
  // The button's tooltip.
  property string tooltipText: "Forget"
  // Whether the pointer is over the button itself.
  readonly property alias hovered: forgetHover.hovered
  // Whether the button shows: a forgettable row under the pointer (the
  // row or the button, which takes the hover from the row's MouseArea) or
  // the keyboard cursor.
  readonly property bool shown: forgettable && (rowHovered || forgetHover.hovered || hasCursor)
  // Whether it's drawn bright: the keyboard cursor's action is on it.
  readonly property bool bright: hasCursor && cursorAction
  // How long after creation a pointer click is ignored, in ms, unless the
  // gate has accepted a real move onto the button since.
  property int settleMs: 300
  // When the button was created (Date.now()), for settleMs.
  property real createdAt: 0
  // Whether the gate has accepted a real pointer move onto the button.
  property bool pointerMovedHere: false

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

  // Whether a pointer click may land: the button has been on screen for
  // settleMs, or the pointer has really moved onto it.
  function clickSettled() {
    return pointerMovedHere || Date.now() - createdAt >= settleMs
  }

  objectName: "forgetButton"
  visible: shown
  width: shown ? forgetLabel.implicitWidth + Style.space(12) : 0
  height: shown ? forgetLabel.implicitHeight + Style.space(4) : 0
  Component.onCompleted: createdAt = Date.now()

  Rectangle {
    objectName: "forgetBorder"
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: forgetBtn.bright ? DesignTokens.urgent : Util.alpha(DesignTokens.foreground, 0.22)
  }
  Text {
    id: forgetLabel
    objectName: "forgetLabel"
    anchors.centerIn: parent
    text: String.fromCodePoint(0xf0156) + " forget"
    color: forgetBtn.bright ? DesignTokens.urgent : Util.alpha(DesignTokens.urgent, 0.7)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: if (forgetBtn.clickSettled())
      forgetBtn.activate()
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
      })) {
        forgetBtn.pointerMovedHere = true
        forgetBtn.pointerEntered()
      }
    }
  }
  PanelToolTip {
    objectName: "forgetTip"
    visible: forgetHover.hovered
    text: forgetBtn.tooltipText
  }
}
