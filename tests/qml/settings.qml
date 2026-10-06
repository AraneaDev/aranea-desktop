// Controller behavior exercised through held process completions.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: testRoot
  // Captured argv dispatched by the real controller.
  property var calls: []
  // Held subprocess completions used to exercise ordering.
  property var callbacks: []
  // Complete healthy adapter fixture with independent owner readback.
  property var healthy: ({
      motion: {
        configured: 'on',
        applied: 'on',
        availability: 'available',
        application: 'applied'
      },
      wallpaper: {
        activeId: 'day',
        availability: 'available'
      },
      wallpapers: [
        {
          id: 'day',
          label: 'Day',
          path: '/fixture/day.png',
          available: true
        },
        {
          id: 'missing',
          label: 'Missing',
          path: '/fixture/missing.png',
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
        }
      ],
      integrationsAvailability: 'available'
    })
  QmlTest {
    id: t
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    adapterPath: '/fixture/theme path/scripts/aranea-settings'
    runner: function (argv, done) {
      testRoot.calls.push(argv)
      testRoot.callbacks.push(done)
    }
  }
  // Complete a held subprocess with a versioned adapter envelope.
  function reply(index, state, code, error) {
    callbacks[index](code || 0, JSON.stringify({
      schemaVersion: 1,
      ok: !error,
      state: state,
      error: error || null
    }), '')
  }
  Component.onCompleted: {
    entry.controller.refresh()
    reply(0, null, 2, {
      code: 'DEPENDENCY_MISSING',
      message: 'jq unavailable'
    })
    t.equal(entry.controller.state, ({}), 'read failure invents no state')
    t.check(!!entry.controller.error, 'read failure offers an error')
    entry.controller.refresh()
    entry.controller.refresh()
    reply(2, healthy)
    reply(1, null, 1, {
      code: 'STATE_UNAVAILABLE',
      message: 'old error'
    })
    t.equal(entry.controller.state.motion.configured, 'on', 'older responses cannot replace latest state')
    t.equal(entry.controller.error, '', 'old failures cannot replace latest success')
    var start = calls.length
    entry.controller.request('set motion', ['off'])
    t.equal(calls[start], ['/fixture/theme path/scripts/aranea-settings', 'set', 'motion', 'off', '--json'], 'motion is argv with spaced adapter path')
    t.check(entry.controller.pending, 'mutation is pending')
    t.equal(entry.controller.refresh(), false, 'ordinary refresh cannot invalidate pending confirmation')
    t.equal(entry.controller.request('set integration', ['session', 'active']), false, 'competing mutation refused')
    var deferred = JSON.parse(JSON.stringify(healthy))
    deferred.motion = {
      configured: 'off',
      applied: null,
      availability: 'available',
      application: 'deferred'
    }
    reply(start, deferred)
    t.check(entry.controller.pending, 'pending survives until explicit readback')
    reply(start + 1, deferred)
    t.equal(entry.controller.resultFor('motion'), 'Saved · application deferred', 'saved deferred motion is never Applied')
    t.check(!entry.controller.pending, 'readback releases lock')
    start = calls.length
    entry.controller.request('set integration', ['session', 'active'])
    entry.close()
    t.check(entry.controller.pending, 'close does not cancel installation')
    entry.open('{"section":"schedule"}')
    t.check(entry.controller.pending, 'reopen cannot overlap installation')
    t.equal(entry.section, 'schedule', 'open routes to schedule')
    reply(start, healthy, 23, {
      code: 'HELPER_FAILED',
      message: 'installation failed'
    })
    reply(calls.length - 1, healthy)
    t.equal(entry.controller.resultFor('integration:session'), 'Failed', 'mutation failures remain visible after readback')
    t.equal(entry.controller.errorFor('integration:session'), 'installation failed', 'integration keeps per-item error')
    t.check(!entry.controller.pending, 'failed mutation releases lock without retry')
    start = calls.length
    t.equal(entry.controller.request('configure schedule', ['08:00', '06:00', '18:00', '20:00']), false, 'invalid schedule cannot invoke helper')
    t.equal(calls.length, start, 'invalid schedule executes zero commands')
    entry.controller.refreshNotifications()
    var dnd = calls.length - 3
    callbacks[dnd](0, 'off', '')
    callbacks[dnd + 1](0, 'scheduled', '')
    callbacks[dnd + 2](0, '22:00-07:00', '')
    t.equal(entry.controller.notifications.dnd, 'off', 'DND read independent of backend')
    start = calls.length
    entry.controller.request('set dnd', ['on'])
    t.equal(calls[start], ['omarchy-shell', 'notifications', 'setDnd', 'on'], 'DND delegates to service IPC')
    callbacks[start](0, 'on', '')
    t.check(entry.controller.pending, 'DND write output alone is not Applied')
    callbacks[start + 1](0, 'off', '')
    t.equal(entry.controller.resultFor('dnd'), 'Application not confirmed', 'mismatched DND readback is not Applied')
    entry.controller.refreshNotifications()
    callbacks[calls.length - 3](1, '', 'IPC unavailable')
    t.equal(entry.controller.notifications.dnd, null, 'unavailable IPC clears observed DND')
    t.equal(entry.controller.notifications.dndAvailability, 'unavailable', 'unavailable DND disables only that control')
    t.done()
  }
}
