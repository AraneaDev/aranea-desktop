// The notification center's Filament header and footer, driven by a
// plain view object in a real window with real pointer clicks: the
// caption states ("N unread", "Nothing new", the quiet-hours text), the
// empty state only at count 0, the DND switch shows on and busy and
// emits toggleDnd once per settled click, the Clear pill hides at 0 and
// shows the confirm label and emits clearAll, a click right after
// noteLayoutChange() is refused on both controls, no outline without the
// keyboard cursor and exactly one with it, and the hint line renders.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.notifications" as Notifications

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by full, as [name, arg], in emission order.
  property var actions: []

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // A view with OPTS: {count, caption, dndOn, dndBusy, clearVisible,
  // clearConfirming, clearLabel, keyHint}; missing options give 3 unread,
  // DND off, Clear all visible.
  function viewOf(opts) {
    var o = opts || {}
    return {
      count: o.count !== undefined ? o.count : 3,
      caption: o.caption !== undefined ? o.caption : "3 unread",
      dnd: {
        on: !!o.dndOn,
        busy: !!o.dndBusy
      },
      clear: {
        visible: o.clearVisible !== undefined ? o.clearVisible : true,
        confirming: !!o.clearConfirming,
        label: o.clearLabel !== undefined ? o.clearLabel : (o.clearConfirming ? "Confirm clear (" + (o.count !== undefined ? o.count : 3) + ")" : "Clear all")
      },
      keyHint: o.keyHint !== undefined ? o.keyHint : "↑↓ move · enter open · del dismiss · ⇧del clear group"
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

  // The first child of ITEM named NAME.
  function one(item, name) {
    return t.findChild(item, name)
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
    implicitWidth: 420
    implicitHeight: 500
    visible: true

    Column {
      x: 20
      width: 380
      spacing: 20

      Notifications.NotificationCenterContent {
        id: full
        width: 380
        view: viewOf({})
        onAction: function (name, arg) {
          actions.push([name, arg])
        }
      }

      // Nothing waiting: the empty state shows and Clear hides.
      Notifications.NotificationCenterContent {
        id: empty
        width: 380
        view: viewOf({
          count: 0,
          caption: "Nothing new",
          clearVisible: false
        })
      }

      // Quiet hours active.
      Notifications.NotificationCenterContent {
        id: quiet
        width: 380
        view: viewOf({
          caption: "Quiet until 08:00"
        })
      }
    }
  }

  Component.onCompleted: run([[350, function () {
        // ---------- Caption states ----------
        t.equal(one(full, "centerHeader").title, "Notifications", "the header's title")
        t.equal(one(full, "headerCaption").text, "3 unread", "3 unread, with native casing")
        t.equal(one(empty, "headerCaption").text, "Nothing new", "nothing new at count 0")
        t.equal(one(quiet, "headerCaption").text, "Quiet until 08:00", "the quiet-hours text")

        // ---------- Empty state ----------
        t.check(!one(full, "emptyState").visible, "no empty state with unread entries")
        t.check(one(empty, "emptyState").visible, "the empty state shows at count 0")
        t.equal(one(empty, "emptyState").message, "All caught up", "with its message")

        // ---------- DND switch ----------
        t.check(!one(full, "dndSwitch").checked, "DND off by default")
        t.check(!one(full, "dndSwitch").busy, "and not busy")
        full.view = viewOf({
          dndOn: true,
          dndBusy: true
        })
        t.check(one(full, "dndSwitch").checked, "a view with dnd.on reads on")
        t.check(one(full, "dndSwitch").busy, "and dnd.busy pulses")
        full.view = viewOf({})

        // ---------- Clear pill ----------
        t.check(!one(empty, "clearRow").visible, "the Clear pill hides at count 0")
        t.check(one(full, "clearRow").visible, "and shows with unread entries")
        t.equal(one(full, "clearPill").text, "Clear all", "the plain label")
        full.view = viewOf({
          clearConfirming: true
        })
        t.equal(one(full, "clearPill").text, "Confirm clear (3)", "the confirm label")
        full.view = viewOf({})

        // ---------- Key hint ----------
        t.equal(one(full, "keyHint").text, "↑↓ move · enter open · del dismiss · ⇧del clear group", "the hint line renders the view's text")

        // ---------- No outline without the cursor ----------
        t.equal(litOutlines(full), 0, "an inactive cursor draws no outline")
        full.dndCursor = true
        t.equal(litOutlines(full), 1, "the cursor on the DND row draws exactly one outline")
        full.dndCursor = false
        full.clearCursor = true
        t.equal(litOutlines(full), 1, "and so does the cursor on the Clear pill")
        full.clearCursor = false
        t.equal(litOutlines(full), 0, "and none once it leaves")
      }], [350, function () {
        // ---------- Settled clicks ----------
        actions = []
        pointer.mouseClick(one(full, "dndSwitch"))
        t.check(reported("toggleDnd", ({})) && actions.length === 1, "a settled click on the DND switch emits toggleDnd once")
        actions = []
        pointer.mouseClick(one(full, "clearPill"))
        t.check(reported("clearAll", ({})) && actions.length === 1, "a settled click on the Clear pill emits clearAll")
      }], [350, function () {
        // ---------- Refused right after a layout stamp ----------
        actions = []
        full.noteLayoutChange()
        pointer.mouseClick(one(full, "dndSwitch"))
        pointer.mouseClick(one(full, "clearPill"))
        t.equal(actions.length, 0, "clicks right after noteLayoutChange() are refused on both controls")
      }], [40, function () {
        pointer.mouseClick(one(full, "dndSwitch"))
        pointer.mouseClick(one(full, "clearPill"))
        t.equal(actions.length, 0, "and still refused 40 ms later, inside the settle window")
      }], [350, function () {
        pointer.mouseClick(one(full, "dndSwitch"))
        pointer.mouseClick(one(full, "clearPill"))
        t.equal(named("toggleDnd").length, 1, "and accepted once the settle window passes")
        t.equal(named("clearAll").length, 1, "for the Clear pill too")
      }]])
}
