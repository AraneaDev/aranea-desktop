// Real production picker, controller, fields and capture transaction, with inert owners.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: host
  // Exact process requests observed by the inert adapter.
  property var commands: []
  // Inject a refused preview without starting a renderer.
  property bool failPreview: false
  // Inject a failed scene preference mutation.
  property bool failSave: false
  // Persist timing but report failed shell reload.
  property bool failTimingReload: false
  // Inject an unavailable independent confirmation read.
  property bool failReadback: false
  // Authoritative fake owner data returned through the real controller.
  property var owner: ({
      screensaver: {
        catalogAvailable: true,
        availability: 'available',
        selectedId: 'silk-journey',
        mode: 'single',
        choices: [
          {
            id: 'silk-journey',
            label: '<b>Silk Journey</b>',
            description: 'Web scene',
            available: true,
            thumbnail: null,
            shuffleEligible: true
          },
          {
            id: 'silk-chamber',
            label: 'Silk Chamber',
            available: true,
            thumbnail: null,
            shuffleEligible: true
          },
          {
            id: 'omarchy',
            label: 'Omarchy',
            available: false,
            reason: 'Stock launcher missing',
            thumbnail: null,
            shuffleEligible: false
          }
        ],
        idle: {
          screensaverSeconds: 150,
          lockSeconds: 1200,
          stayAwake: true,
          screensaverOff: false
        },
        integration: {
          installed: false,
          reachable: false
        },
        session: {},
        error: null
      }
    })
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    when: false
    name: 'screensavers-input'
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: function (argv, done) {
      host.commands = host.commands.concat([argv])
      var state = JSON.parse(JSON.stringify(host.owner))
      var result = {}
      var ok = true
      if (argv[1] === 'configure' && argv[2] === 'screensaver' && !host.failSave) {
        host.owner.screensaver.selectedId = argv[3]
        host.owner.screensaver.mode = argv[4]
        state = JSON.parse(JSON.stringify(host.owner))
      }
      if (argv[1] === 'configure' && argv[2] === 'screensaver-timing') {
        host.owner.screensaver.idle.screensaverSeconds = Number(argv[3])
        host.owner.screensaver.idle.lockSeconds = Number(argv[4])
        state = JSON.parse(JSON.stringify(host.owner))
        result.screensaverTiming = {
          persisted: true,
          applied: !host.failTimingReload
        }
        ok = !host.failTimingReload
      }
      if (argv[1] === 'preview') {
        result.screensaverPreview = {
          accepted: !host.failPreview,
          sessionId: 'fake'
        }
        ok = !host.failPreview
      }
      if (argv[1] === 'configure' && host.failSave)
        ok = false
      if (argv[1] === 'status' && host.failReadback) {
        state = {}
        ok = false
      }
      done(ok ? 0 : 1, JSON.stringify({
        schemaVersion: 1,
        ok: ok,
        state: state,
        result: result,
        error: ok ? null : {
          code: 'HELPER_FAILED',
          message: host.failTimingReload ? 'Timing saved but not applied: reload failed' : 'Retry saved preference'
        }
      }), '')
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
  Component.onCompleted: t.step(150, function () {
    entry.view = surface
    entry.controller.state = JSON.parse(JSON.stringify(owner))
    entry.section = 'screensavers'
    var page = t.findChild(surface, 'screensaversPage')
    t.check(!!page, 'production picker exists')
    if (!page) {
      t.done()
      return
    }
    t.equal(page.selectedId, 'silk-journey', 'initial draft reads owner')
    t.equal(page.timingDraft.screensaverSeconds, 150, 'initial exact seconds retained')
    t.equal(commands.length, 0, 'render and navigation have no process effects')
    t.check(t.findChild(page, 'screensaverCurrent').text.indexOf('<b>Silk Journey</b>') >= 0, 'current summary preserves catalog label as text')
    t.equal(t.findChild(page, 'screensaverCurrent').textFormat, Text.PlainText, 'owner label never interprets markup')
    var tile = t.findChild(page, 'screensaverChoice:silk-chamber')
    var countBeforeClick = commands.length
    surface.stampLayout()
    input.mouseClick(tile, tile.width / 2, tile.height / 2)
    t.equal(page.selectedId, 'silk-journey', 'pointer cannot activate without movement after layout')
    t.equal(commands.length, countBeforeClick, 'guarded pointer has no owner effects')
    tile.forceActiveFocus()
    input.keyClick(Qt.Key_Space)
    t.equal(page.selectedId, 'silk-chamber', 'keyboard selects production card')
    t.equal(owner.screensaver.selectedId, 'silk-journey', 'tile never persists')
    entry.opened = true
    t.findChild(page, 'screensaverPreview').activate()
    t.equal(entry.opened, false, 'accepted Preview hides Settings overlay')
    t.equal(page.selectedId, 'silk-chamber', 'Preview retains draft')
    t.equal(owner.screensaver.selectedId, 'silk-journey', 'Preview never saves selection')
    t.equal(entry.controller.resultFor('screensaver-preview'), 'Preview accepted', 'preview result persists on controller')
    t.findChild(page, 'screensaverShuffle').activate()
    t.equal(page.modeDraft, 'shuffle', 'shuffle edits mode locally')
    t.equal(tile.selected, false, 'shuffle clears tile highlight')
    t.findChild(page, 'screensaverApply').activate()
    t.equal(owner.screensaver.mode, 'shuffle', 'Apply persists mode')
    t.equal(page.sceneDirty, false, 'matching readback acknowledges scene draft')
    tile.activate()
    t.equal(page.modeDraft, 'single', 'scene click returns to single')
    host.failSave = true
    t.findChild(page, 'screensaverApply').activate()
    t.check(page.sceneDirty, 'failed scene Apply retains draft')
    t.check(!!entry.controller.errorFor('screensaver'), 'failed scene Apply retains error')
    host.failSave = false
    host.failReadback = true
    t.findChild(page, 'screensaverApply').activate()
    t.check(page.sceneDirty, 'unreadable independent readback retains scene draft')
    t.equal(entry.controller.resultFor('screensaver'), 'Save not confirmed', 'unreadable readback cannot claim Saved')
    host.failReadback = false
    entry.controller.refresh()
    // Restore the last confirmed shuffle state for the explicit Discard assertion.
    host.owner.screensaver.mode = 'shuffle'
    entry.controller.refresh()
    t.findChild(page, 'screensaverDiscard').activate()
    t.equal(page.modeDraft, 'shuffle', 'scene Discard reads authoritative mode')
    var missing = t.findChild(page, 'screensaverChoice:omarchy')
    missing.activate()
    t.equal(page.selectedId, 'silk-chamber', 'unavailable card cannot select')
    var field = t.findChild(page, 'screensaverMinutes:lockSeconds')
    field.forceActiveFocus()
    input.keyClick(Qt.Key_A, Qt.ControlModifier)
    input.keyClick(Qt.Key_2)
    input.keyClick(Qt.Key_1)
    t.equal(page.timingDraft.lockSeconds, 1260, 'production minutes field edits local seconds')
    t.equal(page.timingDraft.screensaverSeconds, 150, 'editing other field preserves exact seconds')
    var before = commands.length
    t.findChild(page, 'screensaverPreview').activate()
    t.equal(owner.screensaver.idle.lockSeconds, 1200, 'Preview never saves timing')
    t.findChild(page, 'screensaverTimingApply').activate()
    t.equal(owner.screensaver.idle.screensaverSeconds, 150, 'timing Apply preserves unedited exact seconds')
    t.equal(owner.screensaver.idle.lockSeconds, 1260, 'timing Apply saves edited minutes')
    t.equal(page.timingDirty, false, 'timing readback clears acknowledged draft')
    t.check(commands.length > before, 'explicit controls dispatch commands')
    t.findChild(page, 'screensaverDisabled:lockSeconds').activate()
    t.equal(page.timingDraft.lockSeconds, 0, 'Disabled is explicit zero choice')
    host.failTimingReload = true
    t.findChild(page, 'screensaverTimingApply').activate()
    t.check(page.timingDirty, 'saved but reload failed retains timing draft')
    t.equal(entry.controller.resultFor('screensaver-timing'), 'Saved · reload failed', 'reload failure never claims Applied')
    t.check(!!entry.controller.errorFor('screensaver-timing'), 'timing error retained')
    host.failTimingReload = false
    t.findChild(page, 'screensaverTimingDiscard').activate()
    t.equal(page.timingDirty, false, 'timing Discard clears local edits')
    entry.opened = true
    host.failPreview = true
    t.findChild(page, 'screensaverPreview').activate()
    t.check(entry.opened, 'failed Preview retains Settings presentation')
    t.check(!!entry.controller.errorFor('screensaver-preview'), 'failed Preview retains controller error')
    host.failPreview = false
    page.setTimingDraft('lockSeconds', '30')
    tile.activate()
    var saved = entry.captureSnapshot()
    var count = commands.length
    t.equal(entry.captureBegin(JSON.stringify({
      snapshot: saved,
      section: 'screensavers',
      fixture: {
        state: owner
      }
    })), 'ok', 'capture accepts screensavers')
    tile.activate()
    page.setTimingDraft('lockSeconds', '40')
    page.applyScene()
    page.applyTiming()
    page.previewScene()
    t.equal(commands.length, count, 'showcase blocks every mutation and renderer')
    t.check(entry.opened, 'showcase Preview cannot hide Settings')
    t.equal(entry.captureRestore(saved), 'ok', 'capture restores transaction')
    t.equal(page.timingDraft.lockSeconds, 1800, 'capture restores timing draft')
    t.check(page.sceneDirty && page.timingDirty, 'capture restores independent dirty state')
    t.equal(page.selectedId, 'silk-chamber', 'capture restores remembered single selection')
    t.equal(page.modeDraft, 'single', 'capture restores gallery highlight mode')
    surface.width = 432
    surface.height = 260
    t.step(150, function () {
      t.check(page.width <= surface.width, 'narrow page stays inside viewport')
      t.check(page.implicitHeight > surface.height, 'short screen scrolls content')
      t.findChild(page, 'screensaverTimingDiscard').activate()
      page.setTimingDraft('lockSeconds', '2.5')
      t.check(!t.findChild(page, 'screensaverTimingApply').enabled, 'edited fractional minutes cannot save')
      page.discardTiming()
      page.setTimingDraft('lockSeconds', '30')
      host.failReadback = true
      t.findChild(page, 'screensaverTimingApply').activate()
      t.check(page.timingDirty, 'unreadable timing readback retains draft')
      t.equal(entry.controller.resultFor('screensaver-timing'), 'Save not confirmed', 'reload acknowledgment alone cannot claim timing save readback')
      host.failReadback = false
      var partial = JSON.parse(JSON.stringify(owner))
      partial.screensaver.selectedId = 'unknown'
      partial.screensaver.catalogAvailable = false
      partial.screensaver.session = {
        running: false,
        ready: false,
        error: 'Renderer startup failed. Retry.'
      }
      entry.controller.state = partial
      page.resetDrafts()
      t.check(!!t.findChild(page, 'screensaverRuntimeError') && t.findChild(page, 'screensaverRuntimeError').text === 'Renderer startup failed. Retry.', 'asynchronous runtime startup error remains visible from session readback')
      t.equal(page.selectedId, 'unknown', 'unknown selected identity is retained honestly')
      t.check(!t.findChild(page, 'screensaverApply').enabled, 'unavailable catalog cannot apply scene')
      page.setTimingDraft('lockSeconds', '40')
      t.check(t.findChild(page, 'screensaverTimingApply').enabled, 'timing is editable independently of broken scene owner')
      entry.controller.pending = true
      var beforePending = commands.length
      page.previewScene()
      page.applyScene()
      page.applyTiming()
      page.selectScene('silk-journey')
      t.equal(commands.length, beforePending, 'pending controller gates all action paths')
      entry.controller.pending = false
      page.setTimingDraft('screensaverSeconds', '1441')
      t.check(!t.findChild(page, 'screensaverTimingApply').enabled, 'UI rejects more than 1440 minutes')
      page.setTimingDraft('screensaverSeconds', '1440')
      t.check(!t.findChild(page, 'screensaverTimingApply').enabled, 'enabled lock must follow saver')
      t.findChild(page, 'screensaverDisabled:lockSeconds').activate()
      t.check(t.findChild(page, 'screensaverTimingApply').enabled, 'explicit disabled lock permits 1440-minute saver')
      page.setTimingDraft('screensaverSeconds', '0')
      t.check(!t.findChild(page, 'screensaverTimingApply').enabled, 'typing zero cannot silently choose Disabled')
      page.setTimingDraft('screensaverSeconds', '1')
      t.check(t.findChild(page, 'screensaverTimingApply').enabled, 'one whole minute is valid')
      t.done()
    })
  })
}
