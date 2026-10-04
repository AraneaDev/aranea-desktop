// Window of the Aranea emoji picker: the overlay PanelWindow with the card,
// search, RECENT row and grid. Emojis.qml (the plugin entry, which holds all
// state and logic) creates it and passes itself as `root`, so the bindings
// below read the picker's state as panel.root.*; tests leave it out.

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Ui
import "../araneadev.shared" as Aranea

PanelWindow {
  id: panel

  // The emoji picker (Emojis.qml) this window draws; set at creation.
  required property var root

  // Gives the picker's key handler the keyboard focus.
  function focusKeys(): void {
    keyCatcher.forceActiveFocus()
  }

  // Scrolls grid cell INDEX into view.
  function reveal(index: int): void {
    pickerContent.reveal(index)
  }

  // Makes the pointer ignore hover until it really moves.
  function disarmPointer(): void {
    pointerGate.reset()
  }

  // Height of the result grid, for page moves.
  readonly property real resultHeight: pickerContent.resultHeight

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
  WlrLayershell.namespace: "omarchy-emojis"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  Rectangle {
    anchors.fill: parent
    color: panel.root.scrim
  }

  MouseArea {
    anchors.fill: parent
    onClicked: panel.root.dismiss()
  }

  Aranea.SurfaceCard {
    id: card
    width: panel.root.cardWidth
    height: panel.root.cardHeight
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
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        if (panel.root.handleKey(event))
          event.accepted = true
      }
    }

    EmojiPickerContent {
      id: pickerContent
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      filterText: panel.root.filterText
      resultModel: panel.root.displayModel
      recentModel: panel.root.recents
      showRecents: panel.root.showRecents
      selectedIndex: panel.root.selectedIndex
      cursorActive: panel.root.outlineShown
      pointerGate: pointerGate
      layoutChangedAt: panel.root.layoutChangedAt
      inRecents: panel.root.inRecents
      recentIndex: panel.root.recentIndex
      selectedEmoji: panel.root.selectedEmoji
      selectedName: panel.root.selectedName
      hintText: panel.root.opened ? panel.root.hintText() : ""
      fontFamily: panel.root.fontFamily
      foreground: panel.root.foreground
      cellWidth: panel.root.cellWidth
      cellHeight: panel.root.cellHeight
      columns: panel.root.columns
      cornerRadius: panel.root.cornerRadius
      selectedBackground: panel.root.selectedBackground
      selectedText: panel.root.selectedText
      onRecentPicked: function (index, key) {
        panel.root.activateRecentKey(index, key)
      }
      onResultPicked: function (index, key) {
        panel.root.activateKey(index, key)
      }
    }
  }
}
