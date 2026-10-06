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
    t.equal(surface.captureFocus(), null, 'hidden capture surface without backing Window has no keyboard target')
    entry.view = surface
    entry.opened = true
    entry.section = 'schedule'
    appearance.selectedId = 'night'
    appearance.wallpaperDirty = true
    appearance.galleryExpanded = true
    var schedule = pageWith(surface, 'save')
    schedule.setDraft(0, '07:15')
    var uiBefore = surface.captureSnapshot()
    var captureBefore = entry.captureSnapshot()
    sample.display = {
      scale: 2.666667,
      configuredScale: 2.66667,
      availability: 'available'
    }
    t.equal(entry.captureBegin(JSON.stringify({
      section: 'display',
      snapshot: captureBefore,
      fixture: {
        state: sample,
        displayDraft: 'invalid'
      }
    })), 'invalid', 'malformed fixture draft refuses before capture')
    t.equal(entry.captureBegin(JSON.stringify({
      section: 'appearance',
      snapshot: '{}',
      fixture: {
        state: sample
      }
    })), 'invalid', 'stale snapshot cannot start capture')
    t.equal(entry.captureSnapshot(), captureBefore, 'refused stale snapshot leaves UI and owner intact')
    t.equal(entry.captureBegin(JSON.stringify({
      section: 'display',
      snapshot: captureBefore,
      fixture: {
        displayDraft: '2.667',
        state: sample
      }
    })), 'ok', 'capture accepts fixture before opening')
    t.equal(entry.section, 'display', 'capture routes Display explicitly')
    t.equal(pageWith(surface, 'setScaleDraft').scaleDraft, '2.667', 'capture fixture preserves exact requested scale')
    t.equal(entry.controller.state.display.scale, 2.666667, 'fixture requested fraction stays independent from effective scale')
    t.check(entry.controller.showcaseActive, 'capture enables read-only owner')
    t.equal(entry.controller.request('set wallpaper', ['day']), false, 'capture cannot mutate owner')
    t.equal(entry.captureRestore(captureBefore), 'ok', 'capture restores matching snapshot')
    t.equal(entry.section, 'schedule', 'capture restores section')
    t.check(entry.opened, 'capture restores previously opened surface')
    t.equal(surface.captureSnapshot(), uiBefore, 'capture restores gallery, dirty drafts and scroll state')
    t.equal(entry.controller.state, original, 'capture restores owner observation')
    t.equal(entry.captureBegin('{"section":"unknown","fixture":{"state":{}}}'), 'invalid', 'invalid destination cannot change owner')
    var displayPage = pageWith(surface, 'setScaleDraft')
    displayPage.setScaleDraft('2.5')
    displayPage.detailsExpanded = true
    entry.showcase(JSON.stringify({
      state: sample
    }))
    var priorShowcase = entry.captureSnapshot()
    var priorUi = surface.captureSnapshot()
    t.equal(entry.captureBegin(JSON.stringify({
      section: 'appearance',
      snapshot: priorShowcase,
      fixture: {
        state: fixture
      }
    })), 'ok', 'nested capture accepts prior showcase')
    t.equal(entry.captureRestore('{}'), 'invalid', 'foreign snapshot cannot restore capture')
    t.equal(entry.captureRestore(priorShowcase), 'ok', 'prior showcase restored')
    t.check(entry.controller.showcaseActive, 'prior read-only mode survives capture')
    t.equal(entry.controller.state, sample, 'prior fixture observations restored')
    t.equal(surface.captureSnapshot(), priorUi, 'Display draft and Details survive capture')
    entry.close()
    t.equal(entry.controller.state, original, 'ending restored prior showcase still restores original owner')

    entry.controller.request('set integration', ['session', 'active'])
    before = calls.length
    t.equal(entry.showcase(JSON.stringify({
      state: sample
    })), 'busy', 'showcase cannot replace running installation')
    t.equal(entry.captureBegin(JSON.stringify({
      section: 'appearance',
      snapshot: priorShowcase,
      fixture: {
        state: sample
      }
    })), 'busy', 'capture refuses in-flight mutation')
    t.check(entry.controller.pending, 'installation remains owned')
    t.equal(calls.length, before, 'no retry when showcase refused')
    t.done()
  })
}
