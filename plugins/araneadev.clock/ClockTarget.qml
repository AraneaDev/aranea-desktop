// A pointer target in the Aranea Clock dropdown (a chevron, the W heading,
// Back to today, the week start label, the year and life bars): reports a
// real pointer move onto it through the dropdown's PointerMoveGate (hot,
// for its hover tint and tooltip), and settles its clicks: a click within
// 300 ms of the target being built, or of the dropdown's layout shifting
// (pointerGate.layoutChangedAt), is refused unless the pointer has really
// moved onto it since. It draws no outline: the calendar has no cursor.
import QtQuick
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Item {
  id: target

  // The dropdown's PointerMoveGate (qs.Ui), carrying layoutChangedAt; null
  // never lights and settles only on the target's age.
  property var pointerGate: null
  // When the target was built (Date.now()).
  property real createdAt: 0
  // When the gate last accepted a real pointer move onto the target
  // (Date.now()), 0 for never.
  property real pointerMovedAt: 0
  // Whether the pointer really moved onto the target and is still on it.
  property bool hot: false

  // Whether a pointer click may act on this target
  // (ClickSettle.clickSettled over its age, the dropdown's last layout
  // shift and the last real pointer move).
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: target.createdAt,
      movedAt: target.pointerMovedAt,
      layoutChangedAt: target.pointerGate ? Number(target.pointerGate.layoutChangedAt) || 0 : 0
    })
  }

  Component.onCompleted: target.createdAt = Date.now()

  HoverHandler {
    id: hover
    onHoveredChanged: if (!hover.hovered)
      target.hot = false
    onPointChanged: if (target.pointerGate && hover.hovered && target.pointerGate.moved(target, {
      x: hover.point.position.x,
      y: hover.point.position.y
    })) {
      target.pointerMovedAt = Date.now()
      target.hot = true
    }
  }
}
