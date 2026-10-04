// The clipboard picker's pointer rules, with real pointer events on the
// results pane in a window, wired to the real Clipboard.qml (its own window
// and capture off, a fixture history in the run directory) the way
// ClipboardWindow wires them: the mint outline marks Enter's target and
// shows from open on the first row; hover fills the row under the pointer
// after a real move but never moves the outline; the first Down moves it
// straight to the second row; typing keeps it on the top match so Enter
// pastes that match even with the pointer over another row; the empty
// state shows no outline and Enter does nothing there; a click is keyed by
// the row's entry id and refused when the row holds another entry on
// release; the rows changing stamps the layout (an equal rebuild does not)
// and a click inside the 300 ms settle window is refused; rows survive a
// rebuild. Never touches the real clipboard history.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.clipboard" as Clip
import "plugins/araneadev.clipboard/components" as ClipComponents

ShellRoot {
  id: shell

  // Commands the picker ran (argv arrays), newest last.
  property var ran: []
  // The row pressed before the results changed.
  property var pressedRow: null
  // The layout stamp a step compares against.
  property real stampBefore: 0
  // Time the test started, in ms; fixture timestamps are relative to it.
  readonly property real now: Date.now()

  QmlTest {
    id: t
  }

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  Clip.Clipboard {
    id: clip
    windowEnabled: false
    captureEnabled: false
    omarchyPath: "/opt/omarchy"
    // A throwaway file in the run directory, never the user's history.
    historyPath: Quickshell.env("XDG_RUNTIME_DIR") + "/clipboard-pointer-history.json"
    run: function (argv) {
      shell.ran = shell.ran.concat([argv])
    }
  }

  FloatingWindow {
    implicitWidth: 760
    implicitHeight: 520
    visible: true

    ClipComponents.ClipboardResultsPane {
      id: pane
      x: 0
      y: 0
      width: 740
      height: 500
      model: clip.displayModel
      history: clip.history
      selectedIndex: clip.selectedIndex
      cursorActive: clip.outlineShown
      layoutChangedAt: clip.layoutChangedAt
      revealedIndex: clip.revealedIndex
      kindGlyph: clip.kindGlyph
      onRowActivated: function (rowIndex, key) {
        clip.activateKey(rowIndex, key)
      }
    }
  }

  // A fake key event: CODE, with TEXT when it types.
  function key(code, text) {
    return {
      key: code,
      modifiers: Qt.NoModifier,
      text: text || "",
      accepted: false
    }
  }

  // Types TEXT into the picker one key at a time.
  function type(text) {
    for (var i = 0; i < text.length; i++)
      clip.handleKey(key(0, text[i]))
  }

  // The row delegate at INDEX, or null.
  function rowAt(index) {
    return pane.list.itemAtIndex(index)
  }

  // Whether row INDEX shows the mint outline.
  function outlined(index) {
    var row = rowAt(index)
    return !!row && row.hasCursor && t.findChild(row, "cursorOutline").visible
  }

  // Moves the pointer onto row INDEX and then a few pixels on (two real
  // samples, so the gate counts it as a move).
  function hoverRow(index) {
    var row = rowAt(index)
    pointer.mouseMove(row, 40, row.height / 2)
    pointer.mouseMove(row, 46, row.height / 2)
  }

  // Paste commands run for history index INDEX.
  function pastesOf(index) {
    return shell.ran.filter(function (argv) {
      return String(argv[0]).endsWith("/omarchy-clipboard-paste-text") && argv[argv.length - 1] === String(index)
    }).length
  }

  // History index of the entry whose text is TEXT.
  function historyIndexOf(text) {
    for (var i = 0; i < clip.history.length; i++)
      if (clip.history[i].text === text)
        return i
    return -1
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then finishes.
  function run(steps) {
    if (steps.length === 0) {
      t.done()
      return
    }
    t.step(steps[0][0], function () {
      steps[0][1]()
      run(steps.slice(1))
    })
  }

  Component.onCompleted: {
    run([[300, function () {
          // After the history file's own (failed) load, so it cannot wipe the fixture.
          clip.loadHistory(JSON.stringify([
            {
              type: "text",
              text: "alpha one",
              capturedAtMs: shell.now - 1000
            },
            {
              type: "text",
              text: "beta two",
              capturedAtMs: shell.now - 2000
            },
            {
              type: "text",
              text: "alpha three",
              capturedAtMs: shell.now - 3000
            },
            {
              type: "text",
              text: "gamma four",
              capturedAtMs: shell.now - 4000
            }
          ]))
          clip.open("{}")
        }], [400, function () {
          // ---------- Open: the outline is on the top row ----------
          t.equal(clip.displayModel.count, 4, "the fixture history shows four rows")
          t.check(clip.cursorActive && clip.selectedIndex === 0, "the cursor is on the first row on open")
          t.check(clip.outlineShown && outlined(0), "the outline marks Enter's target from open")
          t.check(!outlined(1) && !outlined(2), "and only that row")
          t.check(!rowAt(0).hovered && !rowAt(1).hovered && !rowAt(2).hovered, "no row is hover-filled under a still pointer")

          // ---------- Hover fills, never moves the outline ----------
          hoverRow(2)
        }], [60, function () {
          t.check(rowAt(2).hovered, "a real move onto a row fills it")
          t.check(!rowAt(0).hovered && !rowAt(1).hovered, "and only that row")
          t.equal(clip.selectedIndex, 0, "hovering another row does not move the keyboard cursor")
          t.check(outlined(0) && !outlined(2), "the outline stays on the first row")

          // ---------- The arrows move the outline ----------
          clip.handleKey(key(Qt.Key_Down))
          t.equal(clip.selectedIndex, 1, "the first Down moves the cursor to the second row")
          t.check(outlined(1) && !outlined(0), "and the outline with it")
          t.check(rowAt(2).hovered && !outlined(2), "the hover fill stays where the pointer is")
          clip.handleKey(key(Qt.Key_Up))
          t.check(clip.selectedIndex === 0 && outlined(0) && !outlined(1), "Up moves it back")
          hoverRow(1)
        }], [60, function () {
          t.check(rowAt(1).hovered && outlined(0) && clip.selectedIndex === 0, "a real move after the arrows fills the row, the outline stays put")

          // ---------- Type, then Enter targets the outlined top match ----------
          type("alpha")
          t.equal(clip.displayModel.count, 2, "the search shows two matches")
          t.check(clip.selectedIndex === 0 && clip.outlineShown && outlined(0), "typing keeps the outline on the first match")
          t.check(!rowAt(0).hovered && !rowAt(1).hovered, "the rows changing under the still pointer drop the hover fill")
          hoverRow(1)
        }], [60, function () {
          t.check(rowAt(1).hovered && clip.selectedIndex === 0, "hovering the second match does not steal the cursor")
          shell.ran = []
          clip.handleKey(key(Qt.Key_Return))
          t.equal(pastesOf(historyIndexOf("alpha one")), 1, "Enter pastes the outlined top match")
          t.equal(shell.ran.length, 1, "and only it")
          t.check(!clip.opened, "and closes the picker")
          clip.open("{}")
        }], [400, function () {
          // ---------- Empty results: no outline, Enter does nothing ----------
          type("zzzz")
          t.check(clip.displayModel.count === 0 && !clip.outlineShown, "the empty state shows no outline")
          shell.ran = []
          clip.handleKey(key(Qt.Key_Return))
          t.check(clip.opened && shell.ran.length === 0, "and Enter does nothing there")
          clip.handleKey(key(Qt.Key_Escape))
          t.check(clip.opened && clip.filterText === "" && clip.outlineShown, "Esc clears the search and Enter has a target again")
        }], [400, function () {
          t.check(outlined(0), "the outline is back on the top row")

          // ---------- Keyed refusal ----------
          t.check(!clip.activateKey(0, "text:0:0:none"), "an id the row does not hold is refused")
          t.check(clip.opened && shell.ran.length === 0, "and does nothing")
          pressedRow = rowAt(0)
          var before = clip.displayModel.get(0).entryId
          pointer.mousePress(pressedRow, 40, pressedRow.height / 2)
          clip.setFilter("beta")
          t.check(clip.displayModel.get(0).entryId !== before, "the results change under the pressed row")
          t.check(rowAt(0) === pressedRow, "the row delegate survives the rebuild")
        }], [400, function () {
          pointer.mouseRelease(pressedRow, 40, pressedRow.height / 2)
          t.equal(shell.ran.length, 0, "a release on a row that now holds another entry is refused")
          t.check(clip.opened && clip.filterText === "beta", "and the picker is untouched")
          clip.setFilter("")
        }], [400, function () {
          // ---------- Settle after the results change ----------
          stampBefore = clip.layoutChangedAt
          clip.rebuildDisplay()
          t.equal(clip.layoutChangedAt, stampBefore, "an equal rebuild does not stamp the layout")
          pressedRow = rowAt(0)
          clip.setFilter("gamma")
          t.check(clip.layoutChangedAt > stampBefore, "the results changing stamps the layout")
          t.check(rowAt(0) === pressedRow, "the first row keeps its delegate")
          pointer.mouseClick(pressedRow, 40, pressedRow.height / 2)
          t.check(clip.opened && shell.ran.length === 0, "a click right after the results change is refused")
        }], [400, function () {
          pointer.mouseClick(rowAt(0), 40, rowAt(0).height / 2)
          t.equal(pastesOf(historyIndexOf("gamma four")), 1, "a settled click pastes the clicked entry")
          t.check(!clip.opened, "and closes the picker")
        }]])
  }
}
