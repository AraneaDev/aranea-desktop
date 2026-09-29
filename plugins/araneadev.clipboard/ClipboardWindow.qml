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
import "components"

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
    resultPane.reveal(index)
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

    Aranea.OverlayChrome {
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

      ClipboardResultsPane {
        id: resultPane
        anchors.fill: parent
        model: panel.root.displayModel
        history: panel.root.history
        nowMs: panel.root.nowMs
        secretTtlMs: panel.root.secretTtlMs
        selectedIndex: panel.root.selectedIndex
        cursorActive: panel.root.cursorActive
        revealedIndex: panel.root.revealedIndex
        rowHeight: panel.root.rowHeight
        contentMargin: panel.root.contentMargin
        fontFamily: panel.root.fontFamily
        foreground: panel.root.foreground
        selectedText: panel.root.selectedText
        selectedBackground: panel.root.selectedBackground
        borderColor: panel.root.border
        cornerRadius: panel.root.cornerRadius
        emptyMessage: panel.root.history.length === 0 ? "Clipboard is empty" : "No matches for “" + panel.root.filterText + "”"
        kindGlyph: panel.root.kindGlyph
        onPointerMoved: function (rowIndex, item, mouse) {
          panel.root.selectFromPointer(rowIndex, item, mouse)
        }
        onActivated: function (rowIndex) {
          panel.root.cursorActive = true
          panel.root.selectedIndex = rowIndex
          panel.root.activateIndex(rowIndex)
        }
      }
    }
  }
}
