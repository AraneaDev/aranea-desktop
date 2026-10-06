// Shared centered empty-state presentation for menu and picker surfaces.
// The owning surface supplies the icon and message while retaining its state.
// qmllint disable missing-property

import QtQuick
import qs.Commons

Item {
  id: empty

  // Symbol shown above the empty-state message.
  property string icon: ""
  // User-facing empty-state message.
  property string message: ""
  // Font family used by the message.
  property string fontFamily: Style.font.family
  // Separate glyph family; legacy consumers retain their existing override.
  property string iconFontFamily: fontFamily
  // Accent colour for the icon.
  property color iconColor: Color.accent
  // Foreground colour for the message.
  property color foreground: Color.foreground
  // Icon opacity.
  property real iconOpacity: 0.8
  // Maximum width of the centered labels.
  property int contentWidth: Style.space(320)
  // Icon size.
  property int iconSize: Style.font.displayLarge
  // Message size.
  property int messageSize: Style.font.title
  // Vertical gap between icon and message.
  property int spacing: Style.space(12)
  // Image shown instead of the icon glyph (e.g. the brand mark); empty for none.
  property url imageSource: ""
  // Size of imageSource.
  property int imageSize: Style.space(28)
  // Opacity of imageSource.
  property real imageOpacity: 0.6

  implicitWidth: column.implicitWidth
  implicitHeight: column.implicitHeight

  Column {
    id: column
    anchors.centerIn: parent
    spacing: empty.spacing

    InkText {
      visible: empty.imageSource.toString().length === 0
      text: empty.icon
      color: empty.iconColor
      opacity: empty.iconOpacity
      font.family: empty.iconFontFamily
      font.pixelSize: empty.iconSize
      horizontalAlignment: Text.AlignHCenter
      width: empty.contentWidth
    }

    Item {
      visible: empty.imageSource.toString().length > 0
      width: empty.contentWidth
      height: empty.imageSize
      Image {
        anchors.horizontalCenter: parent.horizontalCenter
        width: empty.imageSize
        height: empty.imageSize
        source: empty.imageSource
        sourceSize: Qt.size(empty.imageSize * 2, empty.imageSize * 2)
        fillMode: Image.PreserveAspectFit
        opacity: empty.imageOpacity
        smooth: true
      }
    }

    Text {
      textFormat: Text.PlainText
      text: empty.message
      color: empty.foreground
      opacity: 0.7
      font.family: empty.fontFamily
      font.pixelSize: empty.messageSize
      horizontalAlignment: Text.AlignHCenter
      width: empty.contentWidth
    }
  }
}
