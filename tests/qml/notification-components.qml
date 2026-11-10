// Behaviour contract for presentational notification components.
import QtQuick
import QtTest
import Quickshell
import qs.Commons as Commons
import "lib"
import "plugins/araneadev.notifications/components" as NotificationComponents

ShellRoot {
  // Records the visible button indices emitted by the real card.
  property var invoked: []
  // Counts default card activations independently of button activations.
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

  // Inspect rendered Text children, preserving the real card presentation.
  function texts(root) {
    var result = []
    t.childrenOf(root).forEach(function (child) {
      if (child.text !== undefined && child.textFormat !== undefined)
        result.push(child)
      result = result.concat(texts(child))
    })
    return result
  }

  // Taildrop filenames, paths and failed previews retain the normal card rendering.
  function checkTaildrop() {
    card.app = "Taildrop"
    card.summary = "File received"
    card.urgency = 2
    card.glyph = "󰒊"
    card.image = "file:///missing/aranea-taildrop-preview.png"
    for (var body of ["holiday photo.png", "/home/test/Downloads/holiday photo.png", "$(touch nope); file.png"]) {
      card.body = body
      var rendered = texts(card)
      var bodyText = rendered.filter(function (item) {
        return item.text === body
      })[0]
      var title = rendered.filter(function (item) {
        return item.text === "File received"
      })[0]
      t.check(bodyText && bodyText.visible, "Taildrop body renders literal filename/path: " + body)
      t.check(title && title.color.toString() === Commons.Color.notifications.text.toString(), "critical Taildrop title retains normal text color")
    }
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
      card.keyboardChoices = true
      card.keyboardClick = true
      card.keyboardChoice = 1
      var labels = t.findChildren(card, "notificationActionLabel")
      t.equal(labels.map(function (label) {
        return label.text
      }), ["2 Open", "3 Omacut"], "numbered buttons follow meaningful card click")
      var clickLabel = t.findChildren(card, "notificationClickChoice")[0]
      t.equal(clickLabel.text, "1 Open notification", "meaningful default click appears before buttons")
      t.check(clickLabel.visible, "default choice is visible in keyboard mode")
      card.keyboardClick = false
      t.equal(labels.map(function (label) {
        return label.text
      }), ["1 Open", "2 Omacut"], "button-only numbering starts at one")
      t.check(!clickLabel.visible, "no guessed click choice is offered")
      card.keyboardChoices = false
      t.equal(labels.map(function (label) {
        return label.text
      }), ["Open", "Omacut"], "leaving keyboard mode removes numbering")
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
        checkTaildrop()
        t.step(50, function () {
          var glyph = texts(card).filter(function (item) {
            return item.text === "󰒊" && item.visible
          })
          t.check(glyph.length > 0, "missing Taildrop preview retains the visible glyph fallback")
          t.done()
        })
      })
    })
  }
}
