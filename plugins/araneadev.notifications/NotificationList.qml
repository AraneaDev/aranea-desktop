// Grouped notification list presentation; action policy remains in Panel.qml.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import "components"
import "InboxLogic.js" as InboxLogic

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
  property real cornerRadius: 0
  // Public contract member.
  property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : Style.font.family
  // Public contract member.
  property bool motionEnabled: true
  // Public contract member.
  readonly property real contentHeight: list.contentHeight
  // Public contract member.
  signal activated(int index, var row)
  // Public contract member.
  signal dismissed(int index, var row)
  // Public contract member.
  signal groupToggled(string app)
  // Public contract member.
  signal groupDismissed(string app)

  implicitHeight: list.contentHeight

  // Keeps Panel.qml's cursor navigation independent of the ListView instance.
  function positionViewAtIndex(index: int, mode: int): void {
    list.positionViewAtIndex(index, mode)
  }

  ListView {
    id: list
    anchors.fill: parent
    model: root.rows
    spacing: Style.space(6)
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    delegate: Loader {
      id: rowLoader
      required property var modelData
      required property int index
      width: list.width
      sourceComponent: modelData.kind === "group" ? groupRow : (modelData.kind === "more" ? moreRow : entryRow)

      Component {
        id: groupRow
        NotificationGroupRow {
          app: rowLoader.modelData.app
          count: rowLoader.modelData.count
          collapsed: rowLoader.modelData.collapsed
          fontFamily: root.fontFamily
          onGroupClicked: root.groupToggled(rowLoader.modelData.app)
          onCloseRequested: root.groupDismissed(rowLoader.modelData.app)
        }
      }

      Component {
        id: moreRow
        Text {
          leftPadding: Style.space(12)
          text: "+" + rowLoader.modelData.hidden + " more"
          color: root.cursor === rowLoader.index ? Color.notifications.countdown : Qt.darker(Color.popups.text, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated(rowLoader.index, rowLoader.modelData)
          }
        }
      }

      Component {
        id: entryRow
        NotificationCard {
          width: list.width
          compact: true
          selected: root.cursor === rowLoader.index
          motionEnabled: root.service ? root.service.motionEnabled : root.motionEnabled
          app: rowLoader.modelData.entry.app
          appIcon: rowLoader.modelData.entry.appIcon
          summary: rowLoader.modelData.entry.summary
          body: rowLoader.modelData.entry.body
          image: rowLoader.modelData.entry.image
          glyph: rowLoader.modelData.entry.glyph
          urgency: rowLoader.modelData.entry.urgency
          timeLabel: InboxLogic.relativeTime(rowLoader.modelData.entry.timestamp, root.now)
          cornerRadius: root.service ? root.service.cornerRadius : root.cornerRadius
          fontFamily: root.bar ? root.bar.fontFamily : root.fontFamily
          onCardClicked: root.activated(rowLoader.index, rowLoader.modelData)
          onCloseRequested: root.dismissed(rowLoader.index, rowLoader.modelData)
          onSwipeDismissed: root.dismissed(rowLoader.index, rowLoader.modelData)
        }
      }
    }
  }
}
