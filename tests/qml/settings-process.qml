// Real Process startup and collector boundaries use only missing or scratch executables.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: root
  // Writable fixture directory belonging to this isolated offscreen test.
  readonly property string scratch: Quickshell.env('XDG_RUNTIME_DIR')
  // Completion counts reveal hangs, duplicates and automatic retries.
  property int directFailures: 0
  // Normal process completion count.
  property int directSuccesses: 0
  // Missing-adapter mutation completion count.
  property int mutationCompletions: 0
  // Disappearing-adapter confirmation completion count.
  property int confirmationCompletions: 0
  // Captured outputs verify normal exit waits for the full collectors.
  property string collectedOutput: ''
  // Full diagnostics from a normally exited scratch command.
  property string collectedError: ''
  // Real default-runner argv observed without replacing subprocess results.
  property var observedCommands: []
  // Only in-memory configured data seeds the failed-start mutation case.
  readonly property var seed: ({
      motion: {
        configured: 'on',
        applied: 'on',
        availability: 'available',
        application: 'applied'
      }
    })
  QmlTest {
    id: t
  }
  Settings.SettingsController {
    id: missingRead
    adapterPath: root.scratch + '/missing-adapter'
  }
  Settings.SettingsController {
    id: missingIPC
    notificationsPath: root.scratch + '/missing-ipc'
  }
  Settings.SettingsController {
    id: missingMutation
    adapterPath: root.scratch + '/missing-mutation'
    onMutationCompleted: root.mutationCompletions++
  }
  Settings.SettingsController {
    id: confirmation
    adapterPath: root.scratch + '/disappearing-adapter'
    onMutationCompleted: root.confirmationCompletions++
  }
  // Fixture setup writes and chmods only paths under this test's runtime directory.
  Process {
    id: setup
    command: ['/bin/sh', '-c', 'cat > "$1/disappearing-adapter" <<\'SCRIPT\'\n#!/bin/sh\nprintf "%s\\n" "$*" >> "$(dirname "$0")/adapter-calls"\nrm -- "$0"\nprintf \'%s\\n\' \'{"schemaVersion":1,"ok":true,"state":{"motion":{"configured":"off","applied":"off","availability":"available","application":"applied"}},"error":null}\'\nSCRIPT\n' + 'cat > "$1/collectors" <<\'SCRIPT\'\n#!/bin/sh\nprintf start\ni=0; while [ "$i" -lt 4096 ]; do printf x; i=$((i+1)); done\nprintf end\nprintf fixture-diagnostic >&2\nSCRIPT\nchmod +x "$1/disappearing-adapter" "$1/collectors"', '--', root.scratch]
    onExited: function (code) {
      t.equal(code, 0, 'scratch executables prepared without host commands')
      root.startCases()
    }
  }
  // Observe command dispatch while retaining the actual production Process runner.
  function observeRunner(target, kind) {
    var original = target.runner
    target.runner = function (argv, done) {
      root.observedCommands.push({
        kind: kind,
        argv: argv
      })
      original(argv, done)
    }
  }
  // Exercise the unchanged default runner, not a replacement callback runner.
  function startCases() {
    observeRunner(missingIPC, 'ipc')
    observeRunner(missingMutation, 'mutation')
    observeRunner(confirmation, 'confirmation')
    missingRead.refresh()
    missingIPC.refreshNotifications()
    missingMutation.state = seed
    confirmation.state = seed
    t.check(missingMutation.request('set motion', ['off']), 'failed-start mutation is accepted from readable configuration')
    t.check(confirmation.request('set motion', ['off']), 'scratch mutation accepted before its adapter disappears')
    missingRead.runner([root.scratch + '/missing-direct'], function (code, stdout, stderr) {
      root.directFailures++
      t.check(code !== 0 && !!stderr, 'failed startup delivers failure and actionable diagnostics')
    })
    missingRead.runner([root.scratch + '/collectors'], function (code, stdout, stderr) {
      root.directSuccesses++
      root.collectedOutput = stdout
      root.collectedError = stderr
      t.equal(code, 0, 'normally started process reports its real exit')
    })
    t.waitFor(function () {
      return directFailures === 1 && directSuccesses === 1 && mutationCompletions === 1 && confirmationCompletions === 1 && !!missingRead.error && !!missingIPC.notificationErrors.dnd
    }, 2000, 'failed-start reads and mutations all complete', function () {
      t.equal(missingRead.state, ({}), 'missing adapter yields unavailable state')
      t.equal(missingIPC.notifications.dndAvailability, 'unavailable', 'missing IPC marks DND unavailable')
      t.check(!!missingIPC.notificationErrors.quiet && !!missingIPC.notificationErrors.window, 'missing IPC completes all independent reads')
      t.check(!missingMutation.pending && !confirmation.pending, 'failed mutation and failed confirmation both release lock')
      t.equal(missingMutation.resultFor('motion'), 'Failed', 'failed-start mutation cannot report Applied')
      t.check(confirmation.resultFor('motion') !== 'Applied' && !!confirmation.error, 'failed-start confirmation cannot report Applied')
      t.equal(collectedOutput.length, 4104, 'normal exit retains full stdout collector')
      t.check(collectedOutput.slice(0, 5) === 'start' && collectedOutput.slice(-3) === 'end', 'normal collector retains both ends')
      t.equal(collectedError, 'fixture-diagnostic', 'normal exit retains stderr collector')
      missingIPC.notifications = {
        dnd: 'off',
        dndAvailability: 'available'
      }
      t.check(missingIPC.request('set dnd', ['on']), 'failed-start DND mutation accepted from readable IPC state')
      t.waitFor(function () {
        return !missingIPC.pending && missingIPC.resultFor('dnd') === 'Failed'
      }, 2000, 'failed-start DND write and confirmation release mutation lock', function () {
        t.check(!!missingIPC.errorFor('dnd') && missingIPC.notifications.dndAvailability === 'unavailable', 'failed-start DND write keeps error and independent readback unavailable')
        t.step(350, function () {
          t.equal([directFailures, directSuccesses, mutationCompletions, confirmationCompletions], [1, 1, 1, 1], 'callbacks complete exactly once without automatic mutation retries')
          t.equal(root.observedCommands.filter(function (call) {
            return call.kind === 'ipc'
          }).map(function (call) {
            return call.argv.slice(1)
          }), [['notifications', 'dndState'], ['notifications', 'quietState'], ['notifications', 'quietWindow'], ['notifications', 'setDnd', 'on'], ['notifications', 'dndState']], 'IPC dispatch performs one write and one confirmation without retries')
          t.equal(root.observedCommands.filter(function (call) {
            return call.kind === 'mutation'
          }).map(function (call) {
            return call.argv.slice(1)
          }), [['set', 'motion', 'off', '--json'], ['status', '--json']], 'failed-start helper performs one mutation and one confirmation without retries')
          t.equal(root.observedCommands.filter(function (call) {
            return call.kind === 'confirmation'
          }).map(function (call) {
            return call.argv.slice(1)
          }), [['set', 'motion', 'off', '--json'], ['status', '--json']], 'failed-start confirmation cannot repeat the successful scratch mutation')
          t.check(!missingIPC.pending && missingIPC.resultFor('dnd') === 'Failed', 'DND startup failure does not retry automatically')
          t.done()
        })
      })
    })
  }
  Component.onCompleted: setup.running = true
}
