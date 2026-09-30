// Production KeyboardPanel host for the update center.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Aranea.KeyboardPanelFrame {
  id: host
  // Current update status rendered by the panel.
  property var status: ({})
  // Keyboard-selected action index.
  property int cursorIndex: 0
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
  onTabRequested: function (direction) {
    host.owner.switchPanel(direction)
  }
  onMoveRequested: function (dx, dy) {
    if (dy !== 0)
      host.cursorIndex = (host.cursorIndex + dy + 2) % 2
  }
  onTextKey: function (text) {
    if (text === "r" || text === "R")
      host.refresh()
  }
  onActivateRequested: host.cursorIndex === 0 ? host.openUpdater() : host.refresh()
  UpdatePanel {
    id: content
    anchors.fill: parent
    status: host.status
    cursorIndex: host.cursorIndex
    // The one true cap: the card's own maximum (Style.space(520) or a
    // smaller screen, whichever binds) minus the padding and border the
    // card always reserves around the content, so a capped panel can never
    // exceed the space contentHolder actually gives it.
    maxContentHeight: Math.max(0, Math.min(Style.space(520), host.availableCardHeight) - host.verticalContentInset)
    onOpenUpdater: host.openUpdater()
    onRefresh: host.refresh()
  }
}
