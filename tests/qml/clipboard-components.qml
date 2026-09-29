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

  ListModel {
    id: clipboardRows
    ListElement {
      historyIndex: 0
      kind: "text"
      title: "hello"
      detail: "now"
      previewImage: ""
      colour: ""
      swatch: ""
      pinned: false
      secret: false
      fullText: "hello"
      section: "recent"
    }
  }

  ClipboardComponents.ClipboardResultsPane {
    id: results
    width: 640
    height: 320
    model: clipboardRows
    history: [
      {
        text: "hello"
      }
    ]
    selectedIndex: 0
    cursorActive: true
  }

  Component.onCompleted: {
    t.equal(row.index, 2, "clipboard rows expose their model index")
    t.equal(row.title, "hello", "clipboard rows expose their title")
    t.equal(row.pinned, true, "clipboard rows expose pinned state")
    t.equal(results.selectedIndex, 0, "clipboard result panes expose selection state")
    t.equal(results.cursorActive, true, "clipboard result panes expose cursor state")
    t.done()
  }
}
