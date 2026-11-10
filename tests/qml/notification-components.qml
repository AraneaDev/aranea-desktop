// Behaviour contract for presentational notification components.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.notifications/components" as NotificationComponents

ShellRoot {
  property var invoked: []
  property int cardClicks: 0
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }
  FloatingWindow {
    implicitWidth: 500
    implicitHeight: 400
    visible: true
    NotificationComponents.NotificationCard {
      id: card
      actions: [
        {
          label: "Open"
        },
        {
          label: "Omacut"
        }
      ]
      onActionRequested: function (index) {
        invoked.push(index)
      }
      onCardClicked: cardClicks += 1
    }
  }

  QmlTest {
    id: t
  }

  NotificationComponents.NotificationGroupRow {
    id: row
    app: "Chat"
    count: 3
    collapsed: true
  }

  Component.onCompleted: {
    t.equal(row.app, "Chat", "notification groups expose their app")
    t.equal(row.count, 3, "notification groups expose their count")
    t.equal(row.collapsed, true, "notification groups expose collapsed state")
    t.step(100, function () {
      var buttons = t.findChildren(card, "notificationActionButton")
      t.equal(buttons.length, 2, "two visible action choices")
      t.equal(buttons.map(function (b) {
        return b.label
      }), ["Open", "Omacut"], "visible order follows sender")
      pointer.mouseClick(buttons[1])
      t.equal(invoked, [1], "exactly the selected action emits once")
      t.equal(cardClicks, 0, "button click never invokes the card click")
      var point = buttons[0].mapToItem(card, buttons[0].width / 2, buttons[0].height / 2)
      pointer.mousePress(card, point.x, point.y)
      card.actions = [
        {
          label: "Replaced"
        },
        {
          label: "Omacut"
        }
      ]
      pointer.mouseRelease(card, point.x, point.y)
      t.equal(invoked, [1], "a replaced action set cannot consume an old press")
      t.equal(cardClicks, 0, "replacement release never falls through to the card click")
      buttons = t.findChildren(card, "notificationActionButton")
      point = buttons[0].mapToItem(card, buttons[0].width / 2, buttons[0].height / 2)
      pointer.mousePress(card, point.x, point.y)
      card.actions = []
      pointer.mouseRelease(card, point.x, point.y)
      t.equal(invoked, [1], "removed buttons cannot invoke from a stale press")
      t.equal(cardClicks, 0, "button removal does not trigger the default click")
      t.step(30, function () {
        t.equal(t.findChildren(card, "notificationActionButton").length, 0, "legacy entries render no buttons")
        t.done()
      })
    })
  }
}
