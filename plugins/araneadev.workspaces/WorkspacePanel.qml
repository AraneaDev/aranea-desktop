// Workspace overview content shared by the live and test panel hosts.
import QtQuick
import QtQuick.Layouts
import qs.Commons

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

    RowLayout {
      Layout.fillWidth: true

      Text {
        text: "Workspace overview"
        color: Color.popups.text
        font.pixelSize: Style.font.title
        font.bold: true
        font.family: Style.font.family
        Layout.fillWidth: true
      }

      Text {
        text: "CYCLE  ·  FOCUS"
        color: Color.popups.text
        opacity: 0.75
        font.pixelSize: Style.font.caption
        font.family: Style.font.family
      }
    }

    Text {
      text: "ENTER FOCUS  ·  WHEEL CYCLE  ·  ESC CLOSE"
      color: Color.popups.text
      opacity: 0.5
      font.pixelSize: Style.font.caption
      font.family: Style.font.family
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Util.alpha(Color.popups.text, 0.16)
    }

    Text {
      text: "WORKSPACES  ·  " + panel.workspaceStates.length
      color: Color.popups.text
      opacity: 0.7
      font.pixelSize: Style.font.caption
      font.family: Style.font.family
    }

    Repeater {
      model: panel.workspaceStates
      delegate: Rectangle {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(50)
        color: panel.cursorIndex === index || rowArea.containsMouse ? Util.alpha(Color.popups.text, 0.06) : "transparent"

        Rectangle {
          width: Style.space(2)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          color: modelData.urgent ? Color.accent : (modelData.active ? Color.accent : Util.alpha(Color.popups.text, 0.25))
        }

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(16)
          anchors.rightMargin: Style.space(14)
          spacing: Style.space(12)

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              text: "WORKSPACE " + modelData.name
              color: modelData.active ? Color.accent : Color.popups.text
              font.bold: modelData.active
              font.pixelSize: Style.font.subtitle
              font.family: Style.font.family
            }

            Text {
              text: modelData.windowLabels && modelData.windowLabels.length > 0 ? modelData.windowLabels.join("  ·  ") : (modelData.windows > 0 ? "OPEN WINDOWS" : "EMPTY")
              color: Color.popups.text
              opacity: 0.55
              font.pixelSize: Style.font.caption
              font.family: Style.font.family
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
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
