// Header, status and empty-state presentation for the notification center.
// qmllint disable missing-property unqualified
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: root
  // Public contract member.
  property int count: 0
  // Public contract member.
  property bool dnd: false
  // Public contract member.
  property bool confirmingClear: false
  // Public contract member.
  property bool quiet: false
  // Public contract member.
  property string quietUntil: ""
  // Public contract member.
  property string fontFamily: Style.font.family
  // Public contract member.
  property color foreground: Color.popups.text
  // Public contract member.
  property color focusAccent: Color.notifications.countdown
  // Public contract member.
  signal toggleDnd
  // Public contract member.
  signal clearAll

  implicitHeight: content.implicitHeight
  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.space(10)
    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: "Notifications"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        text: root.dnd ? "DND ◉" : "DND ○"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleDnd()
        }
      }
      Text {
        visible: root.count > 0
        text: root.confirmingClear ? "Confirm clear (" + root.count + ")" : "Clear all"
        color: root.focusAccent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.clearAll()
        }
      }
    }
    Text {
      Layout.fillWidth: true
      text: "ENTER OPEN · DEL DISMISS · ⇧DEL CLEAR GROUP"
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Text {
      visible: root.quiet && root.quietUntil !== ""
      text: "Quiet until " + root.quietUntil
      color: root.focusAccent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    ColumnLayout {
      visible: root.count === 0
      Layout.fillWidth: true
      Image {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Style.space(28)
        Layout.preferredHeight: Style.space(28)
        source: Aranea.RuntimePaths.glyphUrl
        opacity: 0.6
      }
      Text {
        Layout.alignment: Qt.AlignHCenter
        text: "All caught up"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
