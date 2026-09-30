// Update center content shared by the live and test panel hosts.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "UpdateLogic.js" as UpdateLogic

Item {
  id: panel

  // Owning bar widget.
  property var owner: null
  // Bar host used for panel coordination.
  property var bar: null
  // Current update status.
  property var status: ({})
  // Keyboard-selected action index.
  property int cursorIndex: 0
  // Compatibility signal for panel hosts.
  signal closed
  // Request the updater action.
  signal openUpdater
  // Request a status refresh.
  signal refresh

  // Maximum popup height a long update list may grow the panel to; the
  // group list scrolls past this instead of pushing the panel off-screen.
  readonly property real maxHeight: Style.space(520)
  // Height left for the group list once the fixed chrome is accounted for.
  readonly property real maxListHeight: Math.max(0, maxHeight - (header.implicitHeight + statusRow.implicitHeight + footer.implicitHeight + layout.spacing * 3))

  implicitWidth: Style.space(500)
  // Sized by its content: the gaps stay the layout spacing.
  implicitHeight: layout.implicitHeight
  width: implicitWidth
  height: implicitHeight

  ColumnLayout {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(8)

    Aranea.PanelHeader {
      id: header
      Layout.fillWidth: true
      title: "Update center"
      hint: UpdateLogic.headerHint(panel.status)
      hintText: "ENTER OPEN UPDATER  ·  R REFRESH  ·  ESC CLOSE"
      section: "SYSTEM STATUS"
    }

    Aranea.StatusRow {
      id: statusRow
      Layout.fillWidth: true
      rowHeight: Style.space(62)
      railColor: panel.status.error || panel.status.rebootRequired ? Color.accent : Util.alpha(Color.popups.text, 0.25)
      title: panel.status.error ? "CHECK FAILED" : (panel.status.rebootRequired ? "REBOOT REQUIRED" : "UP TO DATE")
      titleColor: panel.status.error || panel.status.rebootRequired ? Color.accent : Color.popups.text
      subtitle: panel.status.count + (panel.status.count === 1 ? " update available" : " updates available")

      Text {
        text: panel.status.error ? "ERROR" : (panel.status.rebootRequired ? "WARN" : "OK")
        color: panel.status.error || panel.status.rebootRequired ? Color.accent : Color.popups.text
        font.bold: true
        font.pixelSize: Style.font.body
        font.family: Style.font.family
      }
    }

    // Scrolls when the group list would otherwise grow the panel past
    // panel.maxHeight; a no-op sizing pass-through for a short list.
    Flickable {
      id: groupList
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(groupLayout.implicitHeight, panel.maxListHeight)
      visible: (panel.status.groups || []).length > 0
      contentWidth: width
      contentHeight: groupLayout.implicitHeight
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: groupLayout
        width: groupList.width
        spacing: Style.space(8)

        Repeater {
          model: panel.status.groups || []
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: modelData.source
              color: Color.popups.text
              font.bold: true
              font.pixelSize: Style.font.body
              font.family: Style.font.family
              Layout.preferredWidth: Style.space(90)
            }

            Text {
              text: modelData.count + (modelData.count === 1 ? " item" : " items")
              color: Color.popups.text
              opacity: 0.7
              font.pixelSize: Style.font.caption
              font.family: Style.font.family
              Layout.fillWidth: true
            }
          }
        }
      }
    }

    RowLayout {
      id: footer
      Layout.fillWidth: true

      Text {
        text: "OPEN UPDATER"
        color: panel.cursorIndex === 0 || openUpdaterArea.containsMouse ? Color.accent : Color.popups.text
        font.pixelSize: Style.font.body
        font.family: Style.font.family
        Layout.fillWidth: true

        MouseArea {
          id: openUpdaterArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.openUpdater()
        }
      }

      Text {
        text: "REFRESH"
        color: panel.cursorIndex === 1 || refreshArea.containsMouse ? Color.accent : Color.popups.text
        font.pixelSize: Style.font.body
        font.family: Style.font.family

        MouseArea {
          id: refreshArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.refresh()
        }
      }
    }
  }
}
