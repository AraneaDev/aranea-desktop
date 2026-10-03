// The notification center's list and the cards it shares with the toasts,
// in a real window with real pointer moves and clicks. Toast-mode cards (no
// gate, no cursor) keep today's look: the same fill, border spec, radius,
// width and urgency rail for normal, critical and low urgency, today's
// light tint on hover, no outline, and clicks that are never settled. In
// the center: hover draws no fill and no outline; the mint outline shows
// only on the cursor's row while cursor.active; clicks act with the row's
// index and key (open, dismiss, toggle, clearGroup); a press released after a
// re-sort moved another entry under it is refused, even past the settle
// window; the rows' keys, a collapse, the "+N more" count and the header
// height stamp the layout (an equal list does not) and a click 0 or 40 ms
// after a stamp is refused, 350 ms later accepted; a still pointer while
// rows shift emits no hover; and the close tint follows only real moves.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.shared" as Aranea
import "plugins/araneadev.notifications" as Notif
import "plugins/araneadev.notifications/InboxLogic.js" as InboxLogic

ShellRoot {
  id: testRoot

  // Test start in ms; entry timestamps are relative to it.
  readonly property real now: Date.now()
  // Actions reported by the list, as [name, arg], in emission order.
  property var actions: []
  // Toast events, as [name], in emission order.
  property var toastEvents: []
  // A layout stamp taken before a change.
  property real stampBefore: 0
  // The pointer position the still-pointer checks replay.
  property var stillPoint: null
  // The row item a held press started on.
  property var pressedItem: null
  // NotificationCard, as Toasts.qml uses it.
  readonly property string cardUrl: "plugins/araneadev.notifications/components/NotificationCard.qml"
  // The normal urgency toast-mode card.
  readonly property var toast: toastLoader.item
  // The critical toast-mode card.
  readonly property var critToast: critLoader.item
  // The low urgency toast-mode card.
  readonly property var lowToast: lowLoader.item

  QmlTest {
    id: t
  }

  // Synthesizes pointer events (TestCase's helpers), never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // An inbox snapshot row: FILE from APP, AGE seconds old, at URGENCY.
  function entry(file, app, age, urgency) {
    return {
      fileName: file,
      id: 0,
      originalId: 0,
      app: app,
      appIcon: "",
      summary: app + " " + file,
      body: "body of " + file,
      image: "",
      glyph: "",
      execArgv: [],
      urgency: urgency,
      expireTimeout: -1,
      timestamp: testRoot.now - age * 1000,
      sourceKey: ""
    }
  }

  // The base inbox: a critical Alarm, a Build and four Chats (collapsed to
  // the newest with "+3 more").
  function baseEntries() {
    return [entry("a1", "Alarm", 60, 2), entry("b1", "Build", 10, 1), entry("c1", "Chat", 20, 1), entry("c2", "Chat", 30, 1), entry("c3", "Chat", 40, 1), entry("c4", "Chat", 50, 1)]
  }

  // The base inbox with b1 turned critical: Build sorts above Alarm, the
  // same number of rows.
  function resortedEntries() {
    var list = baseEntries()
    list[1].urgency = 2
    return list
  }

  // Center rows for ENTRIES with EXPANDED overrides, as Panel.qml builds them.
  function rowsOf(entries, expanded) {
    return InboxLogic.centerRows(entries, expanded || {})
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

  // How many cursor outlines in ITEM are drawn (a border or a fill).
  function litOutlines(item) {
    return t.findChildren(item, "cursorOutline").filter(function (o) {
      return o.visible && (o.border.width > 0 || o.color.a > 0)
    }).length
  }

  // Whether colours A and B are the same.
  function sameColor(a, b) {
    return String(a) === String(b)
  }

  // Today's border spec for a card at URGENCY (NotificationCard before the
  // consistency pass, unselected).
  function todaysBorderSpec(urgency) {
    return JSON.stringify(Border.surfaceSpec("notifications", "border", urgency === 2 ? Color.urgent : Color.notifications.border, Math.max(1, Style.space(1))))
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
    implicitWidth: 440
    implicitHeight: 1000
    visible: true

    Column {
      id: toasts
      x: 20
      y: 20
      spacing: 8

      // Toast-mode cards, loaded by URL: importing the components directory
      // here as well as through NotificationList fails to register its
      // types.
      Loader {
        id: toastLoader
        source: testRoot.cardUrl
        onLoaded: {
          item.app = "Build"
          item.summary = "Build update"
          item.body = "notification center"
          item.urgency = 1
          item.cornerRadius = 6
        }
      }
      Loader {
        id: critLoader
        source: testRoot.cardUrl
        onLoaded: {
          item.app = "Alarm"
          item.summary = "Battery low"
          item.body = "critical notification"
          item.urgency = 2
          item.cornerRadius = 6
        }
      }
      Loader {
        id: lowLoader
        source: testRoot.cardUrl
        onLoaded: {
          item.app = "Mail"
          item.summary = "Digest"
          item.urgency = 0
          item.cornerRadius = 6
        }
      }
    }
    Connections {
      target: toastLoader.item
      function onCardClicked() {
        toastEvents.push("click")
      }
      function onCloseRequested() {
        toastEvents.push("close")
      }
    }

    Notif.NotificationList {
      id: list
      x: 20
      y: 340
      width: 360
      height: 640
      now: testRoot.now
      rows: rowsOf(baseEntries())
      onAction: function (name, arg) {
        actions.push([name, arg])
      }
    }
  }

  Component.onCompleted: run([[350, function () {
        // ---------- Toasts keep today's look ----------
        t.check(sameColor(toast.color, Color.notifications.background), "a toast's fill is today's")
        t.equal(JSON.stringify(toast.cardBorderSpec), todaysBorderSpec(1), "a toast's border spec is today's")
        t.equal(toast.radius, 6, "a toast keeps its corner radius")
        t.equal(toast.implicitWidth, Style.space(380), "a toast keeps its width")
        var rail = one(toast, "urgencyRail")
        t.equal(rail.width, Style.space(3), "the urgency rail keeps its width")
        t.check(sameColor(rail.color, Color.notifications.countdown), "a normal toast's rail is the countdown colour")
        t.check(Math.abs(rail.opacity - 0.9) < 1e-6, "at today's opacity")
        t.check(sameColor(critToast.color, Util.alpha(Color.urgent, 0.08)), "a critical toast keeps its red tint")
        t.equal(JSON.stringify(critToast.cardBorderSpec), todaysBorderSpec(2), "and its red border")
        t.check(sameColor(one(critToast, "urgencyRail").color, Color.urgent), "and its red rail")
        t.check(sameColor(one(lowToast, "urgencyRail").color, Color.notifications.border), "a low toast's rail is the border colour")
        t.check(Math.abs(one(lowToast, "urgencyRail").opacity - 0.55) < 1e-6, "at today's dimmer opacity")
        t.equal(litOutlines(toasts), 0, "no toast draws a cursor outline")
        t.check(!toast.hovered, "no toast is hovered yet")
        pointer.mouseClick(toast)
        pointer.mouseClick(toast, toast.width / 2, toast.height / 2, Qt.RightButton)
        t.equal(toastEvents, ["click", "close"], "a toast's left and right clicks act at once, unsettled")
        pointer.mouseMove(toast, toast.width / 2, toast.height / 2)
      }], [80, function () {
        pointer.mouseMove(toast, toast.width / 2 + 4, toast.height / 2)
      }], [80, function () {
        t.check(toast.hovered, "a toast under the pointer is hovered (its countdown pauses)")
        t.check(sameColor(toast.color, Util.alpha(Color.notifications.countdown, 0.045)), "and keeps today's hover tint")
        t.equal(litOutlines(toasts), 0, "hover draws no outline on a toast")

        // ---------- Rows ----------
        t.equal(shown(list, "entryCard").length, 3, "one card per visible entry")
        t.equal(shown(list, "groupRow").length, 3, "one header per app group")
        t.equal(shown(list, "moreRow").length, 1, "one +N more row for the collapsed group")
        t.equal(one(list.itemAtIndex(6), "moreText").text, "+3 more", "the +N more text")
        t.equal(list.itemAtIndex(3).rowKey, "e:b1", "a card holds its entry's key")

        // ---------- Hover draws no fill and no outline ----------
        actions = []
        list.disarmPointer()
        var card = list.itemAtIndex(3)
        pointer.mouseMove(card, card.width / 2, card.height / 2)
      }], [80, function () {
        var card = list.itemAtIndex(3)
        pointer.mouseMove(card, card.width / 2 + 4, card.height / 2)
      }], [80, function () {
        var card = list.itemAtIndex(3)
        t.check(card.hovered, "the center card is under the pointer")
        t.check(sameColor(card.color, Color.notifications.background), "hover draws no fill on a center card")
        t.equal(litOutlines(list), 0, "hover draws no outline")
        t.check(reported("hover", {
          index: 3,
          key: "e:b1"
        }), "a real move onto a card reports hover with its key")

        // ---------- The keyboard cursor ----------
        list.cursor = {
          active: false,
          index: 3
        }
        t.equal(litOutlines(list), 0, "no outline without cursor.active")
        list.cursor = {
          active: true,
          index: 3
        }
        t.equal(litOutlines(list), 1, "one outline with cursor.active")
        t.equal(litOutlines(list.itemAtIndex(3)), 1, "on the cursor's card")
        t.check(sameColor(one(list.itemAtIndex(3), "cursorOutline").border.color, Aranea.DesignTokens.accent), "in mint (the accent)")
        t.check(sameColor(list.itemAtIndex(3).color, Color.notifications.background), "the cursor's card keeps its fill")
        list.cursor = {
          active: true,
          index: 6
        }
        t.equal(litOutlines(list), 1, "the cursor moves to the +N more row")
        t.equal(litOutlines(list.itemAtIndex(6)), 1, "which draws the outline")
        list.cursor = {
          active: false,
          index: -1
        }
        t.equal(litOutlines(list), 0, "and none once inactive")

        // ---------- Keyed clicks ----------
        actions = []
        pointer.mouseClick(list.itemAtIndex(3))
        t.check(reported("open", {
          index: 3,
          key: "e:b1"
        }), "a card click opens with its index and key")
        pointer.mouseClick(one(list.itemAtIndex(3), "closeButton"))
        t.check(reported("dismiss", {
          index: 3,
          key: "e:b1"
        }), "the card's close dismisses with its index and key")
        pointer.mouseClick(one(list.itemAtIndex(2), "groupTitle"))
        t.check(reported("toggle", {
          index: 2,
          key: "g:Build"
        }), "a group header click toggles with its index and key")
        pointer.mouseClick(one(list.itemAtIndex(2), "groupClose"))
        t.check(reported("clearGroup", {
          index: 2,
          key: "g:Build"
        }), "the group's close clears it with its index and key")
        pointer.mouseClick(list.itemAtIndex(6))
        t.check(reported("open", {
          index: 6,
          key: "m:Chat"
        }), "a +N more click opens with its index and key")
        t.equal(nonHover().length, 5, "one action per click")
        actions = []
        list.actOn("open", 3, "e:a1")
        t.equal(actions.length, 0, "an action whose key no longer matches its row is refused")
        list.actOn("dismiss", 2, "g:Build")
        t.equal(actions.length, 0, "dismiss on a group header is refused")
        list.actOn("toggle", 3, "e:b1")
        t.equal(actions.length, 0, "toggle on an entry is refused")

        // ---------- A re-sort under a held press ----------
        pressedItem = list.itemAtIndex(3)
        pointer.mousePress(pressedItem)
        list.rows = rowsOf(resortedEntries())
      }], [350, function () {
        t.check(list.itemAtIndex(3) === pressedItem, "the re-sort reused the row")
        t.equal(list.itemAtIndex(3).rowKey, "e:a1", "another entry now sits under the press")
        pointer.mouseRelease(list.itemAtIndex(3))
        t.equal(nonHover().length, 0, "the release past the settle window is refused: the key changed")
        pointer.mouseClick(list.itemAtIndex(3))
        t.check(reported("open", {
          index: 3,
          key: "e:a1"
        }), "a fresh click on the moved row opens the entry now there")

        // ---------- Layout stamps ----------
        stampBefore = list.layoutChangedAt
        list.rows = rowsOf(resortedEntries())
        t.equal(list.layoutChangedAt, stampBefore, "an equal list does not stamp the layout")
      }], [20, function () {
        list.rows = rowsOf(baseEntries())
        t.check(list.layoutChangedAt > stampBefore, "the rows' keys changing stamps the layout")
        stampBefore = list.layoutChangedAt
      }], [20, function () {
        var collapsed = rowsOf(baseEntries(), {
          Build: false
        })
        t.equal(collapsed.map(InboxLogic.rowKey), rowsOf(baseEntries()).map(InboxLogic.rowKey), "collapsing a one-entry group keeps the keys")
        list.rows = collapsed
        t.check(list.layoutChangedAt > stampBefore, "a group collapsing stamps the layout")
        t.equal(one(list.itemAtIndex(2), "groupTitle").text.indexOf("▸"), 0, "and shows it collapsed")
        stampBefore = list.layoutChangedAt
      }], [20, function () {
        var more = baseEntries()
        more.push(entry("c5", "Chat", 70, 1))
        var rows = rowsOf(more)
        t.equal(rows.map(InboxLogic.rowKey), rowsOf(baseEntries()).map(InboxLogic.rowKey), "a hidden arrival keeps the keys")
        list.rows = rows
        t.check(list.layoutChangedAt > stampBefore, "the +N more count changing stamps the layout")
        t.equal(one(list.itemAtIndex(6), "moreText").text, "+4 more", "and shows the new count")
        stampBefore = list.layoutChangedAt
      }], [20, function () {
        list.headerHeight = 48
        t.check(list.layoutChangedAt > stampBefore, "the header height changing stamps the layout")

        // ---------- ClickSettle ----------
        list.rows = rowsOf(baseEntries())
      }], [350, function () {
        list.noteLayoutChange()
        actions = []
        pointer.mouseClick(list.itemAtIndex(3))
        pointer.mouseClick(one(list.itemAtIndex(2), "groupTitle"))
        pointer.mouseClick(list.itemAtIndex(6))
        t.equal(nonHover().length, 0, "clicks right after a stamp are refused")
      }], [40, function () {
        pointer.mouseClick(list.itemAtIndex(3))
        pointer.mouseClick(one(list.itemAtIndex(3), "closeButton"))
        pointer.mouseClick(one(list.itemAtIndex(2), "groupClose"))
        t.equal(nonHover().length, 0, "and still 40 ms later")
      }], [350, function () {
        pointer.mouseClick(list.itemAtIndex(3))
        t.check(reported("open", {
          index: 3,
          key: "e:b1"
        }), "a click 350 ms after the stamp is accepted")

        // ---------- The close tint follows real moves ----------
        list.disarmPointer()
        var close = one(list.itemAtIndex(3), "closeButton")
        stillPoint = close.mapToItem(list, close.width / 2, close.height / 2)
        pointer.mouseMove(list, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(list, stillPoint.x + 2, stillPoint.y)
      }], [80, function () {
        var card = list.itemAtIndex(3)
        t.check(sameColor(one(card, "closeButton").color, Color.notifications.countdown), "a real move onto a card's close tints it")
        list.rows = rowsOf(resortedEntries())
      }], [80, function () {
        var card = list.itemAtIndex(3)
        t.check(sameColor(one(card, "closeButton").color, card.dimColor), "another entry sliding under the pointer drops the tint")
        list.rows = rowsOf(baseEntries())
      }], [80, function () {
        var close = one(list.itemAtIndex(2), "groupClose")
        stillPoint = close.mapToItem(list, close.width / 2, close.height / 2)
        pointer.mouseMove(list, stillPoint.x, stillPoint.y)
        pointer.mouseMove(list, stillPoint.x + 2, stillPoint.y)
      }], [80, function () {
        var group = list.itemAtIndex(2)
        t.check(sameColor(one(group, "groupClose").color, group.accent), "a real move onto a group's close tints it")
        pointer.mouseMove(list, 2, 2)
      }], [80, function () {
        var group = list.itemAtIndex(2)
        t.check(sameColor(one(group, "groupClose").color, group.dim), "and leaving drops the tint")

        // ---------- Still pointer ----------
        list.disarmPointer()
        var card = list.itemAtIndex(5)
        stillPoint = card.mapToItem(list, card.width / 3, card.height / 2)
        actions = []
        pointer.mouseMove(list, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(list, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          index: 5,
          key: "e:c1"
        }), "a real move over a card reports hover")
        actions = []
        var shifted = baseEntries()
        shifted.push(entry("a0", "Alarm", 5, 2))
        list.rows = rowsOf(shifted)
      }], [80, function () {
        pointer.mouseMove(list, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.equal(named("hover").length, 0, "rows shifting under a still pointer emit no hover")
        pointer.mouseMove(list, stillPoint.x + 4, stillPoint.y + 2)
      }], [80, function () {
        t.equal(named("hover").length, 1, "a real move afterwards reports hover again")
      }]])
}
