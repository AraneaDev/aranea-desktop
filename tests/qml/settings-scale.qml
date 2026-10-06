// Real scale page and controller with isolated held subprocess completions.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: root
  // Captured subprocess argv and held callbacks, never real desktop commands.
  property var calls: []
  property var callbacks: []
  QmlTest {
    id: t
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    adapterPath: '/fixture/adapter'
    runner: function (argv, done) {
      root.calls.push(argv)
      root.callbacks.push(done)
    }
  }
  Settings.AppearancePage {
    id: page
    width: 560
    backendState: entry.controller.state
    pending: entry.controller.pending
    pendingKey: entry.controller.pendingKey
    results: entry.controller.results
    errors: entry.controller.itemErrors
    onRequest: function (operation, args) {
      entry.controller.request(operation, args)
    }
  }
  // Return a fresh owner envelope, optionally carrying scaling confirmation.
  function reply(index, state, result, error) {
    callbacks[index](error ? 1 : 0, JSON.stringify({
      schemaVersion: 1,
      ok: !error,
      state: state,
      result: result || null,
      error: error || null
    }), '')
  }
  Component.onCompleted: t.step(20, function () {
    var state = {
      display: {
        monitor: 'eDP-1',
        scale: 2,
        width: 3840,
        height: 2160,
        availability: 'available',
        persistenceSupport: 'supported',
        configuredScale: 2
      }
    }
    entry.controller.state = state
    var input = t.findChild(page, 'displayScaleInput')
    var apply = t.findChild(page, 'displayScaleApply')
    t.check(!!input && !!apply, 'production Appearance includes decimal scale control')
    page.setScaleDraft('2.667')
    t.equal(calls.length, 0, 'editing scale issues zero commands')
    page.applyScale()
    t.equal(calls[0], ['/fixture/adapter', 'set', 'display-scale', '2.667', '--monitor', 'eDP-1', '--json'], 'scale delegates exact typed value and observed display')
    t.equal(entry.controller.resultFor('display-scale'), 'Applying…', 'affected control is Applying')
    t.check(!apply.enabled && !input.enabled, 'competing controls disabled during application')
    t.equal(entry.controller.request('set display-scale', ['2.5']), false, 'one mutation lock covers scale')
    entry.close()
    entry.open('{"section":"appearance"}')
    t.equal(calls.length, 1, 'reopen preserves one in-flight scale request')
    t.equal(page.scaleDraft, '2.667', 'reopen keeps exact requested fraction')
    var result = {
      displayScale: {
        requested: '2.667',
        monitor: 'eDP-1',
        width: 3840,
        height: 2160,
        expectedScale: 2.6666666667,
        effectiveScale: 2.666667,
        confirmed: true,
        persistence: 'persisted'
      }
    }
    state.display.scale = 2.666667
    state.display.configuredScale = 2.66667
    reply(0, state, result)
    t.check(entry.controller.pending, 'owner success needs independent controller read')
    reply(1, state)
    t.check(!entry.controller.pending, 'readback releases lock')
    t.equal(page.scaleDraft, '2.667', 'effective adjustment never overwrites typed request')
    t.check(entry.controller.resultFor('display-scale').indexOf('2.666667') >= 0, 'result includes observed adjusted scale')
    page.setScaleDraft('2.5')
    page.applyScale()
    reply(2, state, null, {
      code: 'FOCUS_CHANGED',
      message: 'Focused display changed. Review the focused display and Apply again.'
    })
    reply(3, {
      display: {
        monitor: 'DP-1',
        scale: 2.5,
        availability: 'available'
      }
    })
    t.equal(entry.controller.resultFor('display-scale'), 'Failed', 'changed focus never confirms another display matching scale')
    t.check(entry.controller.errorFor('display-scale').indexOf('Focused display changed') >= 0, 'changed focus retains actionable error')
    t.equal(calls.length, 4, 'focus failure makes one confirmation and zero automatic retries')
    page.applyScale()
    var shifted = {
      display: {
        monitor: 'DP-1',
        scale: 2.5,
        width: 3840,
        height: 2160,
        availability: 'available'
      }
    }
    var confirmed = {
      displayScale: {
        requested: '2.5',
        monitor: 'DP-1',
        width: 3840,
        height: 2160,
        expectedScale: 2.5,
        confirmed: true,
        persistence: 'session-only'
      }
    }
    reply(4, shifted, confirmed)
    shifted.display.monitor = 'HDMI-A-1'
    reply(5, shifted)
    t.equal(entry.controller.resultFor('display-scale'), 'Application not confirmed', 'later focus change rejects a matching fraction on another display')
    t.check(entry.controller.errorFor('display-scale').indexOf('Review the current display') >= 0, 'later mismatch explains the required action')
    t.check(!entry.controller.pending, 'later mismatch releases lock')
    page.setScaleDraft('2; touch /tmp/x')
    page.applyScale()
    t.equal(calls.length, 6, 'invalid scale does not dispatch')
    page.setScaleDraft('2.5')
    page.displayOnly = true
    t.check(!apply.enabled && !input.enabled, 'showcase disables input and Apply')
    apply.activate()
    page.applyScale()
    t.equal(calls.length, 6, 'showcase UI and programmatic Apply refuse requests')
    entry.showcase(JSON.stringify({
      state: state
    }))
    t.equal(entry.controller.request('set display-scale', ['2.5']), false, 'showcase refuses direct scale mutation')
    t.equal(calls.length, 6, 'showcase direct request issues zero commands')
    entry.close()
    page.displayOnly = false
    entry.controller.state = {
      display: {
        availability: 'unavailable'
      }
    }
    t.check(!apply.enabled, 'missing display disables only scale control')
    apply.activate()
    t.equal(calls.length, 6, 'unavailable scale cannot activate through keyboard path')
    t.done()
  })
}
