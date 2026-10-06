// Window of the Aranea menu: the full-screen overlay with the card, header,
// tiles and rows. Menu.qml (the non-visual plugin entry, which holds all
// state and logic) creates it and passes itself as `root`; tests leave it out.

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuLayout.js" as MenuLayout

PanelWindow {
  id: panel

  // The menu entry (Menu.qml) this window draws; set at creation.
  required property var root

  // Gives the menu's key handler the keyboard focus.
  function focusKeys(): void {
    card.focusKeys()
  }

  // Makes the mouse ignore hover until it really moves.
  function disarmPointer(): void {
    pointerGate.reset()
  }

  // Preselects "cancel" in the uninstall confirmation.
  function resetDeleteConfirm(): void {
    card.resetDeleteConfirm()
  }

  // Lets the uninstall confirmation handle a key; true when it did.
  function deleteConfirmHandleKey(event): bool {
    return card.deleteConfirmHandleKey(event)
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel, but never
  // at the cost of the cursor row itself (MenuLayout.revealContentY).
  function revealCursor(): void {
    if (panel.root.displayModel.count === 0)
      return
    var list = card.resultList
    list.positionViewAtIndex(panel.root.selectedIndex, ListView.Contain)
    var item = list.itemAtIndex(panel.root.selectedIndex)
    if (!item)
      return
    list.contentY = MenuLayout.revealContentY({
      index: panel.root.selectedIndex,
      count: panel.root.displayModel.count,
      contentY: list.contentY,
      originY: list.originY,
      contentHeight: list.contentHeight,
      viewHeight: list.height,
      itemY: item.y,
      itemHeight: item.height,
      reach: panel.root.style.rowPeek + panel.root.style.rowSpacing
    })
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  visible: panel.root.opened && panel.root.rowsLoaded
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-menu"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  // The card opens centered exactly as always. The first search keystroke
  // or submenu move freezes the top line where it currently sits; from
  // then on the card grows and shrinks downward instead of re-centering
  // on every resize, which made the menu jump around. The rows height is
  // frozen at the same moment, so the starting menu also caps how tall the
  // card may grow from there. Closing unfreezes both.
  property int cardTop: -1
  // Rows height frozen with cardTop (the starting menu's height), or -1.
  property int maxRowsHeight: -1
  // Top edge that centres the card vertically. Reads panel.root.screenHeight
  // (screen size, falling back to the window's own size, then a fixed
  // default; see MenuLayout.screenExtent) rather than this window's own
  // height, which layer-shell windows report as 0 until the compositor
  // configures them, the same class of bug the frozen-top fix above solves
  // for cardTop. The window is anchored to all edges with
  // ExclusionMode.Ignore, so once configured the two are equal.
  readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((panel.root.screenHeight - panel.root.cardHeight) / 2))
  // Where the card's top edge is: frozen, or centred until the first move.
  readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
  // Freezes the card top and rows height at their current values.
  function freezeCardTop() {
    if (visible && cardTop < 0) {
      cardTop = effectiveCardTop
      maxRowsHeight = panel.root.visibleRowsHeight
    }
  }
  onVisibleChanged: if (!visible) {
    cardTop = -1
    maxRowsHeight = -1
  }

  Rectangle {
    anchors.fill: parent
    color: panel.root.style.scrim
  }

  MouseArea {
    anchors.fill: parent
    onClicked: panel.root.cancel()
  }

  MenuSurface {
    id: card
    root: panel.root
    pointerGate: pointerGate
    width: panel.root.cardWidth
    height: Math.min(panel.root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
    anchors.horizontalCenter: parent.horizontalCenter
    y: panel.effectiveCardTop
  }
}
