// Production SettingsWindow size/content bindings with only its native boundary adapted.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: host
  // Inert output dimensions supplied to the production window's screen binding.
  property real screenWidth: 1920
  // Reduced outputs exercise the same cap used on small desktops.
  property real screenHeight: 1080
  // Geometry changes and navigation must never contact the settings owner.
  property int commands: 0
  QmlTest {
    id: t
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    opened: true
    runner: function (argv, done) {
      host.commands++
    }
  }
  FloatingWindow {
    implicitWidth: 1000
    implicitHeight: 800
    visible: true
    Settings.SettingsWindow {
      id: panel
      root: entry
      screen: ({
          width: host.screenWidth,
          height: host.screenHeight
        })
      // The inert native boundary is an Item; follow the real window's desired size.
      width: implicitWidth
      height: implicitHeight
    }
  }
  // Find the real scrolling viewport without adding a production test seam.
  function viewport(item) {
    if (item.contentY !== undefined && item.contentHeight !== undefined && item.flickableDirection !== undefined)
      return item
    var kids = t.childrenOf(item)
    for (var i = 0; i < kids.length; i++) {
      var found = viewport(kids[i])
      if (found)
        return found
    }
    return null
  }
  // Bounds must be visible before any scrolling or focus adjustment.
  function inside(item, container) {
    if (!item)
      return false
    var pos = item.mapToItem(container, 0, 0)
    return pos.x >= -1 && pos.x + item.width <= container.width + 1 && pos.y >= -1 && pos.y + item.height <= container.height + 1
  }
  Component.onCompleted: {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    entry.controller.state = {
      screensaver: {
        catalogAvailable: true,
        availability: 'available',
        selectedId: 'silk-journey',
        mode: 'single',
        choices: [
          {
            id: 'silk-journey',
            label: 'Silk Journey',
            available: true
          },
          {
            id: 'silk-chamber',
            label: 'Silk Chamber',
            available: true
          },
          {
            id: 'omarchy',
            label: 'Omarchy',
            available: true
          }
        ],
        idle: {
          screensaverSeconds: 900,
          lockSeconds: 1200
        },
        integration: {
          installed: true,
          reachable: true
        },
        session: {},
        error: null
      }
    }
    entry.section = 'screensavers'
    t.step(200, function () {
      t.equal(panel.geometry.height, 620, 'production Screensavers window requests enough height for both timers')
      t.equal(panel.implicitHeight, 628, 'native desired height includes the existing motion gutter')
      var scroll = viewport(panel)
      t.check(!!scroll && scroll.contentY === 0, 'production content starts at the top')
      var cards = ['silk-journey', 'silk-chamber', 'omarchy'].map(function (id) {
        return t.findChild(panel, 'screensaverChoice:' + id)
      })
      t.check(cards.every(function (card) {
        return inside(card, scroll)
      }), 'all three cards are initially visible')
      t.check(cards[0].x + cards[0].width <= cards[1].x && cards[1].x + cards[1].width <= cards[2].x && cards.every(function (card) {
        return card.y < cards[0].y + cards[0].height && card.y + card.height > cards[0].y
      }), 'wide gallery keeps all three cards on one row')
      t.check(inside(t.findChild(panel, 'screensaverMinutes:screensaverSeconds'), scroll), 'screensaver timing field is initially visible')
      t.check(inside(t.findChild(panel, 'screensaverMinutes:lockSeconds'), scroll), 'lock timing field is initially visible')
      for (var section of ['appearance', 'display', 'schedule', 'integrations', 'notifications']) {
        entry.section = section
        t.equal(panel.geometry.height, 460, section + ' keeps its compact production window')
      }
      entry.section = 'screensavers'
      t.equal(panel.geometry.height, 620, 'returning to Screensavers restores its taller window')
      Style.spacingScale = 2
      host.screenWidth = 3840
      host.screenHeight = 2160
      t.equal(panel.geometry.height, 1240, 'Screensavers desired height follows the host unit scale')
      host.screenWidth = 1280
      host.screenHeight = 720
      t.equal(panel.geometry.height, 624, 'short screen keeps 24 scaled units on both sides')
      Style.spacingScale = 1
      host.screenWidth = 432
      host.screenHeight = 260
      t.step(150, function () {
        t.equal(panel.geometry.height, 212, 'tiny screen caps the taller section to the output')
        t.check(panel.geometry.compact, 'tiny screen keeps compact navigation')
        t.check(scroll.contentHeight > scroll.height, 'tiny screen retains vertical content overflow')
        var late = t.findChild(panel, 'screensaverMinutes:lockSeconds')
        late.forceActiveFocus()
        t.step(80, function () {
          t.check(inside(late, scroll), 'keyboard focus reveals timing on the tiny production window')
          t.check(scroll.contentWidth <= scroll.width + 1, 'tiny production window has no horizontal overflow')
          t.equal(host.commands, 0, 'window geometry, navigation and focus remain read-only')
          t.done()
        })
      })
    })
  }
}
