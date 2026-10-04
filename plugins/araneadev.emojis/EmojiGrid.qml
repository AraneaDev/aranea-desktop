// Result grid for the emoji picker. Selection and insertion remain owned by
// Emojis.qml. The mint outline marks the keyboard cursor; hover fills the
// cell the pointer really moved onto (PointerMoveGate) and clears when the
// cells change or scroll under the pointer. Clicks are keyed by emoji and
// settled against layoutChangedAt and the grid's own scroll stamp.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

GridView {
  id: grid

  // Current search text, used by the empty state.
  property string filterText: ""
  // Index selected in the result model.
  property int selectedIndex: -1
  // Whether the keyboard outline shows (on selectedIndex unless inRecents).
  property bool cursorActive: false
  // Whether selection currently belongs to the recents flow.
  property bool inRecents: false
  // Font used by result cells and the empty state.
  property string fontFamily: Style.font.menuFamily
  // Corner radius passed to result cells.
  property int cornerRadius: Style.cornerRadius
  // Fill used for the hovered result cell.
  property color selectedBackground: Color.menu.selectedBackground
  // Accent colour of the picker (the empty-state icon).
  property color selectedText: Color.menu.selectedText
  // Foreground used by the empty-state message.
  property color foreground: Color.menu.text
  // The gate that tells real pointer moves from cells moving under a still
  // pointer; the window shares its own, else the grid's.
  property var pointerGate: ownGate
  // When the cells last changed under a still pointer (Emojis.qml's
  // layoutChangedAt), 0 for never.
  property real layoutChangedAt: 0
  // When the grid last scrolled (Date.now()), 0 for never.
  property real scrolledAt: 0
  // The cell the pointer really moved onto (hover fill), -1 for none.
  property int hoveredIndex: -1
  // The emoji that cell held when hovered; the fill shows only while the
  // cell still holds it.
  property string hoveredKey: ""
  // Emitted for a settled click on cell INDEX that still holds KEY (its
  // emoji) on release.
  signal picked(int index, string key)

  // Drops the hover fill: the cells moved or changed under the pointer.
  function clearHover(): void {
    grid.hoveredIndex = -1
    grid.hoveredKey = ""
  }

  onLayoutChangedAtChanged: grid.clearHover()
  onContentYChanged: {
    grid.scrolledAt = Date.now()
    grid.clearHover()
  }

  clip: true
  boundsBehavior: Flickable.StopAtBounds
  cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)

  delegate: EmojiCell {
    required property int index
    required property string emoji

    objectName: "emojiCell"
    glyph: emoji
    hasCursor: grid.cursorActive && !grid.inRecents && index === grid.selectedIndex
    hovered: grid.hoveredIndex === index && grid.hoveredKey === emoji
    pointerGate: grid.pointerGate
    layoutChangedAt: Math.max(grid.layoutChangedAt, grid.scrolledAt)
    fontFamily: grid.fontFamily
    cellWidth: grid.cellWidth
    cellHeight: grid.cellHeight
    cornerRadius: grid.cornerRadius
    selectedBackground: grid.selectedBackground
    selectedText: grid.selectedText
    onHoverMoved: function (key) {
      grid.hoveredIndex = index
      grid.hoveredKey = key
    }
    onHoverLeft: if (grid.hoveredIndex === index)
      grid.clearHover()
    onPicked: function (key) {
      grid.picked(index, key)
    }
  }

  // The grid's own gate, used when the window shares none (tests).
  PointerMoveGate {
    id: ownGate
    referenceItem: grid
  }

  Aranea.EmptyState {
    anchors.fill: parent
    visible: grid.count === 0
    icon: String.fromCodePoint(0xf0209)
    message: "No matches for “" + grid.filterText + "”"
    fontFamily: grid.fontFamily
    iconColor: grid.selectedText
    foreground: grid.foreground
  }
}
