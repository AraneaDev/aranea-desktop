// Update center content shared by the live and test panel hosts.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

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

  implicitWidth: Style.space(500)
  implicitHeight: Math.min(Style.space(520), Style.space(210) + (status.groups || []).length * Style.space(32))
  width: implicitWidth
  height: implicitHeight

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    Aranea.PanelHeader {
      Layout.fillWidth: true
      title: "Update center"
      hint: panel.status.error ? "CHECK FAILED" : "REFRESH"
      hintText: "ENTER OPEN UPDATER  ·  R REFRESH  ·  ESC CLOSE"
      section: "SYSTEM STATUS"
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(62)
      color: "transparent"

      Aranea.StatusRail {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        railColor: panel.status.error || panel.status.rebootRequired ? Color.accent : Util.alpha(Color.popups.text, 0.25)
      }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.space(16)
        anchors.rightMargin: Style.space(14)

        Aranea.StatusTextPair {
          Layout.fillWidth: true
          title: panel.status.error ? "CHECK FAILED" : (panel.status.rebootRequired ? "REBOOT REQUIRED" : "UP TO DATE")
          titleColor: panel.status.error || panel.status.rebootRequired ? Color.accent : Color.popups.text
          subtitle: panel.status.count + (panel.status.count === 1 ? " update available" : " updates available")
        }

        Text {
          text: panel.status.error ? "ERROR" : (panel.status.rebootRequired ? "WARN" : "OK")
          color: panel.status.error || panel.status.rebootRequired ? Color.accent : Color.popups.text
          font.bold: true
          font.pixelSize: Style.font.body
          font.family: Style.font.family
        }
      }
    }

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

    RowLayout {
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
