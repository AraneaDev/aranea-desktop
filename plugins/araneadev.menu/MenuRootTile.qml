// Presentational tile used by the menu's full root header.
// qmllint disable missing-property
import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: tile

  // Menu data object containing icon, label and detail fields.
  required property var tileData
  // Primary tile label.
  property string label: tileData && tileData.label ? tileData.label : ""
  // Tile icon glyph.
  property string icon: tileData && tileData.icon ? tileData.icon : ""
  // Secondary tile detail text.
  property string detail: tileData && tileData.detail ? tileData.detail : ""
  // External selection state.
  property bool selected: false
  // Font family used for all tile text.
  property string fontFamily: Style.font.menuFamily
  // Main tile text colour.
  property color foreground: Color.menu.text
  // Secondary tile text colour.
  property color contextText: Util.alpha(foreground, 0.58)
  // Accent colour for the icon and edge marks.
  property color selectedText: Color.menu.selectedText
  // Scale applied to the shell font sizes.
  property real menuFontScale: 1.0
  // Letter spacing applied to tile text.
  property real menuLetterSpacing: 0.2
  // Whether parent animations are enabled.
  property bool motionEnabled: true
  // Whether the pointer is currently over the tile.
  property bool hovered: false

  // Emitted when the tile is clicked.
  signal activated

  implicitHeight: Style.space(96)
  radius: Style.space(5)
  color: tile.selected || tile.hovered ? Util.alpha(tile.selectedText, 0.12) : "transparent"
  borderSpec: Border.none()

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    width: Style.space(18)
    height: Style.space(2)
    color: tile.selectedText
    opacity: tile.selected || tile.hovered ? 0.9 : 0.25
  }

  Rectangle {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: Style.space(18)
    height: Style.space(2)
    color: tile.selectedText
    opacity: tile.selected || tile.hovered ? 0.9 : 0.25
  }

  Column {
    width: parent.width - Style.space(28)
    anchors.centerIn: parent
    spacing: Style.space(11)

    Text {
      width: parent.width
      text: tile.icon
      color: tile.selectedText
      font.family: tile.fontFamily
      font.pixelSize: Style.font.iconLarge
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width
      text: tile.label
      color: tile.foreground
      font.family: tile.fontFamily
      font.pixelSize: Style.font.bodySmall * tile.menuFontScale
      font.letterSpacing: tile.menuLetterSpacing
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: tile.detail
      color: tile.contextText
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption * tile.menuFontScale
      font.weight: Font.Medium
      font.letterSpacing: tile.menuLetterSpacing
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.activated()
    onEntered: tile.hovered = true
    onExited: tile.hovered = false
  }
}
