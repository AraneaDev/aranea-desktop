// Update center content shared by the live and test panel hosts: a
// DropdownHeader, a status row with a warn/ok node, the per-source group
// list (unchanged) and two FilamentPills ("Open updater", "Refresh") in the
// Filament style. The keyboard cursor and its mint outline are owned by the
// host (UpdatePanelHost.qml and BarWidget.qml's test host); this is the pure
// view, driven by plain props so tests can set cursorIndex/keyboardCursor/
// checking directly. A pointer click on a pill within 300 ms of this panel's
// layout shifting (the group list appearing, say) is ignored unless the
// pointer has really moved onto it since (ClickSettle, through pointerGate).
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
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
  // Whether Service is running a check right now.
  property bool checking: false
  // Keyboard-selected pill index: 0 "Open updater", 1 "Refresh".
  property int cursorIndex: 0
  // True while the keyboard drives the cursor; any pointer use clears it.
  // The mint outline shows only then, and the first key only reveals it.
  property bool keyboardCursor: false
  // Compatibility signal for panel hosts.
  signal closed
  // Request the updater action.
  signal openUpdater
  // Request a status refresh.
  signal refresh
  // Emitted when the pointer really moves onto pill INDEX (through the
  // gate). Informational: hover only draws the pill's fill and never moves
  // the cursor.
  signal pillHovered(int index)

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
  // Height left for the group list once the fixed chrome (including the
  // hairline between the header and the status row) is accounted for.
  readonly property real maxListHeight: Math.max(0, maxContentHeight - (header.implicitHeight + panel.hairlineHeight + statusSection.implicitHeight + footer.implicitHeight + keyHint.implicitHeight + layout.spacing * 5))

  // The status row's node tone, headline and count line (UpdateLogic.statusRow).
  readonly property var info: UpdateLogic.statusRow(panel.status)

  // Filters synthetic hover from the pills moving under a still pointer,
  // and carries layoutChangedAt to their clickSettled().
  readonly property alias pointerGate: gate
  // When this panel's layout last shifted under the pointer (Date.now()),
  // 0 for never.
  property real layoutChangedAt: 0

  // Stamps layoutChangedAt: a section grew, shrank or (dis)appeared without
  // the pointer moving.
  function noteLayoutChange() {
    panel.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; called after every key so a stale pointer
  // sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

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

    Aranea.DropdownHeader {
      id: header
      Layout.fillWidth: true
      glyph: String.fromCodePoint(0x21a5)
      glyphColor: panel.info.tone === "warn" ? Aranea.DesignTokens.attention : Aranea.DesignTokens.ceremony
      title: "Updates"
      caption: UpdateLogic.statusCaption(panel.status, panel.checking)
    }

    Hairline {}

    // The status row: a node tinted warn or ok, the headline, the update
    // count and a trailing tone word, replacing the old StatusRow/rail.
    Item {
      id: statusSection
      objectName: "statusSection"
      Layout.fillWidth: true
      implicitHeight: Style.space(36)

      Rectangle {
        id: node
        objectName: "statusNode"
        width: Style.space(8)
        height: width
        rotation: 45
        x: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        color: panel.info.tone === "warn" ? Aranea.DesignTokens.attention : Aranea.DesignTokens.ceremony
        border.width: 1
        border.color: color
      }
      Column {
        anchors.left: node.right
        anchors.leftMargin: Style.space(14)
        anchors.right: detail.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text {
          objectName: "statusTitle"
          width: parent.width
          text: panel.info.title
          elide: Text.ElideRight
          color: Aranea.DesignTokens.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          objectName: "statusSubtitle"
          width: parent.width
          text: panel.info.subtitle
          elide: Text.ElideRight
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
      Text {
        id: detail
        objectName: "statusDetail"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: panel.info.tone
        color: panel.info.tone === "warn" ? Aranea.DesignTokens.attention : Aranea.DesignTokens.ceremony
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    // Scrolls when the group list would otherwise grow the panel past
    // panel.maxContentHeight; a no-op sizing pass-through for a short list.
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
      onVisibleChanged: panel.noteLayoutChange()
      onHeightChanged: panel.noteLayoutChange()

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
      objectName: "footer"
      Layout.fillWidth: true
      spacing: Style.space(8)

      Aranea.FilamentPill {
        id: openPill
        objectName: "openUpdaterPill"
        Layout.fillWidth: true
        text: "Open updater"
        hasCursor: panel.keyboardCursor && panel.cursorIndex === 0
        pointerGate: panel.pointerGate
        onClicked: panel.openUpdater()
        onHoveredMoved: panel.pillHovered(0)
      }

      Aranea.FilamentPill {
        id: refreshPill
        objectName: "refreshPill"
        Layout.fillWidth: true
        text: panel.checking ? "Refreshing…" : "Refresh"
        busy: panel.checking
        hasCursor: panel.keyboardCursor && panel.cursorIndex === 1
        pointerGate: panel.pointerGate
        onClicked: if (!panel.checking)
          panel.refresh()
        onHoveredMoved: panel.pillHovered(1)
      }
    }

    Text {
      id: keyHint
      objectName: "keyHint"
      Layout.fillWidth: true
      // What Enter does on the cursor's pill (UpdateLogic.keyHint).
      text: UpdateLogic.keyHint(panel.cursorIndex)
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  PointerMoveGate {
    id: gate
    // This panel's last layout shift, for the pills' clickSettled().
    property real layoutChangedAt: panel.layoutChangedAt

    referenceItem: panel
  }

  // The hairline between sections.
  component Hairline: Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: panel.hairlineHeight
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }
}
