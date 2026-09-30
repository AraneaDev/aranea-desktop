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

  // Maximum popup height a long workspace list may grow the panel to; the
  // row list scrolls past this instead of pushing the panel off-screen.
  readonly property real maxHeight: Style.space(520)
  // Height left for the row list once the fixed chrome is accounted for.
  readonly property real maxListHeight: Math.max(0, maxHeight - (header.implicitHeight + layout.spacing))

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
      title: "Workspace overview"
      hint: "CYCLE  ·  FOCUS"
      hintText: "ENTER FOCUS  ·  WHEEL CYCLE  ·  ESC CLOSE"
      section: "WORKSPACES  ·  " + panel.workspaceStates.length
    }

    // Scrolls when the row list would otherwise grow the panel past
    // panel.maxHeight; a no-op sizing pass-through for a short list.
    Flickable {
      id: rowList
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(rowLayout.implicitHeight, panel.maxListHeight)
      visible: panel.workspaceStates.length > 0
      contentWidth: width
      contentHeight: rowLayout.implicitHeight
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: rowLayout
        width: rowList.width
        spacing: Style.space(8)

        Repeater {
          model: panel.workspaceStates
          delegate: Aranea.StatusRow {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            rowHeight: Style.space(50)
            highlighted: panel.cursorIndex === index
            clickable: true
            railColor: modelData.urgent ? Color.accent : (modelData.active ? Color.accent : Util.alpha(Color.popups.text, 0.25))
            title: "WORKSPACE " + modelData.name
            titleColor: modelData.active ? Color.accent : Color.popups.text
            titleBold: modelData.active
            subtitle: modelData.windowLabels && modelData.windowLabels.length > 0 ? modelData.windowLabels.join("  ·  ") : (modelData.windows > 0 ? "OPEN WINDOWS" : "EMPTY")
            subtitleSize: Style.font.caption
            subtitleElide: Text.ElideRight
            onClicked: panel.focusWorkspace(modelData.id)

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
        }
      }
    }
  }
}
