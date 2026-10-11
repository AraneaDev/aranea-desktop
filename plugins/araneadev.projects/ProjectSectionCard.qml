// A lightweight content group that follows the desktop palette and spacing.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons

Rectangle {
  id: card
  // Theme-scaled inset around grouped content.
  property int padding: Style.space(16)
  // Children participate in the internal vertical layout.
  default property alias content: body.data
  implicitHeight: body.implicitHeight + padding * 2
  color: Util.alpha(Color.foreground, 0.035)
  radius: Style.space(6)
  border.color: Util.alpha(Color.foreground, 0.1)
  border.width: 1
  ColumnLayout {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: card.padding
    spacing: Style.space(12)
  }
}
