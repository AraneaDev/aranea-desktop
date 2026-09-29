// Presentational emoji cell. Selection and insertion remain owned by Emojis.qml.
import QtQuick
import qs.Commons

Rectangle {
  id: cell

  property string glyph: ""
  property bool hasCursor: false
  property string fontFamily: Style.font.menuFamily
  property int cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int cornerRadius: Style.cornerRadius
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
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
