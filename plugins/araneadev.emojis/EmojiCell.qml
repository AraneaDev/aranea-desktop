// Presentational emoji cell. Selection and insertion remain owned by Emojis.qml.
// qmllint disable missing-property
import QtQuick
import qs.Commons

Rectangle {
  id: cell

  // Emoji glyph rendered in the cell.
  property string glyph: ""
  // Whether the cell receives the selected styling.
  property bool hasCursor: false
  // Font used for the emoji glyph.
  property string fontFamily: Style.font.menuFamily
  // Cell width used by the picker grid.
  property int cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  // Cell height used by the picker grid.
  property int cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  // Corner radius for the selected cell surface.
  property int cornerRadius: Style.cornerRadius
  // Fill used for the selected cell.
  property color selectedBackground: Color.menu.selectedBackground
  // Border and glyph color used for the selected cell.
  property color selectedText: Color.menu.selectedText
  // Emitted when the user activates the cell.
  signal picked

  width: cellWidth
  height: cellHeight
  radius: cornerRadius
  color: hasCursor ? selectedBackground : "transparent"
  border.width: hasCursor ? 1.5 : 0
  border.color: selectedText

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: cell.glyph
    font.family: cell.fontFamily
    font.pixelSize: Style.font.display
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: cell.picked()
  }
}
