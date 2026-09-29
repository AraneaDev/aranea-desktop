// Result grid for the emoji picker. Selection and insertion remain owned by Emojis.qml.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

GridView {
  id: grid

  // Current search text, used by the empty state.
  property string filterText: ""
  // Index selected in the result model.
  property int selectedIndex: -1
  // Whether keyboard selection styling is active.
  property bool cursorActive: false
  // Whether selection currently belongs to the recents flow.
  property bool inRecents: false
  // Font used by result cells and the empty state.
  property string fontFamily: Style.font.menuFamily
  // Corner radius passed to result cells.
  property int cornerRadius: Style.cornerRadius
  // Fill used for the selected result cell.
  property color selectedBackground: Color.menu.selectedBackground
  // Border and glyph color used for the selected result cell.
  property color selectedText: Color.menu.selectedText
  // Foreground used by the empty-state message.
  property color foreground: Color.menu.text
  // Emitted when a result is activated.
  signal picked(string emoji, int index)

  clip: true
  boundsBehavior: Flickable.StopAtBounds
  cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)

  delegate: EmojiCell {
    required property int index
    required property string emoji

    glyph: emoji
    hasCursor: grid.cursorActive && !grid.inRecents && index === grid.selectedIndex
    fontFamily: grid.fontFamily
    cellWidth: grid.cellWidth
    cellHeight: grid.cellHeight
    cornerRadius: grid.cornerRadius
    selectedBackground: grid.selectedBackground
    selectedText: grid.selectedText
    onPicked: grid.picked(emoji, index)
  }

  Aranea.EmptyState {
    anchors.fill: parent
    visible: grid.count === 0
    icon: "󰈉"
    message: "No matches for “" + grid.filterText + "”"
    fontFamily: grid.fontFamily
    iconColor: grid.selectedText
    foreground: grid.foreground
  }
}
