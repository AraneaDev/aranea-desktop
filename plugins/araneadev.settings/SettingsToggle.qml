// Keyboard-capable Filament switch using owner-observed values.
import QtQuick
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Aranea.FilamentSwitch {
  id: toggle
  // Last real movement accepted over this control in host coordinates.
  property real pointerMovedAt: 0
  // Host layout stamp invalidates movement accepted before a shift or scroll.
  readonly property real layoutStamp: pointerGate ? Number(pointerGate.layoutChangedAt) || 0 : 0
  // Gate used when a settings switch is hosted without a shared pointer owner.
  readonly property var movementGate: pointerGate || ownGate
  // Apply the existing shared settling rule to pointer activation only.
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      movedAt: pointerMovedAt,
      layoutChangedAt: layoutStamp
    })
  }
  clickGate: toggle
  onLayoutStampChanged: toggle.pointerMovedAt = 0
  PointerMoveGate {
    id: ownGate
    referenceItem: toggle.Window.contentItem
  }
  HoverHandler {
    id: hover
    onHoveredChanged: if (!hovered) {
      toggle.pointerMovedAt = 0
      ownGate.reset()
    }
    onPointChanged: if (hover.hovered && toggle.movementGate.moved(toggle, {
      x: hover.point.position.x,
      y: hover.point.position.y
    }))
      toggle.pointerMovedAt = Date.now()
  }
  activeFocusOnTab: enabled && visible
  hasCursor: activeFocus
  Accessible.role: Accessible.CheckBox
  Accessible.checked: checked
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      activate()
      event.accepted = true
    }
  }
}
