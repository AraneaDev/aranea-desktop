// Workspace overview content shared by the live and test panel hosts.
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
  // Normalized workspace rows rendered by the panel.
  property var workspaceStates: []
  // Keyboard-selected row index.
  property int cursorIndex: -1
  // Compatibility signal for panel hosts.
  signal closed
  // Request focus for a workspace row.
  signal focusWorkspace(int id)

  implicitWidth: Style.space(500)
  implicitHeight: Math.min(Style.space(520), Style.space(154) + workspaceStates.length * Style.space(58))
  width: implicitWidth
  height: implicitHeight

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    Aranea.PanelHeader {
      Layout.fillWidth: true
      title: "Workspace overview"
      hint: "CYCLE  ·  FOCUS"
      hintText: "ENTER FOCUS  ·  WHEEL CYCLE  ·  ESC CLOSE"
      section: "WORKSPACES  ·  " + panel.workspaceStates.length
    }

    Repeater {
      model: panel.workspaceStates
      delegate: Rectangle {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(50)
        color: panel.cursorIndex === index || rowArea.containsMouse ? Util.alpha(Color.popups.text, 0.06) : "transparent"

        Aranea.StatusRail {
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          railColor: modelData.urgent ? Color.accent : (modelData.active ? Color.accent : Util.alpha(Color.popups.text, 0.25))
        }

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(16)
          anchors.rightMargin: Style.space(14)
          spacing: Style.space(12)

          Aranea.StatusTextPair {
            Layout.fillWidth: true
            title: "WORKSPACE " + modelData.name
            titleColor: modelData.active ? Color.accent : Color.popups.text
            titleBold: modelData.active
            subtitle: modelData.windowLabels && modelData.windowLabels.length > 0 ? modelData.windowLabels.join("  ·  ") : (modelData.windows > 0 ? "OPEN WINDOWS" : "EMPTY")
            subtitleSize: Style.font.caption
            subtitleElide: Text.ElideRight
          }

          Text {
            text: modelData.windows + (modelData.windows === 1 ? " WINDOW" : " WINDOWS")
            color: Color.popups.text
            opacity: 0.7
            font.pixelSize: Style.font.caption
            font.family: Style.font.family
          }

          Text {
            visible: modelData.urgent
            text: "ATTENTION"
            color: Color.accent
            font.bold: true
            font.pixelSize: Style.font.caption
            font.family: Style.font.family
          }
        }

        MouseArea {
          id: rowArea
          anchors.fill: parent
          hoverEnabled: true
          onClicked: panel.focusWorkspace(modelData.id)
        }
      }
    }
  }
}
