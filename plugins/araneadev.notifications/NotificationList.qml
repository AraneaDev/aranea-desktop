// Notification row list presentation; action policy remains in Panel.qml.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

Item {
  id: root
  // Public contract member.
  property var rows: []
  // Public contract member.
  property int cursor: -1
  // Public contract member.
  property real now: Date.now()
  // Public contract member.
  property var service: null
  // Public contract member.
  property var bar: null
  // Public contract member.
  property string fontFamily: Style.font.family
  // Public contract member.
  property bool motionEnabled: true
  // Public contract member.
  property color cursorColor: Color.notifications.countdown
  // Public contract member.
  signal activated(var row)
  // Public contract member.
  signal dismissed(var row)
  // Public contract member.
  signal groupToggled(string app)
  // Public contract member.
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
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated(modelData)
      }
    }
  }
}
