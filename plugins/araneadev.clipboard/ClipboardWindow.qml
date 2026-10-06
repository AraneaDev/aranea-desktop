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

        if (panel.root.handleKey(event))
          event.accepted = true
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
      refined: true
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
        cursorActive: panel.root.outlineShown
        pointerGate: pointerGate
        layoutChangedAt: panel.root.layoutChangedAt
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
        onRowActivated: function (rowIndex, key) {
          panel.root.activateKey(rowIndex, key)
        }
      }
    }
  }
}
