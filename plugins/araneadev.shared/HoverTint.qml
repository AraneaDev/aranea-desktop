// The hover fill of a clickable element: it fills its parent with
// DesignTokens.hoverFill once the pointer has really moved over the parent,
// never because the parent slid under a still pointer. Its own
// PointerMoveGate measures in window coordinates and resets when the
// pointer leaves, so the first sample after entering never lights it. The
// fill drops when the pointer leaves or the host's layout shifts
// (pointerGate.layoutChangedAt). Purely visual: it never moves a keyboard
// cursor or the outline. Declare it first among the parent's children so it
// sits behind the content. Watching the hover takes it from the items
// behind the parent (a row's own MouseArea), so a control sitting on a row
// that lights itself turns its tint off (active: false).
import QtQuick
import qs.Ui

Rectangle {
  id: tint

  // Whether the parent can be clicked now; false never lights the fill
  // and stops watching the hover, so it reaches the items behind.
  property bool active: true
  // Optional host PointerMoveGate (qs.Ui) carrying layoutChangedAt: a
  // layout shift drops the fill. Only its stamp is read.
  property var pointerGate: null
  // Whether the pointer really moved onto the parent and is still over it,
  // with the layout unchanged since.
  property bool pointerHovered: false
  // Whether the fill shows.
  readonly property bool lit: pointerHovered && active
  // The host's last layout shift; a change drops the fill.
  readonly property real layoutStamp: pointerGate ? Number(pointerGate.layoutChangedAt) || 0 : 0

  objectName: "hoverFill"
  anchors.fill: parent
  color: DesignTokens.hoverFill
  visible: tint.lit
  onLayoutStampChanged: tint.pointerHovered = false

  // Tells real pointer moves from the parent moving under a still pointer.
  PointerMoveGate {
    id: gate
    referenceItem: tint.Window.contentItem
  }
  // Watches the parent's hover; passive, so the parent's own MouseArea or
  // handlers still get every event.
  HoverHandler {
    id: hover
    parent: tint.parent
    enabled: tint.active
    onHoveredChanged: if (!hovered) {
      tint.pointerHovered = false
      gate.reset()
    }
    onPointChanged: if (hover.hovered && gate.moved(hover.parent, {
      x: hover.point.position.x,
      y: hover.point.position.y
    }))
      tint.pointerHovered = true
  }
}
