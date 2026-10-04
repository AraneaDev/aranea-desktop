// The emoji picker's pointer rules, with real pointer events on the picker
// content in a window, wired to the real Emojis.qml (its own window off,
// commands recorded) the way its window wires them: the mint outline marks
// Enter's target and shows from open on the first cell (the first recent
// when there are recents); hover fills the cell under the pointer after a
// real move but never moves the outline; the first arrow moves it straight
// away; typing keeps it on the first match so Enter inserts that match
// even with the pointer over another cell; no results shows no outline
// and Enter does nothing; a click is keyed by the cell's emoji and refused
// when the cell holds another emoji on release; the cells changing stamps
// the layout (an equal rebuild does not) and a click inside the 300 ms
// settle window is refused; cells survive a rebuild.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.emojis" as Emoji

ShellRoot {
  id: shell

  // Commands the picker ran (argv arrays), newest last.
  property var ran: []
  // The cell pressed before the results changed.
  property var pressedCell: null
  // The layout stamp a step compares against.
  property real stampBefore: 0
  // The emoji a step expects to be inserted.
  property string expected: ""

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

  Emoji.Emojis {
    id: emo
    windowEnabled: false
    omarchyPath: "/opt/omarchy"
    run: function (argv) {
      shell.ran = shell.ran.concat([argv])
    }
  }

  FloatingWindow {
    implicitWidth: 520
    implicitHeight: 640
    visible: true

    Emoji.EmojiPickerContent {
      id: content
      x: 0
      y: 0
      width: 500
      height: 620
      filterText: emo.filterText
      resultModel: emo.displayModel
      recentModel: emo.recents
      showRecents: emo.showRecents
      selectedIndex: emo.selectedIndex
      cursorActive: emo.outlineShown
      layoutChangedAt: emo.layoutChangedAt
      inRecents: emo.inRecents
      recentIndex: emo.recentIndex
      selectedEmoji: emo.selectedEmoji
      selectedName: emo.selectedName
      cellWidth: emo.cellWidth
      cellHeight: emo.cellHeight
      columns: emo.columns
      onRecentPicked: function (index, key) {
        emo.activateRecentKey(index, key)
      }
      onResultPicked: function (index, key) {
        emo.activateKey(index, key)
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
      emo.handleKey(key(0, text[i]))
  }

  // The grid cell at INDEX, or null.
  function cellAt(index) {
    return content.grid.itemAtIndex(index)
  }

  // Whether CELL shows the mint outline.
  function outlined(cell) {
    return !!cell && cell.hasCursor && t.findChild(cell, "cursorOutline").visible
  }

  // Moves the pointer onto CELL and then a few pixels on (two real samples,
  // so the gate counts it as a move).
  function hover(cell) {
    pointer.mouseMove(cell, cell.width / 2 - 3, cell.height / 2)
    pointer.mouseMove(cell, cell.width / 2 + 3, cell.height / 2)
  }

  // Inserts of EMOJI run so far.
  function insertsOf(emoji) {
    return shell.ran.filter(function (argv) {
      return String(argv[0]).endsWith("/omarchy-menu-emoji-insert") && argv[1] === emoji
    }).length
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
    t.waitFor(function () {
      return emo.emojis.length > 100
    }, 10000, "the emoji data loads", function () {
      run([[300, function () {
            // After the recents file's own load, so it cannot replace the list.
            emo.recents = []
            emo.open("{}")
          }], [400, function () {
            // ---------- Open: the outline is on the first cell ----------
            t.check(emo.displayModel.count > 100, "every emoji shows with an empty search")
            t.check(emo.outlineShown && !emo.inRecents && emo.selectedIndex === 0, "the cursor is on the first cell on open")
            t.check(outlined(cellAt(0)) && !outlined(cellAt(1)), "the outline marks Enter's target from open")
            t.check(!cellAt(0).hovered && !cellAt(1).hovered && !cellAt(2).hovered, "no cell is hover-filled under a still pointer")

            // ---------- Hover fills, never moves the outline ----------
            hover(cellAt(2))
          }], [60, function () {
            t.check(cellAt(2).hovered && !cellAt(0).hovered && !cellAt(1).hovered, "a real move onto a cell fills it, and only it")
            t.equal(emo.selectedIndex, 0, "hovering another cell does not move the keyboard cursor")
            t.check(outlined(cellAt(0)) && !outlined(cellAt(2)), "the outline stays on the first cell")

            // ---------- The arrows move the outline straight away ----------
            emo.handleKey(key(Qt.Key_Right))
            t.equal(emo.selectedIndex, 1, "the first Right moves the cursor to the second cell")
            t.check(outlined(cellAt(1)) && !outlined(cellAt(0)), "and the outline with it")
            t.check(cellAt(2).hovered && !outlined(cellAt(2)), "the hover fill stays where the pointer is")
            emo.handleKey(key(Qt.Key_Left))
            t.check(emo.selectedIndex === 0 && outlined(cellAt(0)), "Left moves it back")

            // ---------- Type, then Enter targets the outlined first match ----------
            type("heart")
            t.check(emo.displayModel.count >= 3, "the search shows several matches")
            t.check(emo.selectedIndex === 0 && emo.outlineShown && outlined(cellAt(0)), "typing keeps the outline on the first match")
            t.check(!cellAt(2).hovered, "the cells changing under the still pointer drop the hover fill")
            hover(cellAt(1))
          }], [60, function () {
            t.check(cellAt(1).hovered && emo.selectedIndex === 0, "hovering the second match does not steal the cursor")
            expected = emo.displayModel.get(0).emoji
            t.check(expected !== emo.displayModel.get(1).emoji, "the first match differs from the hovered one")
            shell.ran = []
            emo.handleKey(key(Qt.Key_Return))
            t.equal(insertsOf(expected), 1, "Enter inserts the outlined first match")
            t.equal(shell.ran.length, 1, "and only it")
            t.check(!emo.opened, "and closes the picker")
            emo.open("{}")
          }], [400, function () {
            // ---------- With recents, the outline starts on the first recent ----------
            t.check(emo.showRecents && emo.inRecents && emo.recents[0] === expected, "the inserted emoji is the first recent")
            var recent = content.recentCells.itemAt(0)
            t.check(emo.outlineShown && outlined(recent) && !outlined(cellAt(0)), "the outline is on the first recent from open")
            t.check(!emo.activateRecentKey(0, "x"), "a recent click keyed to another emoji is refused")
            t.check(emo.opened && shell.ran.length === 1, "and does nothing")

            // ---------- No results: no outline, Enter does nothing ----------
            type("zzqqxx")
            t.check(emo.displayModel.count === 0 && !emo.outlineShown, "no results shows no outline")
            shell.ran = []
            emo.handleKey(key(Qt.Key_Return))
            t.check(emo.opened && shell.ran.length === 0, "and Enter does nothing there")
            emo.handleKey(key(Qt.Key_Escape))
            t.check(emo.opened && emo.filterText === "" && emo.outlineShown, "Esc clears the search and Enter has a target again")
            type("heart")
          }], [400, function () {
            // ---------- Keyed refusal ----------
            t.check(!emo.activateKey(0, "x"), "a grid click keyed to another emoji is refused")
            pressedCell = cellAt(0)
            var before = emo.displayModel.get(0).emoji
            pointer.mousePress(pressedCell, pressedCell.width / 2, pressedCell.height / 2)
            emo.setFilter("smile")
            t.check(emo.displayModel.get(0).emoji !== before, "the results change under the pressed cell")
            t.check(cellAt(0) === pressedCell, "the cell delegate survives the rebuild")
          }], [400, function () {
            pointer.mouseRelease(pressedCell, pressedCell.width / 2, pressedCell.height / 2)
            t.equal(shell.ran.length, 0, "a release on a cell that now holds another emoji is refused")
            t.check(emo.opened && emo.filterText === "smile", "and the picker is untouched")
          }], [400, function () {
            // ---------- Settle after the results change ----------
            stampBefore = emo.layoutChangedAt
            emo.rebuildDisplay()
            t.equal(emo.layoutChangedAt, stampBefore, "an equal rebuild does not stamp the layout")
            emo.setFilter("heart")
            t.check(emo.layoutChangedAt > stampBefore, "the results changing stamps the layout")
            pressedCell = cellAt(1)
            pointer.mouseClick(pressedCell, pressedCell.width / 2, pressedCell.height / 2)
            t.check(emo.opened && shell.ran.length === 0, "a click right after the results change is refused")
          }], [400, function () {
            expected = emo.displayModel.get(1).emoji
            pointer.mouseClick(cellAt(1), cellAt(1).width / 2, cellAt(1).height / 2)
            t.equal(insertsOf(expected), 1, "a settled click inserts the clicked emoji")
            t.check(!emo.opened, "and closes the picker")
          }]])
    })
  }
}
