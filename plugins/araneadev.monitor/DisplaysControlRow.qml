// A keyboard-reachable control row in the Aranea Displays dropdown (a
// slider, the night light or the keyboard light): draws the keyboard
// cursor outline, reports a real pointer move onto it through the
// dropdown's PointerMoveGate, and settles clicks for the controls it hosts
// (their clickGate): a click within 300 ms of the row being built, or of
// the dropdown's layout shifting (pointerGate.layoutChangedAt), is refused
// unless the pointer has really moved onto the row since.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Item {
  id: row

  // Whether the keyboard cursor is on this row.
  property bool hasCursor: false
  // The dropdown's PointerMoveGate (qs.Ui), carrying layoutChangedAt; null
  // reports no hover and settles only on the row's age.
  property var pointerGate: null
  // When the row was built (Date.now()).
  property real createdAt: 0
  // When the gate last accepted a real pointer move onto the row
  // (Date.now()), 0 for never.
  property real pointerMovedAt: 0
  // The row's content (a caption, a slider, a switch).
  default property alias content: body.data

  // Emitted when the pointer really moves onto the row (through the gate).
  signal hoveredMoved

  // Whether a pointer click may act on a control in this row
  // (ClickSettle.clickSettled over the row's age, the dropdown's last
  // layout shift and the last real pointer move).
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: row.createdAt,
      movedAt: row.pointerMovedAt,
      layoutChangedAt: row.pointerGate ? Number(row.pointerGate.layoutChangedAt) || 0 : 0
    })
  }

  Component.onCompleted: row.createdAt = Date.now()

  Rectangle {
    // The keyboard cursor outline.
    objectName: "cursorOutline"
    anchors.fill: parent
    anchors.margins: -Style.space(3)
    color: row.hasCursor ? Util.alpha(Aranea.DesignTokens.accent, 0.08) : "transparent"
    border.width: row.hasCursor ? 1 : 0
    border.color: Aranea.DesignTokens.accent
  }
  Item {
    id: body
    anchors.fill: parent
  }
  HoverHandler {
    id: hover
    onPointChanged: if (row.pointerGate && hover.hovered && row.pointerGate.moved(row, {
      x: hover.point.position.x,
      y: hover.point.position.y
    })) {
      row.pointerMovedAt = Date.now()
      row.hoveredMoved()
    }
  }
}
