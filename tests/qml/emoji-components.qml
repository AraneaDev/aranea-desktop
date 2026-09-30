// Isolated contracts for presentational emoji picker components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.emojis" as EmojiComponents

ShellRoot {
  QmlTest {
    id: t
  }

  EmojiComponents.EmojiCell {
    id: cell
    width: 48
    height: 48
    glyph: "😀"
    hasCursor: true
  }

  ListModel {
    id: emojiModel
    ListElement {
      emoji: "😀"
    }
  }

  EmojiComponents.EmojiGrid {
    id: grid
    width: 160
    height: 120
    model: emojiModel
    filterText: ""
    selectedIndex: 0
    cursorActive: true
  }

  EmojiComponents.EmojiPickerContent {
    id: content
    width: 320
    height: 240
    filterText: "sm"
    selectedName: "smile"
    hintText: "ENTER INSERT"
    showRecents: true
    recentModel: ["😀"]
    resultModel: emojiModel
    columns: 9
  }

  Component.onCompleted: {
    t.equal(cell.glyph, "😀", "emoji cells expose their glyph")
    t.equal(cell.hasCursor, true, "emoji cells expose cursor state")
    t.check(cell.implicitWidth >= 0, "emoji cells have a valid implicit width")
    t.equal(grid.selectedIndex, 0, "emoji grids expose selection state")
    t.equal(grid.filterText, "", "emoji grids expose filter state")
    t.equal(content.selectedName, "smile", "emoji picker content exposes selection labels")
    t.equal(content.showRecents, true, "emoji picker content exposes recents visibility")
    t.done()
  }
}
