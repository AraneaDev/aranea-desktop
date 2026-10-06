// Exercise the production settings viewport with real wheel, drag and key events.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.settings" as Settings
import "plugins/araneadev.settings/SettingsLogic.js" as Logic

ShellRoot {
  id: host
  // No scrolling or category selection may invoke a desktop owner.
  property int commands: 0
  // Native resolutions and compositor scales become logical screen dimensions.
  readonly property var sizes: [[1920, 1080, 1], [3840, 2160, 2.5], [3840, 2160, 2.667], [1920, 1080, 2.667], [1280, 720, 2], [1280, 720, 2.667]]
  // Page and resolution indices visited by the sequential fixture.
  property int sizeIndex: 0
  // Current category index within the screen matrix.
  property int sectionIndex: 0
  // Repeat the matrix with a real wrapped read failure visible.
  property bool withError: false
  // Stable category identities used by the production host.
  readonly property var sections: ['appearance', 'display', 'schedule', 'integrations', 'notifications']
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    name: 'settingsScroll'
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
    id: window
    implicitWidth: 840
    implicitHeight: 620
    visible: true
    Settings.SettingsSurface {
      id: surface
      width: 840
      height: 620
      root: entry
    }
  }
  // Find the actual viewport independently of an object-name test seam.
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
  // Find a visible text target, including the fixed close and keyboard hint.
  function textItem(item, text) {
    if (item.visible && item.text === text)
      return item
    var kids = t.childrenOf(item)
    for (var i = 0; i < kids.length; i++) {
      var found = textItem(kids[i], text)
      if (found)
        return found
    }
    return null
  }
  // Verify an item stays within the fixed surface or scrolling viewport.
  function inside(item, container) {
    if (!item)
      return false
    var pos = item.mapToItem(container, 0, 0)
    return pos.x >= -1 && pos.x + item.width <= container.width + 1 && pos.y >= -1 && pos.y + item.height <= container.height + 1
  }
  // Check actual visible actionable bounds, including expanded thumbnail targets.
  function checkHorizontal(item, container, label) {
    if (item.visible && (typeof item.activate === 'function' || item.selectByMouse !== undefined || item.objectName === 'toggle')) {
      var pos = item.mapToItem(container, 0, 0)
      t.check(pos.x >= -1 && pos.x + item.width <= container.contentWidth + 1, label + ': horizontal reachability ' + item.objectName)
    }
    var kids = t.childrenOf(item)
    for (var i = 0; i < kids.length; i++)
      checkHorizontal(kids[i], container, label)
  }
  // Pick a late control on every real page, rather than only the first row.
  function lastControl() {
    if (entry.section === 'appearance')
      return t.findChild(surface, 'motionToggle')
    if (entry.section === 'display')
      return t.findChild(surface, 'displayScaleApply')
    if (entry.section === 'schedule')
      return t.findChild(surface, 'scheduleSave')
    if (entry.section === 'integrations') {
      var actions = t.findChildren(surface, 'integrationAction')
      return actions[actions.length - 1]
    }
    return textItem(t.findChild(surface, 'notificationsPage'), 'Retry')
  }
  // Visit one size/page combination, allowing real layout and event delivery.
  function visit() {
    var size = sizes[sizeIndex]
    var geometry = Logic.geometry(size[0] / size[2], size[1] / size[2], 1)
    surface.width = geometry.width
    surface.height = geometry.height
    entry.section = sections[sectionIndex]
    if (entry.section === 'appearance') {
      var chooser = t.findChild(surface, 'wallpaperChoose')
      if (chooser.text === 'Choose wallpaper')
        chooser.activate()
    }
    t.step(120, function () {
      var scroll = viewport(surface)
      var label = size.join('/') + ' ' + entry.section + (withError ? ' error' : '')
      t.check(Math.abs(surface.width - geometry.width) <= 1 && Math.abs(surface.height - geometry.height) <= 1, label + ': production surface uses capped logical geometry ' + surface.width + 'x' + surface.height)
      t.check(!!scroll && scroll.height >= 36, label + ': viewport can expose a complete control')
      t.check(inside(textItem(surface, 'Close'), surface), label + ': Close stays reachable')
      checkHorizontal(scroll.contentItem, scroll, label)

      t.check(inside(textItem(surface, 'Tab move · Enter select · Esc close'), surface), label + ': hint stays within window')
      scroll.contentY = 0
      var overflow = scroll.contentHeight > scroll.height + 1
      var bar = t.findChild(surface, 'settingsScrollBar')
      t.check(!!bar && bar.visible === overflow, label + ': scrollbar indicates overflow only')
      if (overflow)
        input.mouseWheel(scroll, scroll.width / 2, scroll.height / 2, 0, -120, Qt.NoButton)
      t.step(120, function () {
        t.check(!overflow || scroll.contentY > 0, label + ': real wheel scrolls content')
        scroll.cancelFlick()
        scroll.contentY = 0
        scroll.forceActiveFocus()
        input.keyClick(Qt.Key_PageDown)
        t.check(!overflow || scroll.contentY > 0, label + ': PageDown scrolls the viewport')
        input.keyClick(Qt.Key_PageUp)
        t.check(scroll.contentY <= 1, label + ': PageUp returns toward the top')
        scroll.contentY = 0
        var target = lastControl()
        target.forceActiveFocus()
        t.step(40, function () {
          t.check(inside(target, scroll), label + ': keyboard focus reveals the late control')
          t.check(scroll.contentY >= 0 && scroll.contentY <= Math.max(0, scroll.contentHeight - scroll.height) + 1, label + ': scrolling stays bounded')
          if (bar && overflow) {
            scroll.contentY = 0
            input.mousePress(bar, bar.width / 2, bar.height * bar.visualSize / 2)
            input.mouseMove(bar, bar.width / 2, bar.height - 1, 25, Qt.LeftButton)
            input.mouseRelease(bar, bar.width / 2, bar.height - 1)
            t.check(scroll.contentY > 0, label + ': scrollbar drag moves the real viewport')
          }
          t.equal(commands, 0, label + ': scrolling, focusing and navigation are read-only')
          sectionIndex++
          if (sectionIndex === sections.length) {
            sectionIndex = 0
            sizeIndex++
          }
          if (sizeIndex < sizes.length)
            visit()
          else if (!withError) {
            withError = true
            sizeIndex = 0
            entry.controller.error = "Settings owner could not be read. Retry to load the current desktop configuration."
            visit()
          } else
            t.done()
        })
      })
    })
  }
  Component.onCompleted: {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    var wallpapers = []
    var integrations = []
    for (var i = 0; i < 14; i++)
      wallpapers.push({
        id: 'wallpaper-' + i,
        label: 'Wallpaper ' + i,
        path: '',
        available: true
      })
    for (var j = 0; j < 8; j++)
      integrations.push({
        id: 'integration-' + j,
        label: 'Integration ' + j,
        status: 'active',
        availability: 'available'
      })
    entry.controller.state = {
      wallpapers: wallpapers,
      wallpapersAvailability: 'available',
      wallpaper: {
        activeId: 'wallpaper-0',
        availability: 'available'
      },
      motion: {
        configured: 'on',
        applied: 'on',
        availability: 'available',
        application: 'applied'
      },
      display: {
        monitor: 'eDP-1',
        scale: 2.667,
        availability: 'available',
        persistenceSupport: 'supported'
      },
      schedule: {
        availability: 'available',
        enabled: false,
        applied: false,
        dawn: '06:00',
        day: '08:00',
        dusk: '18:00',
        night: '20:00'
      },
      integrations: integrations,
      integrationsAvailability: 'available'
    }
    entry.controller.notifications = {
      dnd: 'off',
      dndAvailability: 'available',
      quiet: 'off',
      quietAvailability: 'available',
      window: 'off',
      windowAvailability: 'available'
    }
    t.step(200, visit)
  }
}
