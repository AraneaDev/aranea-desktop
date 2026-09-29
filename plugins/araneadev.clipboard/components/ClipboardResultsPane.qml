// Clipboard result list, selected preview, and empty state.
// Keyboard policy and clipboard actions remain owned by ClipboardWindow.qml.
// qmllint disable missing-property unqualified

import QtQuick
import qs.Commons
import "../ClipboardLogic.js" as ClipboardLogic

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
  // Whether keyboard selection is active.
  property bool cursorActive: false
  // Index of a revealed secret, or -1 while masked.
  property int revealedIndex: -1
  // Row height supplied by the clipboard window.
  property int rowHeight: Style.space(50)
  // Content margin shared with the containing card.
  property int contentMargin: Style.spacing.panelPadding
  // Font family used by rows and the preview.
  property string fontFamily: Style.font.menuFamily
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

  // Emitted when pointer movement should update clipboard selection.
  signal pointerMoved(int rowIndex, var item, var mouse)
  // Emitted when a row is activated.
  signal activated(int rowIndex)

  // Scroll the selected result into view.
  function reveal(index: int): void {
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  // Currently selected row projected from the display model.
  readonly property var activeRow: model && model.count > 0 && selectedIndex >= 0 && selectedIndex < model.count ? model.get(selectedIndex) : null
  // Whether the selected secret remains hidden in the preview.
  readonly property bool masked: !!activeRow && activeRow.secret && revealedIndex !== selectedIndex

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

        section.property: "section"
        section.delegate: Item {
          required property string section
          width: ListView.view.width
          height: Style.space(26)

          Rectangle {
            anchors.left: sectionCaption.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: sectionCaption.verticalCenter
            height: 1
            color: Util.alpha(pane.foreground, 0.10)
          }

          Text {
            id: sectionCaption
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(4)
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
          hasCursor: pane.cursorActive && index === pane.selectedIndex
          width: ListView.view.width
          height: pane.rowHeight
          glyph: pane.kindGlyph(kind)
          fontFamily: pane.fontFamily
          foreground: pane.foreground
          selectedText: pane.selectedText
          selectedBackground: pane.selectedBackground
          cornerRadius: pane.cornerRadius
          onPointerMoved: function (rowIndex, item, mouse) {
            pane.pointerMoved(rowIndex, item, mouse)
          }
          onActivated: function (rowIndex) {
            pane.activated(rowIndex)
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

  Column {
    anchors.centerIn: parent
    spacing: Style.space(8)
    visible: !pane.model || pane.model.count === 0

    Text {
      text: "󰅌"
      color: pane.selectedText
      opacity: 0.8
      font.family: pane.fontFamily
      font.pixelSize: Style.font.displayLarge
      horizontalAlignment: Text.AlignHCenter
      width: parent.width
    }

    Text {
      textFormat: Text.PlainText
      text: pane.emptyMessage
      color: pane.foreground
      opacity: 0.7
      font.family: pane.fontFamily
      font.pixelSize: Style.font.title
      horizontalAlignment: Text.AlignHCenter
      width: parent.width
    }
  }
}
