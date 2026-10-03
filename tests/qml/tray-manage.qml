// The Aranea Tray manage view, driven by a plain view object in a real
// window with real pointer clicks: the title and caption, one row per item
// with its name; the Pin pill reads "Pinned" and lights in the accent when
// pinned, the Hide pill reads "Hidden" and lights violet when hidden; a
// pending row's pills pulse; a settled click asks to pin or hide with the
// row's index and key; a press released after the row's key changed is
// refused, and so is a click right after the keys change; the outline shows
// only on the cursor's pill and only with cursor.active; rows changing
// under a still pointer emit no hover; and the empty text shows with no
// rows.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.tray" as Tray
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by manage, as [name, arg], in emission order.
  property var actions: []
  // A layout stamp taken before a change.
  property real stampBefore: 0
  // The pointer position the still-pointer checks replay.
  property var stillPoint: null
  // The items with the first row's key changed (Syncbox twice).
  property var swapped: []

  // Synthesizes pointer events (TestCase's helpers), never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // The stand-in items: Courier pinned, Syncbox in the drawer, Chatter
  // hidden; PENDING (an index) marks one row pending.
  function itemRows(pending) {
    return [
      {
        key: "org.example.Courier",
        name: "Courier",
        icon: "",
        pinned: true,
        hidden: false,
        pending: pending === 0
      },
      {
        key: "org.example.Syncbox",
        name: "Syncbox",
        icon: "",
        pinned: false,
        hidden: false,
        pending: pending === 1
      },
      {
        key: "org.example.Chatter",
        name: "Chatter",
        icon: "",
        pinned: false,
        hidden: true,
        pending: pending === 2
      }
    ]
  }

  // A view with OPTS: {rows, empty, cursor}; missing options give the
  // three items.
  function viewOf(opts) {
    var o = opts || {}
    return {
      rows: o.rows !== undefined ? o.rows : itemRows(-1),
      empty: !!o.empty,
      cursor: o.cursor || {
        active: false,
        row: -1,
        pill: 0
      },
      keyHint: "↑↓ move · ←→ pin / hide · enter toggle · esc close"
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

  // Row INDEX of the manage view.
  function rowAt(index) {
    return shown(manage, "manageRow")[index]
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
    implicitWidth: 380
    implicitHeight: 500
    visible: true

    Tray.TrayManageView {
      id: manage
      x: 20
      y: 20
      width: 320
      view: viewOf({})
      onAction: function (name, arg) {
        actions.push([name, arg])
      }
    }
  }

  Component.onCompleted: run([[350, function () {
        // ---------- Header and rows ----------
        t.equal(one(manage, "manageTitle").text, "Tray icons", "the title")
        t.equal(one(manage, "manageCaption").text, "Pinned icons stay visible. Hidden icons never show.", "the caption")
        t.equal(shown(manage, "manageRow").length, 3, "one row per item")
        t.equal(one(rowAt(1), "rowName").text, "Syncbox", "a row's name")
        t.check(!one(manage, "emptyText").visible, "no empty text with rows")
        t.equal(one(manage, "keyHint").text, "↑↓ move · ←→ pin / hide · enter toggle · esc close", "the key hint")

        // ---------- Pills ----------
        var pinned = one(rowAt(0), "pinPill")
        t.equal(pinned.text, "Pinned", "a pinned item's pill reads Pinned")
        t.check(pinned.selected, "and is lit")
        t.check(Qt.colorEqual(pinned.selectedColor, Aranea.DesignTokens.accent), "in the accent")
        t.equal(one(rowAt(0), "hidePill").text, "Hide", "its hide pill reads Hide")
        t.check(!one(rowAt(0), "hidePill").selected, "unlit")
        t.equal(one(rowAt(1), "pinPill").text, "Pin", "an unpinned item's pill reads Pin")
        t.check(!one(rowAt(1), "pinPill").selected, "unlit")
        var hidden = one(rowAt(2), "hidePill")
        t.equal(hidden.text, "Hidden", "a hidden item's pill reads Hidden")
        t.check(hidden.selected, "and is lit")
        t.check(Qt.colorEqual(hidden.selectedColor, Aranea.DesignTokens.strandEnd), "in violet")
        t.check(Qt.colorEqual(one(hidden, "pillBorder").border.color, Aranea.DesignTokens.strandEnd), "its border is violet")
        t.check(one(rowAt(2), "rowName").color.a < 1 || one(rowAt(2), "rowName").opacity < 1, "a hidden item's name is muted")

        // ---------- Pending ----------
        t.check(!one(rowAt(1), "pinPill").busy, "no pulse at rest")
        manage.view = viewOf({
          rows: itemRows(1)
        })
        t.check(one(rowAt(1), "pinPill").busy && one(rowAt(1), "hidePill").busy, "a pending row's pills pulse")
        t.equal(one(one(rowAt(1), "pinPill"), "busyPulse").running, Aranea.DesignTokens.motionEnabled, "the pulse runs with motion")
        t.check(!one(rowAt(0), "pinPill").busy, "other rows do not")
        manage.view = viewOf({})

        // ---------- Clicks ----------
        actions = []
        pointer.mouseClick(one(rowAt(1), "pinPill"))
        t.check(reported("pin", {
          index: 1,
          key: "org.example.Syncbox"
        }) && nonHover().length === 1, "a click on Pin asks to pin with the row's index and key")
        actions = []
        pointer.mouseClick(one(rowAt(2), "hidePill"))
        t.check(reported("hide", {
          index: 2,
          key: "org.example.Chatter"
        }) && nonHover().length === 1, "a click on Hide asks to hide with the row's index and key")

        // ---------- Key mismatch under a held press ----------
        actions = []
        pointer.mousePress(one(rowAt(0), "pinPill"))
        swapped = itemRows(-1)
        swapped[0] = swapped[1]
        manage.view = viewOf({
          rows: swapped
        })
      }], [350, function () {
        pointer.mouseRelease(one(rowAt(0), "pinPill"))
        t.equal(named("pin").length, 0, "a press on one key released on another is refused")

        // ---------- Layout stamps and ClickSettle ----------
        stampBefore = manage.layoutChangedAt
        manage.view = viewOf({
          rows: swapped
        })
        t.equal(manage.layoutChangedAt, stampBefore, "an equal key list does not stamp the layout")
        manage.view = viewOf({})
        t.check(manage.layoutChangedAt > stampBefore, "the keys changing stamps the layout")
        actions = []
        pointer.mouseClick(one(rowAt(1), "pinPill"))
        t.equal(nonHover().length, 0, "a click right after the stamp is refused")
      }], [350, function () {
        actions = []
        pointer.mouseClick(one(rowAt(1), "hidePill"))
        t.check(reported("hide", {
          index: 1,
          key: "org.example.Syncbox"
        }), "a click 300 ms later is accepted")

        // ---------- The keyboard cursor ----------
        manage.view = viewOf({
          cursor: {
            active: false,
            row: 1,
            pill: 1
          }
        })
        t.equal(litOutlines(manage), 0, "no outline without cursor.active")
        manage.view = viewOf({
          cursor: {
            active: true,
            row: 1,
            pill: 1
          }
        })
        t.equal(litOutlines(manage), 1, "one outline with cursor.active")
        t.equal(litOutlines(one(rowAt(1), "hidePill")), 1, "on the chosen pill")
        manage.view = viewOf({})
      }], [350, function () {
        // ---------- Still pointer ----------
        manage.disarmPointer()
        var name = one(rowAt(1), "rowName")
        stillPoint = name.mapToItem(manage, name.width / 2, name.height / 2)
        actions = []
        pointer.mouseMove(manage, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(manage, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          row: 1
        }), "a real move over a row reports hover")
        t.equal(litOutlines(manage), 0, "hover draws no outline")
        actions = []
        var moved = itemRows(-1)
        moved.unshift({
          key: "org.example.Dropper",
          name: "Dropper",
          icon: "",
          pinned: false,
          hidden: false,
          pending: false
        })
        manage.view = viewOf({
          rows: moved
        })
      }], [80, function () {
        pointer.mouseMove(manage, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.equal(named("hover").length, 0, "rows changing under a still pointer emit no hover")
        pointer.mouseMove(manage, stillPoint.x, stillPoint.y + 2)
      }], [80, function () {
        t.check(reported("hover", {
          row: 1
        }), "a real move afterwards reports hover again")

        // ---------- Empty ----------
        stampBefore = manage.layoutChangedAt
      }], [20, function () {
        manage.view = viewOf({
          rows: [],
          empty: true
        })
        t.check(manage.layoutChangedAt > stampBefore, "emptying stamps the layout")
        t.check(one(manage, "emptyText").visible, "the empty text shows")
        t.equal(one(manage, "emptyText").text, "No tray items reporting.", "with stock's words")
        t.equal(shown(manage, "manageRow").length, 0, "and no rows")
        t.check(one(manage, "manageTitle").visible, "the title stays")
      }]])
}
