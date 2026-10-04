// The notification center fits its card: a list too long for the card's
// content height is capped (InboxLogic.listHeight, as Panel.qml sizes it
// from slotTop and footerHeight), so the whole footer, the Clear pill and
// the key hint, stays at or above the content bottom and the list scrolls
// inside the rest; a short list keeps its full height. The header shows
// the bell glyph like the other dropdowns. Both key hints fit the card's
// content width unelided, the full one with a 10% margin.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.notifications" as Notif
import "plugins/araneadev.notifications/InboxLogic.js" as InboxLogic

ShellRoot {
  id: testRoot

  // Test start in ms; entry timestamps are relative to it.
  readonly property real now: Date.now()

  QmlTest {
    id: t
  }

  // An inbox entry FILE from APP, AGE seconds old, at URGENCY.
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

  // N entries, each from its own app, so none collapse.
  function entries(n) {
    var out = []
    for (var i = 0; i < n; i++)
      out.push(entry("f" + i, "App" + i, 10 + i, 1))
    return out
  }

  // The header view for COUNT unread.
  function viewOf(count) {
    return {
      count: count,
      caption: count + " unread",
      dnd: {
        on: false,
        busy: false
      },
      clear: {
        visible: count > 0,
        confirming: false,
        label: "Clear all"
      },
      keyHint: InboxLogic.centerKeyHint(count)
    }
  }

  // The card's content width as Panel.qml sizes it: the panel width less
  // its padding and border on both sides.
  readonly property real innerWidth: Style.space(380) - 2 * Style.spacing.popupPadding - 2 * Math.max(1, Style.space(2))

  // The bottom of ITEM in FRAME's coordinates.
  function bottomIn(item, frame) {
    return item.mapToItem(frame, 0, item.height).y
  }

  FloatingWindow {
    implicitWidth: 840
    implicitHeight: 460
    visible: true

    // The card's content area (inside padding and border), 400 high.
    Item {
      id: longFrame
      x: 20
      y: 20
      width: testRoot.innerWidth
      height: 400

      Notif.NotificationCenterContent {
        id: longCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        view: viewOf(12)

        Notif.NotificationList {
          id: longList
          width: parent.width
          height: InboxLogic.listHeight(longList.contentHeight, longFrame.height, longCenter.slotTop, longCenter.footerHeight)
          rows: InboxLogic.centerRows(entries(12), {})
          now: testRoot.now
        }
      }
    }

    Item {
      id: shortFrame
      x: 440
      y: 20
      width: testRoot.innerWidth
      height: 400

      Notif.NotificationCenterContent {
        id: shortCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        view: viewOf(1)

        Notif.NotificationList {
          id: shortList
          width: parent.width
          height: InboxLogic.listHeight(shortList.contentHeight, shortFrame.height, shortCenter.slotTop, shortCenter.footerHeight)
          rows: InboxLogic.centerRows(entries(1), {})
          now: testRoot.now
        }
      }
    }
  }

  // The empty center: no list, the short hint.
  FloatingWindow {
    implicitWidth: 420
    implicitHeight: 300
    visible: true

    Notif.NotificationCenterContent {
      id: emptyCenter
      x: 20
      y: 20
      width: testRoot.innerWidth
      view: viewOf(0)
    }
  }

  Component.onCompleted: t.step(400, function () {
    t.check(longList.contentHeight > longList.height + 1, "a long list is capped (content " + longList.contentHeight + ", height " + longList.height + ")")
    t.check(longCenter.implicitHeight <= longFrame.height + 0.5, "the center fits the content area (" + longCenter.implicitHeight + " <= " + longFrame.height + ")")
    var hint = t.findChild(longCenter, "keyHint")
    var pill = t.findChild(longCenter, "clearPill")
    t.check(hint !== null && bottomIn(hint, longFrame) <= longFrame.height + 0.5, "the key hint ends at or above the content bottom (" + (hint ? bottomIn(hint, longFrame) : -1) + ")")
    t.check(pill !== null && bottomIn(pill, longFrame) <= hint.mapToItem(longFrame, 0, 0).y + 0.5, "the Clear pill sits above the key hint")
    t.check(bottomIn(longList, longFrame) <= pill.mapToItem(longFrame, 0, 0).y + 0.5, "the list ends above the Clear pill")
    t.check(Math.abs(shortList.height - shortList.contentHeight) < 0.5 && shortList.height > 0, "a short list keeps its full height")
    t.check(bottomIn(t.findChild(shortCenter, "keyHint"), shortFrame) <= shortFrame.height, "and its footer fits too")
    // A 10% margin: the live shell's font and spacing scale differ from
    // this harness, and a hint that only just fit here was elided live.
    t.check(hint.implicitWidth <= hint.width * 0.9, "the full key hint fits the card unelided, with a margin (" + hint.implicitWidth + " <= 0.9 * " + hint.width + ")")
    t.equal(hint.text, InboxLogic.centerKeyHint(12), "with entries the hint names every key")
    var emptyHint = t.findChild(emptyCenter, "keyHint")
    t.equal(emptyHint.text, "↑↓ move · enter toggle", "the empty center shows the short hint")
    t.check(emptyHint.implicitWidth <= emptyHint.width + 0.5, "and it fits")
    var title = t.findChild(longCenter, "centerHeader")
    t.equal(title.glyph, String.fromCodePoint(0xf009a), "the header shows the bell glyph when the view gives none")
    t.done()
  })
}
