// Behaviour contract for presentational clipboard components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.clipboard/components" as ClipboardComponents

ShellRoot {
  QmlTest {
    id: t
  }

  ClipboardComponents.ClipboardResultRow {
    id: row
    index: 2
    kind: "text"
    title: "hello"
    detail: "today"
    previewImage: ""
    colour: ""
    swatch: ""
    pinned: true
    secret: false
  }

  Component.onCompleted: {
    t.equal(row.index, 2, "clipboard rows expose their model index")
    t.equal(row.title, "hello", "clipboard rows expose their title")
    t.equal(row.pinned, true, "clipboard rows expose pinned state")
    t.done()
  }
}
