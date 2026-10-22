// Real production picker exposes unavailable diagnostics without selecting or launching.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: host
  // No diagnostic inspection or disabled activation may reach an owner.
  property int commands: 0
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    name: 'screensavers-unavailable'
    when: false
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: function (argv, done) {
      host.commands++
    }
  }
  FloatingWindow {
    implicitWidth: 840
    implicitHeight: 620
    visible: true
    Settings.SettingsSurface {
      id: surface
      root: entry
      width: 840
      height: 620
    }
  }
  // Locate the production viewport without adding a test seam to the page.
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
  // A rendered item is readable only when its whole bounds fit the viewport.
  function inside(item, container) {
    if (!item || !item.visible || item.width <= 0 || item.height <= 0)
      return false
    var pos = item.mapToItem(container, 0, 0)
    return pos.x >= -1 && pos.x + item.width <= container.width + 1 && pos.y >= -1 && pos.y + item.height <= container.height + 1
  }
  Component.onCompleted: {
    entry.view = surface
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
            available: false,
            reason: 'Silk Chamber needs mpv; install mpv and retry. <b>Keep this diagnostic literal.</b>'
          },
          {
            id: 'omarchy',
            label: 'Omarchy',
            available: false,
            reason: 'Stock launcher missing; repair the Omarchy package.'
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
    t.step(150, function () {
      var page = t.findChild(surface, 'screensaversPage')
      var scroll = viewport(surface)
      var reason = t.findChild(page, 'screensaverUnavailableReason:silk-chamber')
      var stockReason = t.findChild(page, 'screensaverUnavailableReason:omarchy')
      t.check(inside(reason, scroll), 'nonselected unavailable scene reason is rendered and readable')
      t.check(inside(stockReason, scroll), 'every unavailable scene has its own readable reason')
      if (!reason || !stockReason) {
        t.done()
        return
      }
      t.check(reason.text.indexOf('Silk Chamber') >= 0 && reason.text.indexOf('install mpv') >= 0, 'reason identifies its scene and actionable dependency repair')
      t.check(stockReason.text.indexOf('Omarchy') >= 0 && stockReason.text.indexOf('repair the Omarchy package') >= 0, 'other scene retains its distinct actionable repair')
      t.check(reason.text.indexOf('<b>Keep this diagnostic literal.</b>') >= 0, 'owner diagnostic markup remains literal text')
      t.equal(reason.textFormat, Text.PlainText, 'untrusted unavailable diagnostic is PlainText')
      t.equal(reason.Accessible.name, reason.text, 'assistive technology receives the full scene diagnostic')
      t.check(!t.findChild(page, 'screensaverUnavailableReason:silk-journey'), 'available scene has no diagnostic row')
      t.equal(page.selectedId, 'silk-journey', 'reading reasons preserves the available selection')
      var tile = t.findChild(page, 'screensaverChoice:silk-chamber')
      t.check(!tile.enabled, 'unavailable card stays disabled')
      input.mouseMove(tile, 2, 2)
      input.mouseMove(tile, tile.width / 2, tile.height / 2)
      input.mouseClick(tile, tile.width / 2, tile.height / 2)
      tile.forceActiveFocus()
      input.keyClick(Qt.Key_Space)
      tile.activate()
      page.selectScene('silk-chamber')
      t.equal(page.selectedId, 'silk-journey', 'pointer keyboard and direct activation cannot select unavailable scene')
      t.check(!page.sceneDirty, 'diagnostic inspection leaves scene draft clean')
      t.equal(host.commands, 0, 'diagnostic inspection and disabled activation never save or preview')
      // An unavailable remembered choice must still fail every launch/save guard.
      page.selectedId = 'silk-chamber'
      page.sceneDirty = true
      t.check(!t.findChild(page, 'screensaverPreview').enabled && !t.findChild(page, 'screensaverApply').enabled, 'unavailable remembered scene cannot Preview or Apply')
      page.previewScene()
      page.applyScene()
      t.equal(host.commands, 0, 'unavailable remembered scene cannot dispatch a renderer or mutation')
      page.resetDrafts()
      surface.width = 432
      surface.height = 260
      t.step(150, function () {
        t.check(reason.width <= scroll.width + 1 && reason.contentWidth <= reason.width + 1, 'narrow diagnostic wraps without horizontal overflow')
        t.check(reason.height >= reason.contentHeight, 'narrow diagnostic retains its full explanation')
        t.check(scroll.contentWidth <= scroll.width + 1, 'diagnostic rows introduce no horizontal scrolling')
        scroll.forceActiveFocus()
        for (var i = 0; i < 20 && !inside(reason, scroll); i++)
          input.keyClick(Qt.Key_PageDown)
        t.check(scroll.contentY > 0, 'keyboard scrolls toward unavailable reasons')
        t.check(inside(reason, scroll), 'keyboard reveals the full explanation in a narrow short viewport')
        t.equal(page.selectedId, 'silk-journey', 'scrolling diagnostic keeps the available scene selected')
        t.equal(host.commands, 0, 'reading narrow diagnostics has no owner effects')
        t.done()
      })
    })
  }
}
