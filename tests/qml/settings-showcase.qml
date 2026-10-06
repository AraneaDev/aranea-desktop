// Showcase isolation through the persistent controller and production surface.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: root
  // Complete inert owner snapshot.
  property var fixture: ({
      motion: {
        configured: 'on',
        applied: 'on',
        application: 'applied',
        availability: 'available'
      },
      wallpaper: {
        activeId: 'day',
        availability: 'available'
      },
      wallpapers: [
        {
          id: 'day',
          label: 'Day',
          path: '',
          available: true
        },
        {
          id: 'night',
          label: 'Night',
          path: '',
          available: true
        },
        {
          id: 'missing',
          label: 'Missing',
          path: '',
          available: false
        }
      ],
      wallpapersAvailability: 'available',
      schedule: {
        enabled: false,
        applied: false,
        availability: 'available',
        dawn: '06:00',
        day: '08:00',
        dusk: '18:00',
        night: '20:00'
      },
      integrations: [
        {
          id: 'session',
          status: 'inactive',
          availability: 'available'
        },
        {
          id: 'missing',
          status: 'inactive',
          availability: 'unavailable'
        }
      ],
      integrationsAvailability: 'available'
    })
  // Commands and held completions at the process boundary.
  property var calls: []
  // Held subprocess completions for stale-read isolation.
  property var callbacks: []
  QmlTest {
    id: t
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: function (argv, done) {
      root.calls.push(argv)
      root.callbacks.push(done)
    }
  }
  Settings.SettingsSurface {
    id: surface
    root: entry
    width: 840
    height: 620
  }
  // Find the real page by its public method rather than duplicating content.
  function pageWith(item, method) {
    if (typeof item[method] === 'function')
      return item
    var children = t.childrenOf(item)
    for (var i = 0; i < children.length; i++) {
      var found = pageWith(children[i], method)
      if (found)
        return found
    }
    return null
  }
  Component.onCompleted: t.step(20, function () {
    entry.controller.state = fixture
    entry.controller.refresh()
    var original = entry.controller.state
    var sample = JSON.parse(JSON.stringify(fixture))
    sample.wallpaper.activeId = 'night'
    t.equal(entry.showcase(JSON.stringify({
      state: sample,
      notifications: {
        dnd: 'off',
        dndAvailability: 'available',
        quiet: 'scheduled',
        quietAvailability: 'available',
        window: '22:00-07:00',
        windowAvailability: 'available'
      },
      results: {
        'integration:session': 'Failed'
      },
      itemErrors: {
        'integration:session': 'Fixture install failed.'
      }
    })), 'ok', 'showcase accepts inert display snapshot')
    t.check(entry.controller.showcaseActive, 'controller owns display-only mode')
    callbacks[0](0, JSON.stringify({
      schemaVersion: 1,
      ok: true,
      state: fixture,
      error: null
    }), '')
    t.equal(entry.controller.state.wallpaper.activeId, 'night', 'late real read cannot overwrite fixture')
    var before = calls.length
    var requests = [['set motion', ['off']], ['set wallpaper', ['day']], ['set schedule', ['on']], ['configure schedule', ['07:00', '08:00', '18:00', '20:00']], ['set integration', ['session', 'active']], ['set dnd', ['on']]]
    for (var i = 0; i < requests.length; i++)
      t.equal(entry.controller.request(requests[i][0], requests[i][1]), false, 'direct showcase mutation refused: ' + requests[i][0])
    entry.controller.refresh()
    entry.controller.refreshNotifications()
    entry.open('{"section":"integrations"}')
    t.equal(calls.length, before, 'showcase reads and reopen never dispatch processes')
    t.equal(entry.section, 'integrations', 'showcase navigation remains available')
    var appearance = pageWith(surface, 'applyWallpaper')
    appearance.selectWallpaper('day')
    t.check(!t.findChild(appearance, 'wallpaperApply').enabled, 'showcase Apply disabled in UI')
    var buttons = t.findChildren(surface, 'integrationAction')
    t.check(buttons.length > 0 && !buttons[0].enabled, 'showcase integration action disabled in UI')
    t.check(!t.findChild(surface, 'dndToggle').enabled, 'showcase DND disabled in UI')
    t.check(!t.findChild(surface, 'scheduleToggle').enabled, 'showcase schedule disabled in UI')
    appearance.applyWallpaper()
    pageWith(surface, 'save').save()
    buttons[0].activate()
    t.equal(calls.length, before, 'UI and programmatic activation dispatch zero commands')
    entry.close()
    t.check(!entry.controller.showcaseActive, 'close clears showcase')
    t.equal(entry.controller.state, original, 'close restores observed snapshot')
    entry.showcase(JSON.stringify({
      state: {},
      error: 'Unavailable'
    }))
    var retry = t.findChild(surface, 'settingsRetry')
    t.check(retry && !retry.enabled, 'global Retry remains disabled in display-only mode')
    entry.close()
    t.equal(entry.showcase('{"state":null}'), 'invalid', 'malformed fixture refused')
    entry.controller.request('set integration', ['session', 'active'])
    before = calls.length
    t.equal(entry.showcase(JSON.stringify({
      state: sample
    })), 'busy', 'showcase cannot replace running installation')
    t.check(entry.controller.pending, 'installation remains owned')
    t.equal(calls.length, before, 'no retry when showcase refused')
    t.done()
  })
}
