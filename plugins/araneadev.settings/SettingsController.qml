// Persistent process owner; visibility never controls process lifetime.
import QtQuick
import Quickshell.Io
import qs.Commons as Commons
import "../araneadev.shared" as Aranea
import "../araneadev.shared/SignalValue.js" as SignalValue
import "SettingsLogic.js" as Logic

QtObject {
  id: controller
  // Plugin-local catalog for picker confirmation diagnostics.
  property Commons.Translations strings: Commons.Translations {
    directory: Qt.resolvedUrl('i18n')
  }
  // Backend executable, resolved from the active theme root by default.
  property string adapterPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-settings'
  // Notifications wrapper executable; injectable for isolated IPC fixtures.
  property string notificationsPath: 'omarchy-shell'
  // Injection boundary: runner(argv, callback(exitCode, stdout, stderr)).
  property var runner: function (argv, done) {
    var process = processComponent.createObject(controller, {
      command: argv,
      completion: done
    }) as CommandProcess
    process.startRequested = true
    process.running = true
  }
  // Quick-switcher key helper; it alone edits the user's bindings file.
  property string keybindPath: Aranea.RuntimePaths.keybindPath
  // Latest key binding status, {bound, key}, or null while unknown.
  property var keybind: null
  // Latest key binding error, {code, message, recovery}, or null.
  property var keybindError: null
  // Whether an inert display fixture replaces observed owner state.
  property bool showcaseActive: false
  // Observed state saved while a display fixture is visible.
  property var showcaseSaved: null
  // Start an inert showcase only when no owned mutation is running.
  function beginShowcase(fixture) {
    if (pending)
      return 'busy'
    if (!fixture || !fixture.state || typeof fixture.state !== 'object' || Array.isArray(fixture.state))
      return 'invalid'
    if (!showcaseActive)
      showcaseSaved = {
        state: state,
        error: error,
        notifications: notifications,
        notificationErrors: notificationErrors,
        results: results,
        itemErrors: itemErrors
      }
    readRevision++
    notificationsRevision++
    showcaseActive = true
    state = fixture.state
    error = fixture.error || ''
    notifications = fixture.notifications || ({})
    notificationErrors = fixture.notificationErrors || ({})
    results = fixture.results || ({})
    itemErrors = fixture.itemErrors || ({})
    return 'ok'
  }
  // Restore observations without issuing reads or changing owner preferences.
  function endShowcase() {
    if (!showcaseActive)
      return
    var saved = showcaseSaved
    state = saved.state
    error = saved.error
    notifications = saved.notifications
    notificationErrors = saved.notificationErrors
    results = saved.results
    itemErrors = saved.itemErrors
    showcaseSaved = null
    showcaseActive = false
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
  // Yield the picker before launching its fullscreen preview.
  signal previewRequested
  // Identify the accepted owned session independently of visibility.
  signal previewAccepted(string sessionId)
  // Factory for process instances parented to the keep-loaded controller.
  component CommandProcess: Process {
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
  // Factory retained for the injectable command process boundary.
  property Component processComponent: Component {
    CommandProcess {}
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
    if (showcaseActive || (pending && !done))
      return false
    var revision = ++readRevision
    runCommand([adapterPath, 'status', '--json'], function (code, stdout, stderr) {
      if (!Logic.acceptRead(readRevision, revision))
        return
      var response = Logic.parseResponse(stdout, code)
      state = response.state || ({})
      error = response.error ? response.error.message : ''
      if (response.state && response.state.fonts)
        Aranea.Typography.refresh()
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
      refreshKeybind()
    }
  }
  // Parse a helper envelope; anything unreadable counts as a failure.
  function parseKeybind(stdout) {
    try {
      let value = JSON.parse(stdout)
      return value && typeof value === 'object' ? value : null
    } catch (e) {
      return null
    }
  }
  // Plain error for output that is not a usable helper envelope.
  function keybindFailure(stderr) {
    return {
      code: 'WRITE_FAILED',
      message: "Couldn't read the result.",
      recovery: 'Try again.',
      details: stderr || 'The shortcut helper gave no answer.'
    }
  }
  // Read whether the quick-switcher key is bound; failures keep the last status.
  function refreshKeybind(done) {
    if (showcaseActive)
      return false
    runCommand([keybindPath, 'status', '--json'], function (code, stdout, stderr) {
      var response = parseKeybind(stdout)
      if (response && response.ok && response.data && typeof response.data.bound === 'boolean') {
        keybind = {
          bound: response.data.bound,
          key: response.data.key || null
        }
        if (!done)
          keybindError = null
      } else {
        keybindError = response && response.error ? response.error : keybindFailure(stderr)
      }
      if (done)
        done()
    })
  }
  // Add or remove the key binding, then read the status back.
  function requestKeybind(operation, args) {
    var argv
    if (operation === 'keybind-add') {
      let key = args && args.key
      if (typeof key !== 'string' || key === '')
        return false
      argv = [keybindPath, 'add', '--key', key, '--json']
    } else {
      argv = [keybindPath, 'remove', '--json']
    }
    pending = true
    pendingKey = 'keybind'
    keybindError = null
    runCommand(argv, function (code, stdout, stderr) {
      var response = parseKeybind(stdout)
      var failure = response && response.ok ? null : response && response.error ? response.error : keybindFailure(stderr)
      refreshKeybind(function () {
        if (failure)
          keybindError = failure
        pending = false
        pendingKey = ''
      })
    })
    return true
  }
  // Read each notification field independently from the service IPC.
  function refreshNotifications() {
    if (showcaseActive || (pending && pendingKey === 'dnd'))
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
    // The pages' request signal delivers args as a sequence; Logic wants an array.
    args = SignalValue.plain(args) || (operation.indexOf('keybind-') === 0 ? ({}) : [])
    if (showcaseActive || pending)
      return false
    if (operation === 'keybind-add' || operation === 'keybind-remove')
      return requestKeybind(operation, args)
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
    var key = operation === 'preview screensaver' ? 'screensaver-preview' : operation === 'set integration' ? 'integration:' + args[0] : operation.split(' ')[1]
    pending = true
    pendingKey = key
    readRevision++
    setResult(key, '', '')
    if (operation === 'preview screensaver')
      previewRequested()
    runCommand(argv, function (code, stdout, stderr) {
      var mutation = Logic.parseResponse(stdout, code)
      // STATE_UNAVAILABLE may describe an unrelated section after helper success.
      var succeeded = operation === 'set display-scale' ? !!(mutation.result && mutation.result.displayScale && mutation.result.displayScale.confirmed && (mutation.ok || mutation.error && mutation.error.code === 'STATE_UNAVAILABLE')) : mutation.ok || !!(mutation.error && mutation.error.code === 'STATE_UNAVAILABLE')
      refresh(function (response) {
        var observed = response.state
        // A failed motion helper can confirm persistence before live application fails.
        // If the later config read is unavailable, retain that confirmation only for
        // feedback; never reuse its earlier live state or populate unavailable controls.
        if (!succeeded && operation === 'set motion' && mutation.state && mutation.state.motion && mutation.state.motion.configured === args[0] && (!observed || !observed.motion || ['on', 'off'].indexOf(observed.motion.configured) < 0))
          observed = {
            motion: {
              configured: args[0],
              applied: null
            }
          }
        var outcome = Logic.outcome(operation, args, observed, succeeded, mutation.result)
        var confirmed = operation === 'configure screensaver' ? outcome === 'Saved' : operation === 'configure screensaver-timing' ? outcome === 'Timing saved' : operation === 'preview screensaver' ? outcome === 'Preview accepted' || outcome === 'Stock preview delegated' : true
        var message = succeeded && !confirmed ? controller.strings.t('screensavers.confirmationFailed') : succeeded ? operation === 'set display-scale' && outcome === 'Application not confirmed' ? 'Focused display or effective scale changed during confirmation. Review the current display and Apply again.' : '' : mutation.error ? mutation.error.message : stderr || 'The settings change failed.'
        setResult(key, outcome, message)
        pending = false
        pendingKey = ''
        if (operation === 'preview screensaver' && succeeded && confirmed)
          previewAccepted(mutation.result.screensaverPreview.sessionId || '')
        mutationCompleted(operation, args, succeeded && confirmed && (operation !== 'set display-scale' || outcome.indexOf('Applied') === 0))
      })
    })
    return true
  }
}
