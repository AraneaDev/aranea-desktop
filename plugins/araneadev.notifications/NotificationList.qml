// Notification row list presentation; action policy remains in Panel.qml.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

Item {
  id: root
  property var rows: []
  property int cursor: -1
  property real now: Date.now()
  property var service: null
  property var bar: null
  property string fontFamily: Style.font.family
  property bool motionEnabled: true
  property color cursorColor: Color.notifications.countdown
  signal activated(var row)
  signal dismissed(var row)
  signal groupToggled(string app)
  signal groupDismissed(string app)

  implicitHeight: list.contentHeight
  ListView {
    id: list
    anchors.fill: parent
    model: root.rows
    spacing: Style.space(6)
    clip: true
    delegate: Text {
      required property var modelData
      required property int index
      width: ListView.view.width
      text: modelData.kind === "more" ? "+" + modelData.hidden + " more" : (modelData.kind === "group" ? modelData.app + " (" + modelData.count + ")" : modelData.entry.summary)
      color: root.cursor === index ? root.cursorColor : Color.popups.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activated(modelData) }
    }
  }
}
