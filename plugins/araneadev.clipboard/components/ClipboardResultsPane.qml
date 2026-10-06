// Clipboard result list, selected preview, and empty state.
// Keyboard policy and clipboard actions remain owned by ClipboardWindow.qml.
// The mint outline marks the keyboard cursor (selectedIndex while
// cursorActive) and only the keyboard moves it; hover fills the row the
// pointer really moved onto (PointerMoveGate) and clears when the rows
// change or scroll under the pointer. Clicks are keyed by entry id and
// settled against layoutChangedAt and the list's own scroll stamp.
// qmllint disable missing-property unqualified

import QtQuick
import qs.Commons
import qs.Ui
import "../ClipboardLogic.js" as ClipboardLogic
import "../../araneadev.shared" as Aranea

Item {
  id: pane

  // Display rows supplied by Clipboard.qml.
  property var model: null
  // Original clipboard history used for secret previews.
  property var history: []
  // Current clock value used for secret expiry text.
  property real nowMs: Date.now()
  // Secret lifetime used by the preview label.
  property real secretTtlMs: 600000
  // Currently selected display-row index.
  property int selectedIndex: -1
  // Whether the keyboard outline shows on selectedIndex.
  property bool cursorActive: false
  // The gate that tells real pointer moves from rows moving under a still
  // pointer; the window shares its own, else the pane's.
  property var pointerGate: ownGate
  // When the rows last changed under a still pointer (Clipboard.qml's
  // layoutChangedAt), 0 for never.
  property real layoutChangedAt: 0
  // When the list last scrolled (Date.now()), 0 for never.
  property real scrolledAt: 0
  // The row the pointer really moved onto (hover fill), -1 for none.
  property int hoveredIndex: -1
  // The entry id that row held when hovered; the fill shows only while the
  // row still holds it.
  property string hoveredKey: ""
  // The list of rows (tests read its delegates).
  readonly property alias list: resultList
  // Index of a revealed secret, or -1 while masked.
  property int revealedIndex: -1
  // Row height supplied by the clipboard window.
  property int rowHeight: Style.space(50)
  // Content margin shared with the containing card.
  property int contentMargin: Style.spacing.panelPadding
  // Font family used by rows and the preview.
  property string fontFamily: Aranea.Typography.uiFamily
  // Main content colour.
  property color foreground: Color.menu.text
  // Selected-row foreground colour.
  property color selectedText: Color.menu.selectedText
  // Selected-row background colour.
  property color selectedBackground: Color.menu.selectedBackground
  // Preview border colour.
  property color borderColor: Color.menu.border
  // Card corner radius shared with the preview.
  property real cornerRadius: Style.cornerRadius
  // Message shown when no display rows are available.
  property string emptyMessage: "Clipboard is empty"
  // Converts a clipboard kind to its fallback glyph.
  property var kindGlyph: function (kind) {
    return kind || ""
  }

  // Emitted for a settled click on row ROWINDEX that still holds KEY (its
  // entry id) on release.
  signal rowActivated(int rowIndex, string key)

  // Drops the hover fill: the rows moved or changed under the pointer.
  function clearHover(): void {
    pane.hoveredIndex = -1
    pane.hoveredKey = ""
  }

  onLayoutChangedAtChanged: pane.clearHover()

  // Scroll the selected result into view.
  function reveal(index: int): void {
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  // Currently selected row projected from the display model.
  readonly property var activeRow: model && model.count > 0 && selectedIndex >= 0 && selectedIndex < model.count ? model.get(selectedIndex) : null
  // Whether the selected secret remains hidden in the preview.
  readonly property bool masked: !!activeRow && activeRow.secret && revealedIndex !== selectedIndex

  // Probes the section caption's line box (same font as sectionCaption).
  Text {
    id: captionProbe
    visible: false
    text: "PINNED"
    font.family: pane.fontFamily
    font.pixelSize: Style.font.caption
    font.weight: Font.Medium
    font.letterSpacing: 0.20
  }
  // Cap-height ink of the caption font.
  TextMetrics {
    id: captionInk
    font: captionProbe.font
    text: "H"
  }
  // Cap top of the first section label from the top of the list (the section
  // header is 26 high with the caption 4 above its bottom).
  readonly property real firstLabelCapTop: Style.space(26) - Style.space(4) - captionProbe.height + captionProbe.baselineOffset + captionInk.tightBoundingRect.y

  Row {
    anchors.fill: parent
    spacing: 0

    Item {
      width: Math.round(parent.width * 0.48)
      height: parent.height
      clip: true

      ListView {
        id: resultList
        anchors.fill: parent
        anchors.rightMargin: pane.contentMargin
        model: pane.model
        clip: true
        spacing: Style.space(2)
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: {
          pane.scrolledAt = Date.now()
          pane.clearHover()
        }

        section.property: "section"
        section.delegate: Item {
          required property string section
          width: ListView.view.width
          height: Style.space(26)

          Rectangle {
            anchors.left: sectionCaption.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: 0
            anchors.verticalCenter: sectionCaption.verticalCenter
            height: 1
            color: Util.alpha(pane.foreground, 0.10)
          }

          Aranea.InkText {
            id: sectionCaption
            anchors.left: parent.left
            anchors.leftMargin: 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(4)
            horizontalAlignment: Text.AlignLeft
            textFormat: Text.PlainText
            text: parent.section === "pinned" ? "PINNED" : "RECENT"
            color: Util.alpha(pane.foreground, 0.58)
            font.family: pane.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            font.letterSpacing: 0.20
          }
        }

        delegate: ClipboardResultRow {
          objectName: "clipboardRow"
          hasCursor: pane.cursorActive && index === pane.selectedIndex
          hovered: pane.hoveredIndex === index && pane.hoveredKey === entryId
          pointerGate: pane.pointerGate
          layoutChangedAt: Math.max(pane.layoutChangedAt, pane.scrolledAt)
          width: ListView.view.width
          height: pane.rowHeight
          glyph: pane.kindGlyph(kind)
          fontFamily: pane.fontFamily
          foreground: pane.foreground
          selectedText: pane.selectedText
          selectedBackground: pane.selectedBackground
          cornerRadius: pane.cornerRadius
          onHoverMoved: function (rowIndex, key) {
            pane.hoveredIndex = rowIndex
            pane.hoveredKey = key
          }
          onHoverLeft: function (rowIndex) {
            if (pane.hoveredIndex === rowIndex)
              pane.clearHover()
          }
          onActivated: function (rowIndex, key) {
            pane.rowActivated(rowIndex, key)
          }
        }
      }
    }

    Item {
      id: preview
      width: parent.width - Math.round(parent.width * 0.48)
      height: parent.height
      clip: true

      ClipboardPreview {
        anchors.fill: parent
        firstLineTop: pane.firstLabelCapTop
        masked: pane.masked
        secretHint: "SPACE TO REVEAL"
        secretExpiry: {
          var left = pane.activeRow ? ClipboardLogic.secretExpiryText(pane.history[pane.activeRow.historyIndex], pane.nowMs, pane.secretTtlMs) : ""
          return left
        }
        textValue: !pane.activeRow ? "" : (pane.activeRow.secret ? ClipboardLogic.fullText(pane.history[pane.activeRow.historyIndex]) : pane.activeRow.fullText)
        imageSource: pane.activeRow ? pane.activeRow.previewImage : ""
        colourText: pane.activeRow ? pane.activeRow.colour : ""
        swatch: pane.activeRow ? pane.activeRow.swatch : ""
        isCode: !!pane.activeRow && pane.activeRow.kind === "code"
        contentMargin: pane.contentMargin
        fontFamily: pane.fontFamily
        foreground: pane.foreground
        borderColor: pane.borderColor
        cornerRadius: pane.cornerRadius
      }
    }
  }

  // The pane's own gate, used when the window shares none (tests).
  PointerMoveGate {
    id: ownGate
    referenceItem: pane
  }

  Aranea.EmptyState {
    anchors.fill: parent
    visible: !pane.model || pane.model.count === 0
    icon: String.fromCodePoint(0xf014c)
    message: pane.emptyMessage
    fontFamily: pane.fontFamily
    iconFontFamily: Aranea.Typography.iconFamily
    iconColor: pane.selectedText
    foreground: pane.foreground
  }
}
