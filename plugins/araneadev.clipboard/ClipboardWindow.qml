// Window of the Aranea clipboard picker: the overlay PanelWindow with the
// search, rows and preview. Clipboard.qml (the non-visual plugin entry, which
// holds all state and logic) creates it and passes itself as `root`, so the
// bindings below read the picker's state as panel.root.*; tests leave it out.

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "ClipboardLogic.js" as ClipboardLogic

PanelWindow {
  id: panel

  // The clipboard entry (Clipboard.qml) this window draws; set at creation.
  required property var root
  // Card width: up to 875 scaled px, inside the screen gaps.
  property int cardWidth: Math.min(Style.space(875), panel.width - Style.gapsOut * 2)
  // Card height: up to 600 scaled px, inside the screen gaps.
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)

  // Gives the picker's key handler the keyboard focus.
  function focusKeys(): void {
    keyCatcher.forceActiveFocus()
  }

  // Scrolls the row at index into view.
  function reveal(index: int): void {
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  // Makes the mouse ignore hover until it really moves.
  function disarmPointer(): void {
    pointerGate.reset()
  }

  // Whether the pointer really moved over item (see PointerMoveGate).
  function pointerMoved(item, mouse): bool {
    return pointerGate.moved(item, mouse)
  }

  // Preselects "cancel" in the clear-history confirmation.
  function resetClearConfirm(): void {
    clearConfirm.selectedIndex = 1
  }

  // Plays the entrance animation when the picker opens (unless motion is off).
  Connections {
    target: panel.root
    function onOpenedChanged() {
      if (panel.root.opened && panel.root.motionEnabled)
        openAnimation.restart()
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  ParallelAnimation {
    id: openAnimation
    NumberAnimation {
      target: card
      property: "opacity"
      from: 0
      to: 1
      duration: 180
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: card
      property: "scale"
      from: 0.97
      to: 1
      duration: 180
      easing.type: Easing.OutCubic
    }
  }

  visible: panel.root.opened
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-clipboard"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  Rectangle {
    anchors.fill: parent
    color: panel.root.scrim
  }

  MouseArea {
    anchors.fill: parent
    onClicked: panel.root.close()
  }

  Aranea.SurfaceCard {
    id: card
    width: panel.cardWidth
    height: panel.cardHeight
    cornerRadius: panel.root.cornerRadius
    anchors.centerIn: parent
    fillColor: panel.root.background
    borderSpecOverride: panel.root.borderSpec
    contentPadding: panel.root.contentMargin

    MouseArea {
      anchors.fill: parent
      onClicked: {}
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      z: panel.root.clearConfirmOpen ? 20 : 0
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        if (panel.root.clearConfirmOpen) {
          if (clearConfirm.handleKey(event))
            event.accepted = true
          return
        }

        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        if (event.key === Qt.Key_Escape) {
          if (panel.root.filterText)
            panel.root.setFilter("")
          else
            panel.root.close()
          event.accepted = true
        } else if (ctrl && event.key === Qt.Key_P) {
          panel.root.togglePinnedIndex(panel.root.selectedIndex)
          event.accepted = true
        } else if (ctrl && event.key === Qt.Key_S) {
          panel.root.toggleSecretIndex(panel.root.selectedIndex)
          event.accepted = true
        } else if (event.key === Qt.Key_Delete) {
          if (ctrl && (event.modifiers & Qt.ShiftModifier))
            panel.root.requestClearHistory()
          else
            panel.root.removeDisplayIndex(panel.root.selectedIndex)
          event.accepted = true
        } else if (event.key === Qt.Key_Space && !panel.root.filterText && panel.root.displayModel.count > 0 && panel.root.displayModel.get(panel.root.selectedIndex).secret) {
          panel.root.revealIndex(panel.root.selectedIndex)
          event.accepted = true
        } else if (Util.editsFilter(event, panel.root.filterText)) {
          panel.root.setFilter(Util.editedFilter(event, panel.root.filterText))
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          panel.root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          panel.root.select(1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          panel.root.select(-6)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          panel.root.select(6)
          event.accepted = true
        } else if (event.key === Qt.Key_Home) {
          panel.root.selectAbsolute(0)
          event.accepted = true
        } else if (event.key === Qt.Key_End) {
          panel.root.selectAbsolute(panel.root.displayModel.count - 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (panel.root.cursorActive && (event.modifiers & Qt.AltModifier))
            panel.root.openIndex(panel.root.selectedIndex)
          else if (panel.root.cursorActive && (event.modifiers & Qt.ShiftModifier))
            panel.root.copyIndex(panel.root.selectedIndex)
          else if (panel.root.cursorActive)
            panel.root.activateIndex(panel.root.selectedIndex)
          else if (panel.root.displayModel.count > 0)
            panel.root.cursorActive = true
          event.accepted = true
        } else if (!ctrl && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
          panel.root.setFilter(panel.root.filterText + event.text)
          event.accepted = true
        }
      }

      ConfirmDialog {
        id: clearConfirm

        anchors.fill: parent
        opened: panel.root.clearConfirmOpen
        z: 10
        message: "Delete all unpinned clipboard items?"
        confirmText: "Delete"
        background: panel.root.background
        foreground: panel.root.foreground
        scrim: panel.root.scrim
        selectedBackground: panel.root.selectedBackground
        selectedText: panel.root.selectedText
        fontFamily: panel.root.fontFamily
        cornerRadius: panel.root.cornerRadius
        onCanceled: panel.root.cancelClearHistory()
        onConfirmed: panel.root.confirmClearHistory()
      }
    }

    OverlayChrome {
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      title: "CLIPBOARD"
      subtitle: "HISTORY // PASTE // PIN"
      counts: panel.root.history.length + " ITEMS" + (panel.root.pinnedCount > 0 ? "  ·  " + panel.root.pinnedCount + " 📌" : "")
      searchText: panel.root.filterText
      searchPlaceholder: "Search clipboard…"
      hints: panel.root.opened ? panel.root.hintText() : ""
      fontFamily: panel.root.fontFamily
      foreground: panel.root.foreground
      accent: panel.root.selectedText

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
            anchors.rightMargin: panel.root.contentMargin
            model: panel.root.displayModel
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.delegate: Item {
              required property string section
              width: ListView.view.width
              height: Style.space(26)
              // Hairline after the caption, as in the Aranea menu.
              Rectangle {
                anchors.left: sectionCaption.right
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: sectionCaption.verticalCenter
                height: 1
                color: Util.alpha(panel.root.foreground, 0.10)
              }
              Text {
                id: sectionCaption
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
                textFormat: Text.PlainText
                text: parent.section === "pinned" ? "PINNED" : "RECENT"
                color: Util.alpha(panel.root.foreground, 0.58)
                font.family: panel.root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
                font.letterSpacing: 0.20
              }
            }

            delegate: Rectangle {
              id: row
              required property int index
              required property string kind
              required property bool secret
              required property bool pinned
              required property string title
              required property string detail
              required property string previewImage
              required property string colour
              required property string swatch

              readonly property bool hasCursor: panel.root.cursorActive && index === panel.root.selectedIndex

              width: ListView.view.width
              height: panel.root.rowHeight
              radius: panel.root.cornerRadius
              color: hasCursor ? panel.root.selectedBackground : "transparent"

              Behavior on color {
                ColorAnimation {
                  duration: 120
                  easing.type: Easing.OutCubic
                }
              }

              // Mint rail on the selected row, as in the Aranea menu.
              Rectangle {
                visible: row.hasCursor
                width: Style.space(2)
                height: parent.height - Style.space(14)
                radius: Style.space(1)
                color: panel.root.selectedText
                opacity: 0.9
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                Item {
                  width: Style.space(22)
                  height: parent.height

                  Image {
                    visible: row.previewImage.length > 0
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.width
                    source: row.previewImage
                    sourceSize: Qt.size(44, 44)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                  }
                  Rectangle {
                    visible: row.swatch.length > 0
                    anchors.centerIn: parent
                    width: Style.space(14)
                    height: Style.space(14)
                    radius: Style.space(3)
                    color: row.swatch.length > 0 ? row.swatch : "transparent"
                    border.width: 1
                    border.color: Util.alpha(panel.root.foreground, 0.25)
                  }
                  Text {
                    visible: row.previewImage.length === 0 && row.colour.length === 0
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: row.secret ? "󰌾" : panel.root.kindGlyph(row.kind)
                    color: row.hasCursor ? panel.root.selectedText : Util.alpha(panel.root.foreground, 0.7)
                    font.family: panel.root.fontFamily
                    font.pixelSize: Style.font.icon
                  }
                }

                Text {
                  width: parent.width - Style.space(22) - detailText.width - parent.spacing * 2
                  height: parent.height
                  textFormat: Text.PlainText
                  text: row.title
                  color: row.hasCursor ? panel.root.selectedText : panel.root.foreground
                  font.family: panel.root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  wrapMode: Text.NoWrap
                  verticalAlignment: Text.AlignVCenter
                }

                Text {
                  id: detailText
                  height: parent.height
                  textFormat: Text.PlainText
                  text: (row.pinned ? "📌 " : "") + row.detail
                  color: Util.alpha(panel.root.foreground, 0.5)
                  font.family: panel.root.fontFamily
                  font.pixelSize: Style.font.caption
                  verticalAlignment: Text.AlignVCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function (mouse) {
                  panel.root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  panel.root.cursorActive = true
                  panel.root.selectedIndex = row.index
                  panel.root.activateIndex(row.index)
                }
              }
            }
          }
        }

        // Preview of the selected item.
        Item {
          id: preview
          width: parent.width - Math.round(parent.width * 0.48)
          height: parent.height
          clip: true

          property var activeRow: panel.root.displayModel.count > 0 && panel.root.selectedIndex >= 0 && panel.root.selectedIndex < panel.root.displayModel.count ? panel.root.displayModel.get(panel.root.selectedIndex) : null
          readonly property bool masked: !!activeRow && activeRow.secret && panel.root.revealedIndex !== panel.root.selectedIndex

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Style.normalBorderWidth
            color: Util.alpha(panel.root.border, 0.28)
          }

          // Secret: masked until revealed with Space for this selection.
          Column {
            visible: preview.masked
            anchors.left: parent.left
            anchors.leftMargin: panel.root.contentMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              text: "•••••••••••••••• · secret"
              color: panel.root.foreground
              font.family: panel.root.fontFamily
              font.pixelSize: Style.font.title
            }
            Text {
              textFormat: Text.PlainText
              text: {
                var left = preview.activeRow ? ClipboardLogic.secretExpiryText(panel.root.history[preview.activeRow.historyIndex], panel.root.nowMs, panel.root.secretTtlMs) : ""
                return "SPACE TO REVEAL" + (left ? "  ·  " + left.toUpperCase() : "")
              }
              color: Util.alpha(panel.root.foreground, 0.5)
              font.family: panel.root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 0.20
            }
          }

          // Colour swatch.
          Column {
            visible: !preview.masked && !!preview.activeRow && preview.activeRow.colour.length > 0
            anchors.left: parent.left
            anchors.leftMargin: panel.root.contentMargin
            anchors.top: parent.top
            spacing: Style.space(10)
            Rectangle {
              visible: !!preview.activeRow && preview.activeRow.swatch.length > 0
              width: Style.space(120)
              height: Style.space(80)
              radius: panel.root.cornerRadius
              color: preview.activeRow && preview.activeRow.swatch.length > 0 ? preview.activeRow.swatch : "transparent"
              border.width: 1
              border.color: Util.alpha(panel.root.foreground, 0.25)
            }
            Text {
              textFormat: Text.PlainText
              text: preview.activeRow ? preview.activeRow.colour : ""
              color: panel.root.foreground
              font.family: panel.root.fontFamily
              font.pixelSize: Style.font.title
            }
          }

          // Text, code, links and paths (revealed secrets fetch their text
          // from history by index: display rows never carry it).
          Text {
            visible: !preview.masked && !!preview.activeRow && !preview.activeRow.previewImage && preview.activeRow.colour.length === 0
            anchors.fill: parent
            anchors.leftMargin: panel.root.contentMargin
            textFormat: Text.PlainText
            text: !preview.activeRow ? "" : (preview.activeRow.secret ? ClipboardLogic.fullText(panel.root.history[preview.activeRow.historyIndex]) : preview.activeRow.fullText)
            color: panel.root.foreground
            font.family: preview.activeRow && preview.activeRow.kind === "code" ? "monospace" : panel.root.fontFamily
            font.pixelSize: preview.activeRow && preview.activeRow.kind === "code" ? Style.font.body : Style.font.title
            wrapMode: Text.WrapAnywhere
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
          }

          Image {
            visible: !preview.masked && !!preview.activeRow && preview.activeRow.previewImage.length > 0
            anchors.fill: parent
            anchors.leftMargin: panel.root.contentMargin
            source: preview.activeRow ? preview.activeRow.previewImage : ""
            fillMode: Image.PreserveAspectFit
            verticalAlignment: Image.AlignTop
            asynchronous: true
            smooth: true
          }
        }
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.space(8)
        visible: panel.root.displayModel.count === 0

        Text {
          text: "󰅌"
          color: panel.root.selectedText
          opacity: 0.8
          font.family: panel.root.fontFamily
          font.pixelSize: Style.font.displayLarge
          horizontalAlignment: Text.AlignHCenter
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: panel.root.history.length === 0 ? "Clipboard is empty" : "No matches for “" + panel.root.filterText + "”"
          color: panel.root.foreground
          opacity: 0.7
          font.family: panel.root.fontFamily
          font.pixelSize: Style.font.title
          horizontalAlignment: Text.AlignHCenter
          width: parent.width
        }
      }
    }
  }
}
