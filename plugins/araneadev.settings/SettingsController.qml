// Persistent process owner; visibility never controls process lifetime.
import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea
import "SettingsLogic.js" as Logic

QtObject {
  id: controller
  // Backend executable, resolved from the active theme root by default.
  property string adapterPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-settings'
  // Notifications wrapper executable; injectable for isolated IPC fixtures.
  property string notificationsPath: 'omarchy-shell'
  // Injection boundary: runner(argv, callback(exitCode, stdout, stderr)).
  property var runner: function (argv, done) {
    var process = processComponent.createObject(controller, {
      command: argv,
      completion: done
    })
    process.startRequested = true
    process.running = true
  }
  // Latest adapter snapshot; unreadable sections are never replaced with defaults.
  property var state: ({})
  // Whether a settings mutation is in flight.
  property bool pending: false
  // Stable key of the affected control while applying.
  property string pendingKey: ''
  // Actionable error from the latest read or mutation.
  property string error: ''
  // Latest backend read generation; older responses are discarded.
  property int readRevision: 0
  // Latest independent notifications IPC read generation.
  property int notificationsRevision: 0
  // Latest per-control application outcomes.
  property var results: ({})
  // Latest per-control mutation errors, retained through refreshes.
  property var itemErrors: ({})
  // Independently observed notifications IPC state and per-field availability.
  property var notifications: ({
      dnd: null,
      dndAvailability: 'unavailable',
      quiet: null,
      quietAvailability: 'unavailable',
      window: null,
      windowAvailability: 'unavailable'
    })
  // Read errors for individual notifications IPC fields.
  property var notificationErrors: ({})
  // Notify consumers after a current backend snapshot has been accepted.
  signal stateRead
  // Report completion after independent owner readback, for local draft acknowledgment.
  signal mutationCompleted(string operation, var args, bool succeeded)
  // Factory for process instances parented to the keep-loaded controller.
  property Component processComponent: Component {
    Process {
      id: process
      property var completion
      property bool startRequested: false
      property bool startedSuccessfully: false
      property bool completed: false
      function finish(code, stdout, stderr) {
        if (completed)
          return
        completed = true
        completion(code, stdout, stderr)
        process.destroy()
      }
      onStarted: process.startedSuccessfully = true
      // Failed launch has no exited signal; a real exit must wait for collectors.
      onRunningChanged: if (process.startRequested && !running && !process.startedSuccessfully)
        process.finish(-1, '', 'Could not start ' + process.command[0] + '. Check that it is installed and executable.')
      stdout: StdioCollector {
        id: output
      }
      stderr: StdioCollector {
        id: diagnostics
      }
      // Quickshell metadata omits the unused QProcess exit-status enum.
      // qmllint disable signal-handler-parameters
      onExited: function (exitCode) {
        process.finish(exitCode, output.text, diagnostics.text)
      }
      // qmllint enable signal-handler-parameters
    }
  }
  // Return Applying while busy, otherwise the stored application outcome.
  function resultFor(key) {
    return pending && pendingKey === key ? 'Applying…' : results[key] || ''
  }
  // Return the latest error for a stable control key.
  function errorFor(key) {
    return itemErrors[key] || ''
  }
  // Replace outcome and error maps so QML bindings update.
  function setResult(key, value, message) {
    var next = Object.assign({}, results)
    next[key] = value
    results = next
    var errors = Object.assign({}, itemErrors)
    errors[key] = message || ''
    itemErrors = errors
  }
  // Invoke the injected runner and surface dispatch exceptions as failures.
  function runCommand(argv, done) {
    try {
      runner(argv, done)
    } catch (e) {
      done(1, '', String(e))
    }
  }
  // Read backend state, discarding old generations and protecting confirmation reads.
  function refresh(done) {
    if (pending && !done)
      return false
    var revision = ++readRevision
    runCommand([adapterPath, 'status', '--json'], function (code, stdout, stderr) {
      if (!Logic.acceptRead(readRevision, revision))
        return
      var response = Logic.parseResponse(stdout, code)
      state = response.state || ({})
      error = response.error ? response.error.message : ''
      stateRead()
      if (done)
        done(response)
    })
  }
  // Read current owners on reopen without overlapping a running mutation.
  function reopened() {
    // Avoid invalidating a mutation's required confirmation callback.
    if (!pending) {
      refresh()
      refreshNotifications()
    }
  }
  // Read each notification field independently from the service IPC.
  function refreshNotifications() {
    if (pending && pendingKey === 'dnd')
      return false
    var revision = ++notificationsRevision
    readNotification('dndState', 'dnd', revision)
    readNotification('quietState', 'quiet', revision)
    readNotification('quietWindow', 'window', revision)
  }
  // Validate one IPC field and preserve other available notification fields.
  function readNotification(method, key, revision, done) {
    runCommand([notificationsPath, 'notifications', method], function (code, stdout, stderr) {
      if (revision !== notificationsRevision)
        return
      var value = String(stdout || '').trim()
      var valid = code === 0 && (key === 'dnd' ? ['on', 'off'].indexOf(value) >= 0 : key === 'quiet' ? ['on', 'off', 'scheduled'].indexOf(value) >= 0 : value === 'off' || /^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value))
      var next = Object.assign({}, notifications)
      next[key] = valid ? value : null
      next[key + 'Availability'] = valid ? 'available' : 'unavailable'
      notifications = next
      var errors = Object.assign({}, notificationErrors)
      errors[key] = valid ? '' : (stderr || 'Notifications unavailable. Retry to reconnect.')
      notificationErrors = errors
      if (done)
        done(valid, value)
    })
  }
  // Validate and serialize mutations, then confirm against independent owner readback.
  function request(operation, args) {
    args = args || []
    if (pending)
      return false
    if (operation === 'set dnd') {
      if (notifications.dndAvailability !== 'available' || args.length !== 1 || ['on', 'off'].indexOf(args[0]) < 0)
        return false
      pending = true
      pendingKey = 'dnd'
      notificationsRevision++
      setResult('dnd', '', '')
      runCommand([notificationsPath, 'notifications', 'setDnd', args[0]], function (code, stdout, stderr) {
        readNotification('dndState', 'dnd', notificationsRevision, function (valid, value) {
          setResult('dnd', code !== 0 ? 'Failed' : valid && value === args[0] ? 'Applied' : 'Application not confirmed', code !== 0 ? stderr || 'DND change failed.' : valid ? '' : notificationErrors.dnd)
          pending = false
          pendingKey = ''
        })
      })
      return true
    }
    var argv = Logic.command(adapterPath, operation, args, state)
    if (!argv || operation === 'status')
      return false
    var key = operation === 'set integration' ? 'integration:' + args[0] : operation.split(' ')[1]
    pending = true
    pendingKey = key
    readRevision++
    setResult(key, '', '')
    runCommand(argv, function (code, stdout, stderr) {
      var mutation = Logic.parseResponse(stdout, code)
      // STATE_UNAVAILABLE may describe an unrelated section after helper success.
      var succeeded = mutation.ok || !!(mutation.error && mutation.error.code === 'STATE_UNAVAILABLE')
      refresh(function (response) {
        setResult(key, Logic.outcome(operation, args, response.state, succeeded), succeeded ? '' : mutation.error ? mutation.error.message : stderr || 'The settings change failed.')
        pending = false
        pendingKey = ''
        mutationCompleted(operation, args, succeeded)
      })
    })
    return true
  }
}
