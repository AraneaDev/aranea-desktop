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
  // Font family used by both labels.
  property string fontFamily: Style.font.family
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

  Column {
    anchors.centerIn: parent
    spacing: empty.spacing

    Text {
      text: empty.icon
      color: empty.iconColor
      opacity: empty.iconOpacity
      font.family: empty.fontFamily
      font.pixelSize: empty.iconSize
      horizontalAlignment: Text.AlignHCenter
      width: empty.contentWidth
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
