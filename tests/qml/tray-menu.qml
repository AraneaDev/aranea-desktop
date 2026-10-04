// The Aranea Tray app menu view, driven by a plain view object in a real
// window with real pointer clicks: the title and key hint, rows with their
// check and radio marks, the child glyph, dimmed disabled rows and hairline
// separators render from the view; separators and disabled rows take no
// click and no hover; a settled click activates with the row's index and
// key; a press released after the row's key changed is refused; the rows'
// keys changing, the depth changing and the menu emptying stamp the layout
// (an equal key list does not) and a click right after a stamp is refused;
// the breadcrumb shows only below the root and its back glyph asks to go
// back; "No menu entries" shows when empty; no outline shows without
// cursor.active and hover never draws one; and rows changing under a still
// pointer emit no hover.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.tray" as Tray

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by menu, as [name, arg], in emission order.
  property var actions: []
  // A layout stamp taken before a change.
  property real stampBefore: 0
  // The pointer position the still-pointer checks replay.
  property var stillPoint: null
  // The root rows with the first row's key changed.
  property var changed: []

  // Synthesizes pointer events (TestCase's helpers), never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // A menu row with FIELDS over the defaults (a plain selectable entry).
  function rowOf(fields) {
    var row = {
      key: "",
      label: "",
      separator: false,
      enabled: true,
      selectable: true,
      mark: "",
      markOn: false,
      hasChildren: false,
      icon: "",
      index: 0
    }
    for (var k in fields)
      row[k] = fields[k]
    return row
  }

  // The root rows: a plain entry, a submenu, a lit check, a disabled
  // entry, a separator and Quit.
  function rootRows() {
    return [rowOf({
        key: "1|Open Courier",
        label: "Open Courier",
        index: 1
      }), rowOf({
        key: "4|Send a file",
        label: "Send a file",
        hasChildren: true,
        index: 2
      }), rowOf({
        key: "5|Start minimised",
        label: "Start minimised",
        mark: "check",
        markOn: true,
        index: 3
      }), rowOf({
        key: "6|Receive (busy)",
        label: "Receive (busy)",
        enabled: false,
        selectable: false,
        index: 4
      }), rowOf({
        key: "7|",
        separator: true,
        selectable: false,
        index: 5
      }), rowOf({
        key: "8|Quit",
        label: "Quit",
        index: 6
      })]
  }

  // The "Send a file" submenu's rows, the last a lit radio.
  function subRows() {
    return [rowOf({
        key: "11|To nearby device",
        label: "To nearby device",
        index: 0
      }), rowOf({
        key: "12|Share a link",
        label: "Share a link",
        mark: "radio",
        markOn: false,
        index: 1
      }), rowOf({
        key: "13|Fast mode",
        label: "Fast mode",
        mark: "radio",
        markOn: true,
        index: 2
      })]
  }

  // A view with OPTS: {rows, depth, crumb, empty, cursor}; missing options
  // give the root menu.
  function viewOf(opts) {
    var o = opts || {}
    return {
      title: "Courier",
      crumb: o.crumb !== undefined ? o.crumb : "",
      depth: o.depth !== undefined ? o.depth : 0,
      rows: o.rows !== undefined ? o.rows : rootRows(),
      empty: !!o.empty,
      cursor: o.cursor || {
        active: false,
        index: -1
      },
      keyHint: "↑↓ move · enter run · → open · ← back · esc close"
    }
  }

  // Whether an action NAME with ARG (compared as JSON) was reported.
  function reported(name, arg) {
    var want = JSON.stringify([name, arg])
    return actions.some(function (a) {
      return JSON.stringify(a) === want
    })
  }

  // Actions named NAME.
  function named(name) {
    return actions.filter(function (a) {
      return a[0] === name
    })
  }

  // Actions other than hover.
  function nonHover() {
    return actions.filter(function (a) {
      return a[0] !== "hover"
    })
  }

  // The first child of ITEM named NAME.
  function one(item, name) {
    return t.findChild(item, name)
  }

  // The visible items in ITEM named NAME.
  function shown(item, name) {
    return t.findChildren(item, name).filter(function (c) {
      return c.visible
    })
  }

  // Row INDEX of the menu.
  function rowAt(index) {
    return shown(menu, "menuRow")[index]
  }

  // How many cursor outlines in ITEM are drawn (a border or a fill).
  function litOutlines(item) {
    return t.findChildren(item, "cursorOutline").filter(function (o) {
      return o.visible && (o.border.width > 0 || o.color.a > 0)
    }).length
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then ends the run.
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

  FloatingWindow {
    id: win
    implicitWidth: 360
    implicitHeight: 600
    visible: true

    Tray.TrayMenuView {
      id: menu
      x: 20
      y: 20
      width: 300
      view: viewOf({})
      onAction: function (name, arg) {
        actions.push([name, arg])
      }
    }
  }

  Component.onCompleted: run([[350, function () {
        // ---------- Rows and marks ----------
        t.equal(one(menu, "menuTitle").text, "COURIER", "the app title, uppercased")
        t.check(!one(menu, "crumbRow").visible, "no breadcrumb at the root")
        t.equal(shown(menu, "menuRow").length, 6, "one row per view row")
        t.equal(one(rowAt(0), "rowLabel").text, "Open Courier", "a row's label")
        t.equal(one(rowAt(2), "rowMark").text, String.fromCodePoint(0x2713), "a lit check shows a check mark")
        t.equal(one(rowAt(0), "rowMark").text, "", "a plain row shows no mark")
        t.check(one(rowAt(2), "selectedFill").visible && !one(rowAt(0), "selectedFill").visible, "a lit check carries the selected highlight, a plain row none")
        t.check(one(rowAt(1), "childGlyph").visible, "a submenu row shows the child glyph")
        t.equal(one(rowAt(1), "childGlyph").text, String.fromCodePoint(0x203A), "the child glyph is a right angle quote")
        t.check(!one(rowAt(0), "childGlyph").visible, "a leaf row shows none")
        t.check(rowAt(3).opacity < 1, "a disabled row is dimmed")
        t.equal(rowAt(0).opacity, 1, "an enabled row is not")
        t.check(one(rowAt(4), "separatorLine").visible, "a separator draws a hairline")
        t.check(!one(rowAt(4), "rowLabel").visible, "and no label")
        t.check(!one(rowAt(0), "separatorLine").visible, "a plain row draws no hairline")
        t.check(!one(menu, "emptyText").visible, "no empty text with rows")
        t.equal(one(menu, "keyHint").text, "↑↓ move · enter run · → open · ← back · esc close", "the key hint")

        // ---------- Clicks ----------
        actions = []
        pointer.mouseClick(rowAt(4))
        t.equal(nonHover().length, 0, "a separator is not clickable")
        pointer.mouseClick(rowAt(3))
        t.equal(nonHover().length, 0, "a disabled click emits nothing")
        pointer.mouseClick(rowAt(5))
        t.check(reported("activate", {
          index: 5,
          key: "8|Quit"
        }) && nonHover().length === 1, "a click activates with its index and key")
        actions = []
        menu.activateAt(5, "1|Open Courier")
        t.equal(nonHover().length, 0, "an activation whose key no longer matches its row is refused")
        menu.activateAt(3, "6|Receive (busy)")
        t.equal(nonHover().length, 0, "an activation of a disabled row is refused")

        // ---------- Key mismatch under a held press ----------
        actions = []
        pointer.mousePress(rowAt(0))
        changed = rootRows()
        changed[0] = rowOf({
          key: "9|Open Courier",
          label: "Open Courier",
          index: 1
        })
        menu.view = viewOf({
          rows: changed
        })
      }], [350, function () {
        pointer.mouseRelease(rowAt(0))
        t.equal(named("activate").length, 0, "a press on one key released on another is refused")

        // ---------- Layout stamps and ClickSettle ----------
        stampBefore = menu.layoutChangedAt
        menu.view = viewOf({
          rows: changed
        })
        t.equal(menu.layoutChangedAt, stampBefore, "an equal key list does not stamp the layout")
        menu.view = viewOf({})
        t.check(menu.layoutChangedAt > stampBefore, "the rows' keys changing stamps the layout")
        actions = []
        pointer.mouseClick(rowAt(0))
        t.equal(nonHover().length, 0, "a click right after the stamp is refused")
      }], [350, function () {
        actions = []
        pointer.mouseClick(rowAt(0))
        t.check(reported("activate", {
          index: 0,
          key: "1|Open Courier"
        }), "a click 300 ms later is accepted")

        // ---------- Breadcrumb ----------
        stampBefore = menu.layoutChangedAt
        menu.view = viewOf({
          depth: 1,
          crumb: "Courier › Send a file",
          rows: subRows()
        })
        t.check(menu.layoutChangedAt > stampBefore, "drilling in stamps the layout")
        t.check(one(menu, "crumbRow").visible, "the breadcrumb shows below the root")
        t.equal(one(menu, "crumbBack").text, String.fromCodePoint(0x2039), "with the back glyph")
        t.equal(one(menu, "crumbText").text, "COURIER › SEND A FILE", "and the crumb, uppercased")
        t.check(!one(menu, "menuTitle").visible, "the root title gives way to it")
        t.equal(one(rowAt(2), "rowMark").text, String.fromCodePoint(0x25CF), "a lit radio shows a dot")
        t.equal(one(rowAt(1), "rowMark").text, "", "an unlit radio shows none")
        actions = []
        pointer.mouseClick(one(menu, "crumbBack"))
        t.equal(nonHover().length, 0, "a back click right after drilling in is refused")
      }], [350, function () {
        actions = []
        pointer.mouseClick(one(menu, "crumbBack"))
        t.check(reported("back", {}) && nonHover().length === 1, "the back glyph asks to go back")
        stampBefore = menu.layoutChangedAt
      }], [20, function () {
        menu.view = viewOf({
          depth: 2,
          crumb: "Courier › Send a file",
          rows: subRows()
        })
        t.check(menu.layoutChangedAt > stampBefore, "the depth changing alone stamps the layout")

        // ---------- Empty ----------
        stampBefore = menu.layoutChangedAt
      }], [20, function () {
        menu.view = viewOf({
          rows: [],
          empty: true
        })
        t.check(menu.layoutChangedAt > stampBefore, "emptying stamps the layout")
        t.check(one(menu, "emptyText").visible, "the empty text shows")
        t.equal(one(menu, "emptyText").text, "No menu entries", "with stock's words")
        t.equal(shown(menu, "menuRow").length, 0, "and no rows")
        menu.view = viewOf({})

        // ---------- The keyboard cursor ----------
        menu.view = viewOf({
          cursor: {
            active: false,
            index: 1
          }
        })
        t.equal(litOutlines(menu), 0, "no outline without cursor.active")
        menu.view = viewOf({
          cursor: {
            active: true,
            index: 1
          }
        })
        t.equal(litOutlines(menu), 1, "one outline with cursor.active")
        t.equal(litOutlines(rowAt(1)), 1, "on the cursor's row")
        menu.view = viewOf({})
      }], [350, function () {
        // ---------- Still pointer ----------
        menu.disarmPointer()
        var r1 = rowAt(1)
        stillPoint = r1.mapToItem(menu, r1.width / 2, r1.height / 2)
        actions = []
        pointer.mouseMove(menu, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(menu, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          index: 1
        }), "a real move over a row reports hover")
        t.check(one(rowAt(1), "hoverFill").visible && !one(rowAt(0), "hoverFill").visible, "and draws that row's hover fill")
        t.equal(litOutlines(menu), 0, "hover draws no outline")
        actions = []
        var moved = rootRows()
        moved.unshift(rowOf({
          key: "0|About",
          label: "About",
          index: 0
        }))
        menu.view = viewOf({
          rows: moved
        })
      }], [80, function () {
        pointer.mouseMove(menu, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.equal(named("hover").length, 0, "rows changing under a still pointer emit no hover")
        pointer.mouseMove(menu, stillPoint.x, stillPoint.y + 2)
      }], [80, function () {
        t.check(reported("hover", {
          index: 1
        }), "a real move afterwards reports hover again")

        // ---------- No hover on separators or disabled rows ----------
        menu.view = viewOf({})
      }], [80, function () {
        // Once the rebuilt rows have replaced the old ones.
        actions = []
        var off = rowAt(3)
        var p = off.mapToItem(menu, off.width / 2, off.height / 2)
        pointer.mouseMove(menu, p.x, p.y)
        pointer.mouseMove(menu, p.x + 6, p.y)
        var sep = rowAt(4)
        var q = sep.mapToItem(menu, sep.width / 2, sep.height / 2)
        pointer.mouseMove(menu, q.x, q.y)
        pointer.mouseMove(menu, q.x + 6, q.y)
      }], [80, function () {
        t.equal(named("hover"), [], "a disabled row or separator is no hover target")
        t.check(!one(rowAt(3), "hoverFill").visible && !one(rowAt(4), "hoverFill").visible, "and draws no hover fill")
      }]])
}
