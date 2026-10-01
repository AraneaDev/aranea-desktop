// Small on/off switch in the Filament style: a short strand with a node
// that sits right and glows when on, left and grey when off.
import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: sw

  // Whether the switch is on.
  property bool checked: false
  // Whether the keyboard cursor is on the switch.
  property bool hasCursor: false

  // Emitted when the switch is clicked or activated.
  signal toggled

  // Toggles from the keyboard or a click.
  function activate() {
    toggled()
  }

  implicitWidth: Style.space(34)
  implicitHeight: Style.space(16)

  Rectangle {
    // The keyboard cursor outline.
    objectName: "cursorOutline"
    anchors.fill: parent
    anchors.margins: -Style.space(3)
    color: "transparent"
    border.width: sw.hasCursor ? 1 : 0
    border.color: DesignTokens.accent
  }
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(2, Style.space(2))
    color: Util.alpha(DesignTokens.foreground, 0.15)
  }
  // The node's soft mint glow while on.
  RectangularShadow {
    x: knob.x
    y: knob.y
    width: knob.width
    height: knob.height
    radius: knob.radius
    blur: Style.space(8)
    color: Util.alpha(DesignTokens.accent, 0.8)
    visible: sw.checked
  }
  Rectangle {
    id: knob
    width: Style.space(12)
    height: width
    radius: width / 2
    anchors.verticalCenter: parent.verticalCenter
    x: sw.checked ? sw.width - width : 0
    color: Color.background
    border.width: Math.max(1, Style.space(2))
    border.color: sw.checked ? DesignTokens.accent : Util.alpha(DesignTokens.foreground, 0.22)
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: sw.activate()
  }
}
