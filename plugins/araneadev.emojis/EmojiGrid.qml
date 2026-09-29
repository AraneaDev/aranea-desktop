// Result grid for the emoji picker. Selection and insertion remain owned by Emojis.qml.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

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

  Column {
    anchors.centerIn: parent
    spacing: Style.space(8)
    visible: grid.count === 0

    Text {
      text: "󰈉"
      color: grid.selectedText
      opacity: 0.8
      font.family: grid.fontFamily
      font.pixelSize: Style.font.displayLarge
      horizontalAlignment: Text.AlignHCenter
      width: parent.width
    }

    Text {
      textFormat: Text.PlainText
      text: "No matches for “" + grid.filterText + "”"
      color: grid.foreground
      opacity: 0.7
      font.family: grid.fontFamily
      font.pixelSize: Style.font.title
      horizontalAlignment: Text.AlignHCenter
      width: parent.width
    }
  }
}
