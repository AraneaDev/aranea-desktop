// The Quick switcher row asks only the controller; a fake runner stands in for the helper.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: host
  // Requests emitted by the page.
  property var requests: []
  // Commands the fake runner saw, never run for real.
  property var commands: []
  // Next status answer the fake helper gives.
  property bool fakeBound: false
  // Make the fake helper answer garbage.
  property bool failStatus: false
  // Commands seen by the first-open Settings fixture.
  property var openCommands: []
  QmlTest {
    id: t
  }
  TestCase {
    id: keys
    when: false
  }
  Settings.Settings {
    id: firstOpen
    windowEnabled: false
    runner: function (argv, done) {
      host.openCommands = host.openCommands.concat([argv.join(' ')])
    }
  }
  FloatingWindow {
    visible: true
    width: 400
    height: 700
    Settings.IntegrationsPage {
      id: page
      width: 400
      backendState: ({
          integrationsAvailability: 'available',
          integrations: [],
          keybind: {
            bound: false,
            key: null
          }
        })
      onRequest: function (operation, args) {
        host.requests = host.requests.concat([[operation, args]])
      }
    }
  }
  Settings.SettingsController {
    id: controller
    keybindPath: '/fake/aranea-keybind'
    runner: function (argv, done) {
      host.commands = host.commands.concat([argv.slice(1).join(' ')])
      var sub = argv[1]
      if (host.failStatus)
        return done(1, '', 'Could not run the shortcut helper.')
      if (sub === 'add')
        host.fakeBound = true
      if (sub === 'remove')
        host.fakeBound = false
      if (sub === 'add' && argv[3] === 'TAKEN')
        return done(1, JSON.stringify({
          ok: false,
          data: null,
          error: {
            code: 'KEY_TAKEN',
            message: 'That key is already used by Omarchy menu.',
            recovery: 'Choose another key.'
          }
        }), '')
      done(0, JSON.stringify({
        ok: true,
        data: {
          bound: host.fakeBound,
          key: host.fakeBound ? 'SUPER + ALT + P' : null
        },
        error: null
      }), '')
    }
  }
  // Find a named control in the page.
  function child(name) {
    return t.findChild(page, name)
  }
  Component.onCompleted: t.step(50, function () {
    t.equal(child('quickSwitcherState').text, 'Not set', 'unbound state reads Not set')
    t.equal(child('quickSwitcherKey').text, 'SUPER + ALT + P', 'default key prefilled')
    t.equal(child('quickSwitcherAdd').text, 'Add to bindings', 'Add button label')
    child('quickSwitcherKey').text = ''
    t.check(!child('quickSwitcherAdd').enabled, 'Add disabled when the field is empty')
    child('quickSwitcherKey').text = '   '
    t.check(!child('quickSwitcherAdd').enabled, 'Add disabled when the field is blank')
    child('quickSwitcherKey').text = 'SUPER + CTRL + O'
    t.check(!child('quickSwitcherRemove').visible, 'Remove hidden when unbound')
    child('quickSwitcherAdd').clicked()
    t.equal(host.requests, [['keybind-add',
        {
          key: 'SUPER + CTRL + O'
        }
      ]], 'Add sends the edited key')
    // Enter in the key field submits when Add is enabled, and does nothing when it is not.
    host.requests = []
    child('quickSwitcherKey').forceActiveFocus()
    keys.keyClick(Qt.Key_Return)
    t.equal(host.requests, [['keybind-add',
        {
          key: 'SUPER + CTRL + O'
        }
      ]], 'Enter in the key field adds the binding')
    child('quickSwitcherKey').text = ' '
    host.requests = []
    keys.keyClick(Qt.Key_Return)
    t.equal(host.requests, [], 'Enter does nothing while Add is disabled')
    child('quickSwitcherKey').text = 'SUPER + CTRL + O'
    page.backendState = {
      integrations: [],
      keybind: {
        bound: true,
        key: 'SUPER + ALT + P'
      }
    }
    t.equal(child('quickSwitcherState').text, 'SUPER + ALT + P', 'bound state shows key')
    t.equal(child('quickSwitcherKey').text, 'SUPER + ALT + P', 'the field shows the bound key')
    t.check(child('quickSwitcherRemove').visible, 'Remove visible when bound')
    host.requests = []
    child('quickSwitcherRemove').clicked()
    t.equal(host.requests, [['keybind-remove',
        {}
      ]], 'Remove requests removal')
    page.errors = {
      keybind: {
        code: 'KEY_TAKEN',
        message: 'That key is already used by Omarchy menu.',
        recovery: 'Choose another key.'
      }
    }
    t.equal(child('quickSwitcherError').text, 'That key is already used by Omarchy menu. Choose another key.', 'error shows message and recovery')
    page.displayOnly = true
    host.requests = []
    t.check(!child('quickSwitcherAdd').enabled && !child('quickSwitcherRemove').enabled, 'inert when displayOnly')
    child('quickSwitcherAdd').clicked()
    child('quickSwitcherRemove').clicked()
    t.equal(host.requests, [], 'displayOnly emits nothing')
    page.displayOnly = false
    controller.reopened()
    t.step(50, function () {
      t.equal(host.commands[host.commands.length - 1], 'status --json', 'reopen reads status')
      t.equal(controller.keybind, {
        bound: false,
        key: null
      }, 'status lands in keybind')
      controller.request('keybind-add', {
        key: 'SUPER + ALT + P'
      })
      t.step(50, function () {
        t.check(host.commands.indexOf('add --key SUPER + ALT + P --json') >= 0, 'add runs the helper with the key')
        t.equal(host.commands[host.commands.length - 1], 'status --json', 'add re-reads status')
        t.equal(controller.keybind.bound, true, 'bound after add')
        controller.request('keybind-remove', {})
        t.step(50, function () {
          t.equal(controller.keybind.bound, false, 'unbound after remove')
          controller.request('keybind-add', {
            key: 'TAKEN'
          })
          t.step(50, function () {
            t.equal(controller.keybindError.code, 'KEY_TAKEN', 'helper error reaches the controller')
            t.check(!controller.pending, 'not pending afterwards')
            controller.beginShowcase({
              state: {}
            })
            var n = host.commands.length
            t.check(controller.request('keybind-add', {
              key: 'SUPER + ALT + P'
            }) === false && host.commands.length === n, 'showcase refuses add')
            host.failStatus = true
            controller.showcaseActive = false
            controller.keybindError = null
            controller.refreshKeybind(function () {})
            t.step(30, function () {
              t.equal(controller.keybindError.code, 'WRITE_FAILED', 'failed status read sets a plain error')
              t.equal(controller.keybindError.message + ' ' + controller.keybindError.recovery, "Couldn't read the result. Try again.", 'raw helper text is not shown as the message')
              t.check(controller.keybindError.details.indexOf('Could not run the shortcut helper.') >= 0, 'raw helper text is kept as details')
              page.errors = {
                keybind: controller.keybindError
              }
              t.check(child('quickSwitcherError').text.length > 0, 'failed status shows an error')
              host.openCommands = []
              firstOpen.open('{}')
              t.check(host.openCommands.some(function (c) {
                return c.indexOf('aranea-keybind') >= 0 && c.indexOf('status --json') >= 0
              }), 'first open reads status')
              t.done()
            })
          })
        })
      })
    })
  })
}
