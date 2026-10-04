// Production KeyboardPanel host for the update center.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/CursorLogic.js" as CursorLogic
import "UpdateLogic.js" as UpdateLogic

Aranea.KeyboardPanelFrame {
  id: host
  // Current update status rendered by the panel.
  property var status: ({})
  // Whether Service is running a check right now.
  property bool checking: false
  // Keyboard-selected pill index: 0 "Open updater", 1 "Refresh".
  property int cursorIndex: 0
  // True while the keyboard drives the cursor; any pointer use clears it.
  // The mint outline shows only then, and the first key only reveals it.
  property bool keyboardCursor: false
  // Request the updater action.
  signal openUpdater
  // Request a status refresh.
  signal refresh
  // Wait for the layer-shell anchor geometry before revealing the card; opening
  // on the first zero-sized frame makes cardOrigin visibly settle sideways.
  open: owner ? owner.opened && anchorWindow !== null && screenW > 0 : false
  centerOnBar: true
  gap: Style.gapsOut
  contentWidth: fittedContentWidth(Style.space(380))
  contentHeight: fittedContentHeight(content.implicitHeight, Style.space(520))
  onCloseRequested: host.owner.close()
  // A fresh open starts with the cursor hidden; the first key reveals it.
  onOpenChanged: {
    content.disarmPointer()
    host.cursorIndex = 0
    host.keyboardCursor = false
  }
  onTabRequested: function (direction) {
    content.disarmPointer()
    host.owner.switchPanel(direction)
  }
  onMoveRequested: function (dx, dy) {
    content.disarmPointer()
    if (dy !== 0) {
      var next = UpdateLogic.moveCursor(host.cursorIndex, host.keyboardCursor, dy)
      host.cursorIndex = next.index
      host.keyboardCursor = next.keyboardCursor
    }
  }
  onTextKey: function (text) {
    content.disarmPointer()
    if ((text === "r" || text === "R") && !host.checking)
      host.refresh()
  }
  onActivateRequested: {
    content.disarmPointer()
    var intent = CursorLogic.pressIntent(true, host.keyboardCursor)
    if (intent === "reveal") {
      host.keyboardCursor = true
      return
    }
    if (host.cursorIndex === 0)
      host.openUpdater()
    else if (!host.checking)
      host.refresh()
  }
  UpdatePanel {
    id: content
    anchors.fill: parent
    status: host.status
    checking: host.checking
    cursorIndex: host.cursorIndex
    keyboardCursor: host.keyboardCursor
    // The one true cap: the card's own maximum (Style.space(520) or a
    // smaller screen, whichever binds) minus the padding and border the
    // card always reserves around the content, so a capped panel can never
    // exceed the space contentHolder actually gives it.
    maxContentHeight: Math.max(0, Math.min(Style.space(520), host.availableCardHeight) - host.verticalContentInset)
    onOpenUpdater: host.openUpdater()
    onRefresh: host.refresh()
  }
}
