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

  Component.onCompleted: {
    t.equal(cell.glyph, "😀", "emoji cells expose their glyph")
    t.equal(cell.hasCursor, true, "emoji cells expose cursor state")
    t.check(cell.implicitWidth >= 0, "emoji cells have a valid implicit width")
    t.done()
  }
}
