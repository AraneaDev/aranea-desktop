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

  // Maximum height this panel's content (this Item, not the host's card) may
  // grow to; the caller owns this number. The host passes down its real cap
  // (KeyboardPanel's availableCardHeight/verticalContentInset), since only it
  // knows how much of the popup's height is card padding and border versus
  // content; a second, independently-guessed cap here previously let a long
  // list overflow the card by the padding+border amount. Unbounded by
  // default so a standalone panel (previews, tests without a host) isn't
  // artificially capped.
  property real maxContentHeight: Infinity
  // Height left for the row list once the fixed chrome is accounted for.
  readonly property real maxListHeight: Math.max(0, maxContentHeight - (header.implicitHeight + layout.spacing))

  implicitWidth: Style.space(500)
  // Sized by its content: the gaps stay the layout spacing.
  implicitHeight: layout.implicitHeight
  width: implicitWidth
  height: implicitHeight

  // Keeps the keyboard-selected row inside the (possibly capped/scrolled)
  // viewport: moveCursor() only changes cursorIndex, it never touches
  // rowList's contentY, so without this a capped list could select a row
  // that's scrolled out of view.
  onCursorIndexChanged: ensureCursorVisible()

  // Scrolls rowList the minimum amount needed to bring the row at
  // cursorIndex fully into view; a no-op when it's already visible or there
  // is no cursor row.
  function ensureCursorVisible() {
    if (panel.cursorIndex < 0)
      return
    var item = rowRepeater.itemAt(panel.cursorIndex)
    if (!item)
      return
    var maxContentY = Math.max(0, rowList.contentHeight - rowList.height)
    if (item.y < rowList.contentY)
      rowList.contentY = Math.max(0, item.y)
    else if (item.y + item.height > rowList.contentY + rowList.height)
      rowList.contentY = Math.min(maxContentY, item.y + item.height - rowList.height)
  }

  // True when the row at INDEX is fully within the scrolled viewport (used
  // by callers/tests to confirm keyboard navigation keeps the cursor row
  // visible).
  function isRowVisible(index) {
    var item = rowRepeater.itemAt(index)
    if (!item)
      return false
    return item.y >= rowList.contentY && item.y + item.height <= rowList.contentY + rowList.height
  }

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
    // panel.maxContentHeight; a no-op sizing pass-through for a short list.
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
          id: rowRepeater
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
