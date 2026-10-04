// Emoji cell. Selection and insertion remain owned by Emojis.qml. Two
// separate highlights: the mint outline marks the keyboard cursor (Enter's
// target, hasCursor); the hover fill shows on the cell the pointer really
// moved onto (hovered, set by the owner). A click is keyed by the cell's
// emoji and settled (ClickSettle).
// qmllint disable missing-property
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Rectangle {
  id: cell

  // Emoji glyph rendered in the cell; clicks are keyed by it.
  property string glyph: ""
  // Whether the keyboard cursor (the mint outline) is on this cell.
  property bool hasCursor: false
  // Whether the pointer really moved onto this cell and it still holds the
  // same emoji (the hover fill); set by the owner.
  property bool hovered: false
  // The gate that tells real pointer moves from cells moving under a still
  // pointer (PointerMoveGate), or null to ignore hover.
  property var pointerGate: null
  // When the cells last changed or scrolled under a still pointer
  // (Date.now()), 0 for never.
  property real layoutChangedAt: 0
  // When this cell was built (Date.now()).
  property real createdAt: 0
  // When the gate last accepted a real pointer move onto this cell.
  property real pointerMovedAt: 0
  // The emoji under the last press, compared on release.
  property string pressedKey: ""
  // Font used for the emoji glyph.
  property string fontFamily: Style.font.menuFamily
  // Cell width used by the picker grid.
  property int cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  // Cell height used by the picker grid.
  property int cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  // Corner radius for the cell surface.
  property int cornerRadius: Style.cornerRadius
  // Fill of the hovered cell.
  property color selectedBackground: Color.menu.selectedBackground
  // Accent colour of the picker (kept for callers; the cursor is the mint outline).
  property color selectedText: Color.menu.selectedText
  // Emitted when the pointer really moved onto the cell holding KEY.
  signal hoverMoved(string key)
  // Emitted when the pointer leaves the cell.
  signal hoverLeft
  // Emitted for a settled click on the cell that still holds KEY on release.
  signal picked(string key)

  // Whether a pointer click may act on this cell (ClickSettle).
  function clickSettled(): bool {
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: cell.createdAt,
      movedAt: cell.pointerMovedAt,
      layoutChangedAt: cell.layoutChangedAt
    })
  }

  Component.onCompleted: cell.createdAt = Date.now()

  width: cellWidth
  height: cellHeight
  radius: cornerRadius
  color: hovered ? selectedBackground : "transparent"

  Rectangle {
    // The keyboard cursor outline (mint): Enter's target.
    objectName: "cursorOutline"
    anchors.fill: parent
    radius: cell.cornerRadius
    visible: cell.hasCursor
    color: Util.alpha(Aranea.DesignTokens.accent, 0.08)
    border.width: 1
    border.color: Aranea.DesignTokens.accent
  }

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: cell.glyph
    font.family: cell.fontFamily
    font.pixelSize: Style.font.display
  }

  MouseArea {
    id: cellArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // Hover fills the cell and feeds the settle rule; it never moves the
    // keyboard cursor.
    onPositionChanged: function (mouse) {
      if (cell.pointerGate && cell.pointerGate.moved(cellArea, mouse)) {
        cell.pointerMovedAt = Date.now()
        cell.hoverMoved(cell.glyph)
      }
    }
    onExited: cell.hoverLeft()
    onPressed: cell.pressedKey = cell.glyph
    onClicked: {
      var key = cell.pressedKey
      cell.pressedKey = ""
      if (!key || key !== cell.glyph || !cell.clickSettled())
        return
      cell.picked(key)
    }
  }
}
