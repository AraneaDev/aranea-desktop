// Real persistent picker lifecycle, with only process boundaries made inert.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: host
  // Refuse the next owner launch.
  property bool refuse: false
  // Current lock observation from the external owner.
  property bool locked: false
  // Fail a session read without fabricating termination.
  property bool unreadable: false
  // Hold a session callback across manual navigation.
  property bool deferRead: false
  // Retained callback for the late-result regressions.
  property var deferred: null
  // Owned session projection returned by the process boundary.
  property var session: ({
      sessionId: 'owned',
      running: true,
      preview: true,
      version: 1
    })
  // Valid owner state returned by the real controller adapter.
  property var owner: ({
      screensaver: {
        availability: 'available',
        catalogAvailable: true,
        selectedId: 'spiderfall',
        mode: 'single',
        choices: [
          {
            id: 'spiderfall',
            available: true
          }
        ],
        session: {}
      }
    })
  QmlTest {
    id: t
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: function (argv, done) {
      if (argv[0].endsWith('/aranea-screensaver')) {
        if (host.deferRead)
          host.deferred = done
        else
          done(host.unreadable ? 1 : 0, host.unreadable ? '' : JSON.stringify({
            session: host.session
          }), '')
        return
      }
      if (argv[1] === 'lock') {
        done(0, host.locked ? 'true' : 'false', '')
        return
      }
      var preview = argv[1] === 'preview'
      if (preview)
        t.check(!entry.opened, 'picker yields focus before renderer launch')
      done(host.refuse && preview ? 1 : 0, JSON.stringify({
        schemaVersion: 1,
        ok: !(host.refuse && preview),
        state: host.owner,
        result: preview ? {
          screensaverPreview: {
            accepted: !host.refuse,
            sessionId: 'owned'
          }
        } : {},
        error: host.refuse && preview ? {
          code: 'HELPER_FAILED',
          message: 'Busy'
        } : null
      }), '')
    }
  }
  // Launch through the production controller from an open picker.
  function start() {
    entry.opened = true
    entry.section = 'screensavers'
    entry.controller.state = owner
    session = {
      sessionId: 'owned',
      running: true,
      preview: true,
      version: 1
    }
    t.check(entry.controller.request('preview screensaver', ['spiderfall']), 'production controller accepts preview')
  }
  Component.onCompleted: t.step(100, function () {
    start()
    entry.pollPreview()
    t.check(!entry.opened, 'live owned preview keeps picker hidden')
    t.equal(entry.captureBegin('{}'), 'busy', 'capture cannot replace active preview lifecycle')
    unreadable = true
    entry.pollPreview()
    t.check(!entry.opened && entry.previewReturn, 'unreadable status cannot steal focus')
    unreadable = false
    session = {
      sessionId: 'owned',
      running: false,
      preview: true,
      version: 1,
      error: 'Renderer failed'
    }
    entry.pollPreview()
    t.check(entry.opened, 'startup failure returns picker')
    t.equal(entry.section, 'screensavers', 'return retains picker destination')
    t.equal(entry.controller.state.screensaver.session.error, 'Renderer failed', 'runtime failure is visible on return')

    refuse = true
    start()
    t.check(entry.opened && !entry.previewReturn, 'refused launch restores picker immediately')
    locked = true
    start()
    t.check(!entry.opened && !entry.previewReturn, 'lock rejection never summons picker')
    locked = false
    refuse = false
    start()
    session = {
      sessionId: 'foreign',
      running: true
    }
    entry.pollPreview()
    t.check(!entry.opened && !entry.previewReturn, 'foreign session cancels automatic return')

    start()
    locked = true
    session = {
      sessionId: 'owned',
      running: false
    }
    entry.pollPreview()
    t.check(!entry.opened && !entry.previewReturn, 'lock never summons picker')
    locked = false

    start()
    deferRead = true
    entry.pollPreview()
    entry.close()
    deferred(0, JSON.stringify({
      session: {
        sessionId: 'owned',
        running: false
      }
    }), '')
    t.check(!entry.opened, 'late callback cannot undo manual close')
    deferRead = false

    start()
    deferRead = true
    entry.pollPreview()
    entry.open('{"section":"appearance"}')
    deferred(0, JSON.stringify({
      session: {
        sessionId: 'owned',
        running: false
      }
    }), '')
    t.check(entry.opened && entry.section === 'appearance', 'late callback cannot replace manual navigation')
    deferRead = false
    entry.close()
    start()
    session = {
      sessionId: 'owned',
      running: false
    }
    t.step(1000, function () {
      t.check(entry.opened && !entry.previewReturn, 'timer returns the picker without user intervention')
      entry.close()
      t.done()
    })
  })
}
