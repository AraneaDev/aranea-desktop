// Workspace overview content shared by the live and test panel hosts: a
// DropdownHeader (glyph, "Workspaces", "N open"), then one row per
// workspace (an Aranea.NodeDeviceRow lit on the current workspace, red for
// an urgent one, with the window count plus "current"/"attention" as
// detail, and a titles line underneath when any window has one), and a key
// hint at the bottom. Pure view: rows and the keyboard cursor in, keyed
// signals out.
//
// Every row is keyed by WorkspaceModel.workspaceKey (the workspace id) and
// a click or Enter is refused when the row no longer carries the key it
// was aimed at. The Repeater runs over the row count, so a workspace list
// that changes while the dropdown is open never recreates a row under a
// resting pointer. When the rows really move, or a row's titles line
// appears or disappears (workspaceLayoutSignature changes), the panel
// stamps layoutChangedAt, which the rows read through pointerGate: a click
// within 300 ms of it is ignored unless the pointer has really moved onto
// the row since. The mint outline is drawn only on cursorIndex, which the
// host sets only while the keyboard drives it; pointer hover never
// highlights a row.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "WorkspaceModel.js" as WorkspaceModel

Item {
  id: panel

  // Owning bar widget.
  property var owner: null
  // Bar host used for panel coordination.
  property var bar: null
  // Normalized workspace rows rendered by the panel.
  property var workspaceStates: []
  // Row index of the keyboard cursor, -1 for none (the host passes -1
  // while the pointer drives, so the outline is keyboard only).
  property int cursorIndex: -1
  // Compatibility signal for panel hosts.
  signal closed
  // Emitted with a workspace's id once a settled click or Enter on its row
  // is accepted, keyed by activateRow so a stale index never focuses
  // another workspace.
  signal focusWorkspace(int id)
  // Emitted when the pointer really moves onto row INDEX; the host places
  // the cursor there, hidden, so a following key reveals it in place.
  signal rowHovered(int index)

  // Maximum height this panel's content (this Item, not the host's card) may
  // grow to; the caller owns this number. The host passes down its real cap
  // (KeyboardPanel's availableCardHeight/verticalContentInset), since only it
  // knows how much of the popup's height is card padding and border versus
  // content; a second, independently-guessed cap here previously let a long
  // list overflow the card by the padding+border amount. Unbounded by
  // default so a standalone panel (previews, tests without a host) isn't
  // artificially capped.
  property real maxContentHeight: Infinity
  // The hairline's height, shared with the maxListHeight sum below so
  // Style.spacing.hairline is only read in one place.
  readonly property real hairlineHeight: Math.max(1, Style.spacing.hairline)
  // Height left for the row list once the fixed chrome (the header, the
  // hairline and the key hint) is accounted for.
  readonly property real maxListHeight: Math.max(0, maxContentHeight - (header.implicitHeight + panel.hairlineHeight + keyHint.implicitHeight + layout.spacing * 3))

  // Every row's id paired with whether it shows a titles line, joined: a
  // host can tell when the rows really moved, or when a row's titles line
  // appeared/disappeared and so resized it, since either can shift the
  // rows below under a resting pointer. An equal list rebuilt gives the
  // same string.
  readonly property string layoutSignature: WorkspaceModel.workspaceLayoutSignature(panel.workspaceStates)
  // When the rows last moved under the pointer (Date.now()), 0 for never.
  property real layoutChangedAt: 0
  // Filters synthetic hover from rows moving under a still pointer, and
  // carries layoutChangedAt to the rows' clickSettled().
  readonly property alias pointerGate: gate

  // Stamps layoutChangedAt: the rows moved without the pointer moving.
  function noteLayoutChange() {
    panel.layoutChangedAt = Date.now()
  }
  onLayoutSignatureChanged: panel.noteLayoutChange()

  // Resets the pointer gate; called after every key so a stale pointer
  // sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

  // Reports row INDEX as activated, refused when it no longer holds KEY.
  function activateRow(index, key) {
    var row = WorkspaceModel.keyedWorkspace(panel.workspaceStates, index, key)
    if (row)
      panel.focusWorkspace(row.id)
  }

  // The row at INDEX: its Aranea.NodeDeviceRow (objectName "workspaceNode"),
  // or null. Found by objectName, not a typed property, so qmllint can
  // still check this against the Repeater's generically-typed item. The
  // titles line underneath it, when shown, has objectName "workspaceTitles"
  // and is reached through t.findChild/t.findChildren in tests.
  function rowAt(index) {
    var wrap = rowRepeater.itemAt(index)
    if (!wrap)
      return null
    for (var i = 0; i < wrap.children.length; i++)
      if (wrap.children[i].objectName === "workspaceNode")
        return wrap.children[i]
    return null
  }

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

    Aranea.DropdownHeader {
      id: header
      refined: true
      Layout.fillWidth: true
      glyph: String.fromCodePoint(0x283f)
      title: "Workspaces"
      caption: WorkspaceModel.openCaption(panel.workspaceStates.length)
    }

    Rectangle {
      // The hairline between the header and the row list.
      Layout.fillWidth: true
      Layout.preferredHeight: panel.hairlineHeight
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
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
      onVisibleChanged: panel.noteLayoutChange()
      onHeightChanged: panel.noteLayoutChange()

      ColumnLayout {
        id: rowLayout
        width: rowList.width
        spacing: Style.space(4)

        // The model is the row count, not the array: a refresh that hands
        // over a fresh (but equal) workspaceStates array never recreates a
        // row under a resting pointer. Each delegate is the workspace's
        // Aranea.NodeDeviceRow plus, underneath it, a titles line that
        // takes no space while empty. A plain Item with an explicit
        // implicitHeight, not a Column, since a Column-of-Columns through
        // this Repeater does not reflow its height in the offscreen test
        // harness (confirmed against panel-heights.qml's 20-row cases);
        // this is the same implicitHeight-on-an-Item pattern NodeDeviceRow
        // itself uses as a ColumnLayout child.
        Repeater {
          id: rowRepeater
          model: panel.workspaceStates.length
          Item {
            id: rowWrap
            required property int index
            // This row's workspace, read from the live array.
            readonly property var workspace: panel.workspaceStates[rowWrap.index] || ({})
            // The row's key, sent with its action.
            readonly property string key: WorkspaceModel.workspaceKey(rowWrap.workspace)
            // The row's secondary text: its open windows' titles, joined,
            // "" when there are none to show.
            readonly property string titles: WorkspaceModel.workspaceTitles(rowWrap.workspace)

            objectName: "workspaceRow"
            Layout.fillWidth: true
            implicitHeight: node.height + (titlesText.visible ? Style.space(2) + titlesText.height : 0)

            Aranea.NodeDeviceRow {
              id: node
              refined: true
              objectName: "workspaceNode"
              labelFontFamily: Aranea.Typography.technicalFamily
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              label: WorkspaceModel.workspaceLabel(rowWrap.workspace)
              detail: WorkspaceModel.workspaceDetail(rowWrap.workspace)
              detailColor: rowWrap.workspace.urgent ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.foreground, 0.55)
              nodeColor: rowWrap.workspace.urgent ? Aranea.DesignTokens.urgent : Aranea.DesignTokens.accent
              // Lit (filled, glowing) for the current workspace, and for an
              // urgent one even when it is not current, so attention is
              // visible wherever the workspace is.
              active: !!(rowWrap.workspace.active || rowWrap.workspace.urgent)
              // The current workspace carries the selected highlight.
              selected: !!rowWrap.workspace.active
              hasCursor: panel.cursorIndex === rowWrap.index
              pointerGate: panel.pointerGate
              onChosen: panel.activateRow(rowWrap.index, rowWrap.key)
              onEntered: panel.rowHovered(rowWrap.index)
            }

            Text {
              id: titlesText
              objectName: "workspaceTitles"
              visible: rowWrap.titles !== ""
              anchors.top: node.bottom
              anchors.topMargin: Style.space(2)
              // Indents roughly under node's label text (past its marker
              // and glyph slot); a secondary line, so pixel-exact alignment
              // with the label isn't required.
              x: Style.space(54)
              width: Math.max(0, rowWrap.width - x)
              text: rowWrap.titles
              elide: Text.ElideRight
              color: Util.alpha(Aranea.DesignTokens.foreground, 0.5)
              font.family: Aranea.Typography.uiFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    Text {
      id: keyHint
      objectName: "keyHint"
      Layout.fillWidth: true
      text: "↑↓ move · enter focus · wheel cycle"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  PointerMoveGate {
    id: gate
    // This panel's last layout shift, for the rows' clickSettled().
    property real layoutChangedAt: panel.layoutChangedAt

    referenceItem: panel
  }
}
