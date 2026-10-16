// Headless backend client; the user manager owns action lifetimes.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea
import "ProjectActionRecords.js" as Records

Item {
  id: client
  // Every I/O boundary, native UUID read and poll is inert during captures.
  property bool captureActive: false
  // Selection is presentation scope; accepted receipt identity survives changes.
  property string projectId: ''
  // Exact selected checkout; never fall back to another worktree.
  property string checkoutId: ''
  // Latest validated definition/run state retains its global revision.
  property var snapshot: ({
      revision: 0,
      definitions: [],
      runs: [],
      requests: []
    })
  // Project whose backend-filtered state `snapshot` holds; cleared when the project changes.
  property string snapshotProjectId: ''
  // Suggestions compare against saved definitions only once the snapshot is this project's own.
  readonly property bool suggestionsReady: projectId !== '' && snapshotProjectId === projectId
  // Selected exact run only; accepted IDs can outlive the selection.
  property var currentRun: null
  // Accepted or explicitly inspected retained ID for reconnection.
  property string runId: ''
  // Native UUID identity retained even when the submission response is lost.
  property string requestId: ''
  // Backend transport reachability, separate from native execution availability.
  property bool available: false
  // Independent user manager, journal, preview probe and opener capability flags.
  property var availability: ({})
  // Structured refusal or transport uncertainty, including recovery text.
  property var error: null
  // Local helper/submission in flight; this never owns a service lifecycle.
  property bool pending: false
  // Only an in-flight launch can leave acceptance uncertain after disconnect.
  property bool submitting: false
  // Blocks new submission until the exact receipt is recovered.
  property bool submissionUncertain: false
  // Immutable submitted project/checkout/action identity for receipt recovery.
  property var submissionTarget: null
  // Bounded plaintext local journal data; consumers must use plain text rendering.
  property string output: ''
  // Backend journal truncation evidence, independent of process success.
  property bool truncated: false
  // Only visible consumers explicitly enable native observation of retained runs.
  property bool observationActive: false
  // Only the visible Overview may schedule background native observations.
  property bool summaryObservationActive: false
  // Physical summary slot remains occupied until even an invalidated callback ends.
  property var summaryRead: null
  // Selection/capture/visibility epochs invalidate publication, never receipts.
  property int summaryGeneration: 0
  // One protected run per pass rotates through exact-checkout observations.
  property int summaryCursor: 0
  // Background failures never overwrite an explicit action's error or receipt.
  property var summaryError: null
  // Read-only detection per exact project|checkout; never saved automatically.
  property var detections: ({})
  // Detection for the current selection, or null before the first read.
  readonly property var detection: detections[projectId + '|' + checkoutId] || null
  // A detection read is in flight for some selection.
  property bool detecting: false
  // The project|checkout key of the detection read in flight; empty when idle.
  property string detectingKey: ''
  // Detection reads supersede only other detection reads.
  property int detectionGeneration: 0
  // Remaining inert drafts of one Add all; each waits for the previous acknowledgement.
  property var addQueue: []
  // Size of the current or last Add all.
  property int addTotal: 0
  // Saves acknowledged so far by the current or last Add all.
  property int addCount: 0
  // {added,total,error,cancelled} once an Add all finishes; error is the first refusal or null.
  property var addResult: null
  // Mutation generation of the save this queue issued; other acknowledgements never advance it.
  property int addToken: 0
  // An Add all has started and not yet published its outcome.
  readonly property bool addActive: addTotal > 0 && addResult === null
  onSummaryObservationActiveChanged: summaryGeneration++
  // Two-second presentation poll, active only for visible protected runs.
  property int pollInterval: 2000
  // Submission identity is independent of all read freshness generations.
  property int generation: 0
  // Definition reads supersede other definition reads only.
  property int snapshotGeneration: 0
  // Run reads reject stale exact-run callbacks and selection changes.
  property int runGeneration: 0
  // Availability reads have independent freshness.
  property int availabilityGeneration: 0
  // Fixed shared backend deployed with the active theme.
  property string backendPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-actions'
  // Fixtures replace only the process boundary, keeping the real client logic.
  property var runner: function (argv, input, done) {
    if (client.captureActive)
      return
    var process = processComponent.createObject(client, {
      command: argv,
      input: input,
      completion: done
    })
    if (client.captureActive) {
      process.destroy()
      return
    }
    process.startRequested = true
    process.running = true
  }
  // Definition/state read or mutation changed presentation data.
  signal changed
  // Selected exact run evidence changed; no agent verification inference.
  signal runChanged(var run)
  // An explicit submission or exact receipt recovery retained a run.
  signal runAccepted(var run)
  // Backend response retained even when ok=false includes run evidence.
  signal requestFinished(var response)

  // Short-lived observer/transport processes complete once and never own native services.
  property Component processComponent: Component {
    Process {
      id: process
      property string input: ''
      property var completion
      property bool startRequested: false
      property bool startedSuccessfully: false
      property bool completed: false
      stdinEnabled: true
      function finish(code, text, diagnostics) {
        if (completed)
          return
        completed = true
        completion(code, text, diagnostics)
        process.destroy()
      }
      onStarted: {
        startedSuccessfully = true
        if (input && !client.captureActive)
          write(input + '\n')
        stdinEnabled = false
      }
      onRunningChanged: if (startRequested && !running && !startedSuccessfully)
        finish(-1, '', 'The project action backend is not available.')
      stdout: StdioCollector {
        id: collected
      }
      stderr: StdioCollector {
        id: diagnostics
      }
      // Quickshell metadata omits the unused exit-status enum.
      // qmllint disable signal-handler-parameters
      onExited: function (exitCode) {
        process.finish(exitCode, collected.text, diagnostics.text)
      }
      // qmllint enable signal-handler-parameters
    }
  }
  // How many automatic receipt checks have run for the current uncertainty, 0 to 3.
  property int autoChecksDone: 0
  // Offsets from the moment the submission became uncertain; overridable in tests.
  property var autoCheckDelays: [2000, 5000, 10000]
  // True while another automatic check is still scheduled.
  readonly property bool autoChecking: autoTimer.running
  // Wait before the next automatic check, from the previous one.
  function autoInterval(): int {
    var i = autoChecksDone
    return Math.max(1, autoCheckDelays[i] - (i > 0 ? autoCheckDelays[i - 1] : 0))
  }
  // Cancel scheduled checks; they only read, never submit.
  function stopAutoCheck(): void {
    autoTimer.stop()
  }
  Timer {
    id: autoTimer
    repeat: false
    onTriggered: {
      if (client.captureActive || !client.submissionUncertain || client.autoChecksDone >= 3 || client.autoChecksDone >= client.autoCheckDelays.length)
        return
      // Reading the snapshot is the receipt recovery path; a run id may not exist yet.
      // A busy client still uses up this check, so the schedule always ends.
      client.autoChecksDone++
      if (!client.pending && !client.submitting)
        client.refresh()
      if (client.autoChecksDone < 3 && client.autoChecksDone < client.autoCheckDelays.length) {
        autoTimer.interval = client.autoInterval()
        autoTimer.start()
      }
    }
  }
  onSubmissionUncertainChanged: {
    autoTimer.stop()
    if (submissionUncertain && !captureActive && autoCheckDelays.length) {
      autoChecksDone = 0
      autoTimer.interval = autoInterval()
      autoTimer.start()
    }
  }
  onCaptureActiveChanged: {
    autoTimer.stop()
    disconnect()
    if (!captureActive)
      schedulePoll()
  }
  onProjectIdChanged: {
    snapshotProjectId = ''
    selectionChanged()
  }
  onCheckoutIdChanged: selectionChanged()
  onObservationActiveChanged: schedulePoll()
  onVisibleChanged: schedulePoll()

  // Stop presentation observation only. Accepted native services are untouched.
  function disconnect(): void {
    summaryGeneration++
    generation++
    snapshotGeneration++
    runGeneration++
    availabilityGeneration++
    detectionGeneration++
    detecting = false
    detectingKey = ''
    if (addActive)
      finishAdd(null, true)
    poll.stop()
    if (submitting && requestId && submissionTarget)
      submissionUncertain = true
    pending = false
    submitting = false
  }
  // Invalidate selected readbacks while keeping accepted receipt identity.
  function selectionChanged(): void {
    autoTimer.stop()
    summaryGeneration++
    summaryCursor = 0
    summaryError = null
    snapshotGeneration++
    runGeneration++
    if (!submitting)
      pending = false
    currentRun = null
    output = ''
    truncated = false
    poll.stop()
    if (addActive)
      generation++
    clearAdd()
  }
  // Require both project and checkout equality for attached presentation evidence.
  function matchesSelection(run: var): bool {
    return !!run && run.projectId === projectId && run.checkoutId === checkoutId
  }
  // Check only immutable receipt identity here; the backend remains full-schema authority.
  function validRecordId(value: var, prefix: string): bool {
    return typeof value === 'string' && value.indexOf(prefix + '-') === 0 && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value.slice(prefix.length + 1))
  }
  // Missing fields must never establish equality with other missing evidence.
  function validRunIdentity(run: var): bool {
    return !!run && validRecordId(run.id, 'r') && validRecordId(run.requestId, 'req') && validRecordId(run.projectId, 'p') && validRecordId(run.checkoutId, 'c') && validRecordId(run.actionId, 'a') && typeof run.definitionRevision === 'number' && isFinite(run.definitionRevision) && run.definitionRevision > 0 && Math.floor(run.definitionRevision) === run.definitionRevision && typeof run.definitionHash === 'string' && /^[0-9a-f]{64}$/.test(run.definitionHash)
  }
  // Transport uncertainty directs exact-receipt recovery without retry.
  function transportError(text: string): var {
    return {
      code: 'SUBMISSION_UNCONFIRMED',
      message: text || 'Backend response not available.',
      recovery: 'Refresh the exact action and checkout to recover its receipt; never automatically resubmit.'
    }
  }
  // Fixed private command argv and JSON stdin; errors can still carry accepted runs.
  function invoke(method: string, payload: var, fresh: var, done: var): void {
    if (captureActive || ['snapshot', 'configure', 'remove', 'start', 'inspect', 'refresh', 'stop', 'restart', 'logs', 'open-preview', 'availability', 'detect'].indexOf(method) < 0)
      return
    var complete = function (code, text, diagnostics) {
      if (client.captureActive || !fresh())
        return
      var response = null
      try {
        response = JSON.parse(text)
      } catch (e) {}
      if (!response || typeof response.ok !== 'boolean' || !Object.prototype.hasOwnProperty.call(response, 'error')) {
        done(null, client.transportError(diagnostics))
        return
      }
      // Backend refusals exit nonzero and still retain honest state/run evidence.
      done(response, null)
    }
    try {
      if (!captureActive)
        runner([backendPath, method], JSON.stringify(payload || {}), complete)
    } catch (e) {
      complete(-1, '', String(e))
    }
  }
  // Retain acceptance independently of selected-run presentation.
  function publishRun(run: var): void {
    if (runId !== run.id) {
      output = ''
      truncated = false
    }
    runId = run.id
    if (matchesSelection(run)) {
      currentRun = run
      runChanged(run)
    }
    schedulePoll()
  }
  // Poll only while the visible selected run still needs native observation.
  function schedulePoll(): void {
    poll.stop()
    if (!captureActive && observationActive && visible && !pending && matchesSelection(currentRun) && Records.protectedRun(currentRun))
      poll.restart()
  }
  // Recover only the exact native request receipt and immutable semantic tuple.
  function recoverReceipt(state: var): void {
    if (!submissionUncertain || !requestId || !submissionTarget)
      return
    var receipt = (Array.isArray(state.requests) ? state.requests : []).filter(function (row) {
      return !!row && row.requestId === client.requestId && validRecordId(row.runId, 'r')
    })[0]
    var run = (Array.isArray(state.runs) ? state.runs : []).filter(function (row) {
      return receipt && validRunIdentity(row) && row.id === receipt.runId && row.projectId === client.submissionTarget.projectId && row.checkoutId === client.submissionTarget.checkoutId && row.actionId === client.submissionTarget.actionId
    })[0]
    if (run) {
      submissionUncertain = false
      publishRun(run)
      runAccepted(run)
    }
  }
  // Fresh definition/list reads never supersede acceptance callbacks.
  function refresh(): bool {
    if (captureActive)
      return false
    var read = ++snapshotGeneration
    var selectedProject = projectId
    invoke('snapshot', selectedProject ? {
      projectId: selectedProject
    } : {}, function () {
      return read === client.snapshotGeneration && selectedProject === client.projectId
    }, function (response, failure) {
      available = !!response
      error = failure || response.error
      if (response && response.state) {
        snapshot = response.state
        snapshotProjectId = selectedProject
        recoverReceipt(snapshot)
        changed()
      }
    })
    return true
  }
  // Read independent native capability flags without launching anything.
  function checkAvailability(): bool {
    if (captureActive)
      return false
    var read = ++availabilityGeneration
    invoke('availability', {}, function () {
      return read === client.availabilityGeneration
    }, function (response, failure) {
      available = !!response
      error = failure || response.error
      if (response && response.availability)
        availability = response.availability
      changed()
    })
    return true
  }
  // Definitions remain inert; stale edit refusals leave the caller's draft intact.
  function configure(definition: var, expectedRevision: var): bool {
    var payload = {
      projectId: projectId,
      definition: definition
    }
    if (expectedRevision !== undefined && expectedRevision !== null)
      payload.expectedRevision = expectedRevision
    return mutation('configure', payload)
  }
  // Remove a definition only through store protection and optional revision guard.
  function remove(actionId: string, expectedRevision: var): bool {
    var payload = {
      projectId: projectId,
      actionId: actionId
    }
    if (expectedRevision !== undefined && expectedRevision !== null)
      payload.expectedRevision = expectedRevision
    return mutation('remove', payload)
  }
  // Read the selected checkout's declared commands; cached until forced or failed.
  function detect(force: bool): bool {
    if (captureActive || !projectId || !checkoutId)
      return false
    var key = projectId + '|' + checkoutId
    var cached = detections[key]
    if (!force && (detecting && detectingKey === key || cached && !cached.error))
      return false
    var read = ++detectionGeneration
    var target = {
      projectId: projectId,
      checkoutId: checkoutId
    }
    detecting = true
    detectingKey = key
    invoke('detect', target, function () {
      return read === client.detectionGeneration
    }, function (response, failure) {
      client.detecting = false
      client.detectingKey = ''
      var next = Object.assign({}, client.detections)
      next[key] = response && response.ok && response.checkoutId === target.checkoutId ? {
        projectId: target.projectId,
        checkoutId: target.checkoutId,
        suggestions: Array.isArray(response.suggestions) ? response.suggestions : [],
        sources: Array.isArray(response.sources) ? response.sources : [],
        error: null
      } : {
        projectId: target.projectId,
        checkoutId: target.checkoutId,
        suggestions: [],
        sources: [],
        error: failure || (response && response.error) || client.transportError('')
      }
      client.detections = next
    })
    return true
  }
  // Save drafts one at a time through configure; never start a run.
  function addSuggestions(definitions: var): bool {
    if (captureActive || pending || submissionUncertain || addActive || !Array.isArray(definitions) || !definitions.length)
      return false
    addResult = null
    addTotal = definitions.length
    addCount = 0
    addQueue = definitions.slice(1)
    // The save's generation is claimed first so a synchronous acknowledgement still advances.
    addToken = generation + 1
    if (!configure(definitions[0], undefined)) {
      finishAdd(addStartError(), false)
      return false
    }
    return true
  }
  // Advance or stop the queue after one acknowledged save.
  function advanceAdd(response: var): void {
    if (!addActive)
      return
    if (!response || !response.ok) {
      finishAdd(response ? response.error : transportError(''), false)
      return
    }
    addCount++
    if (!addQueue.length) {
      finishAdd(null, false)
      return
    }
    var next = addQueue[0]
    addQueue = addQueue.slice(1)
    addToken = generation + 1
    if (!configure(next, undefined))
      finishAdd(addStartError(), false)
  }
  // Local refusal for a queued save that could not begin; never the client's unrelated error.
  function addStartError(): var {
    return {
      code: 'SAVE_NOT_STARTED',
      message: 'The next save could not start.',
      recovery: 'Wait for the current change to finish, then add the remaining commands again.'
    }
  }
  // Publish the Add all outcome; remaining drafts are dropped, never retried.
  function finishAdd(failure: var, cancelled: bool): void {
    addQueue = []
    addResult = {
      added: addCount,
      total: addTotal,
      error: failure || null,
      cancelled: cancelled === true
    }
  }
  // Forget the queue and its outcome; a result never outlives its project.
  function clearAdd(): void {
    addQueue = []
    addTotal = 0
    addCount = 0
    addResult = null
  }
  onRequestFinished: function (response) {
    if (addActive && addToken === generation)
      advanceAdd(response)
  }
  // Submit one inert definition mutation; never call Start implicitly.
  function mutation(method: string, payload: var): bool {
    if (captureActive || pending || submissionUncertain)
      return false
    pending = true
    var token = ++generation
    invoke(method, payload, function () {
      return token === client.generation
    }, function (response, failure) {
      pending = false
      available = !!response
      error = failure || response.error
      if (response && response.state && payload.projectId === projectId) {
        snapshotGeneration++
        snapshot = response.state
        snapshotProjectId = payload.projectId
        changed()
      }
      requestFinished(response)
      schedulePoll()
    })
    return true
  }
  // Generate true native UUID before a single explicit start/restart submission.
  function submit(method: string, payload: var, target: var): bool {
    if (captureActive || pending || submissionUncertain)
      return false
    summaryGeneration++
    poll.stop()
    pending = true
    submitting = true
    error = null
    requestId = ''
    submissionTarget = target
    var token = ++generation
    var complete = function (code, text, diagnostics) {
      if (client.captureActive || token !== client.generation)
        return
      var uuid = text.trim()
      if (code !== 0 || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(uuid)) {
        client.pending = false
        client.submitting = false
        client.error = {
          code: 'DEPENDENCY_MISSING',
          message: diagnostics || 'Native request UUID not available.',
          recovery: 'Restore the native UUID helper before starting.'
        }
        return
      }
      if (client.projectId !== target.projectId || client.checkoutId !== target.checkoutId) {
        client.pending = false
        client.submitting = false
        return
      }
      client.requestId = 'req-' + uuid
      payload.requestId = client.requestId
      client.invoke(method, payload, function () {
        return token === client.generation
      }, function (response, failure) {
        client.pending = false
        client.submitting = false
        client.available = !!response
        client.error = failure || response.error
        var requests = response && response.state && Array.isArray(response.state.requests) ? response.state.requests : []
        var runs = response && response.state && Array.isArray(response.state.runs) ? response.state.runs : []
        var request = requests.filter(function (row) {
          return !!row && row.requestId === client.requestId
        })[0]
        var hasRequest = !!request
        var run = response && response.run
        // Store conflicts can carry acceptance only in state. Resolve the exact receipt,
        // then use the same immutable checks as the top-level run envelope below.
        if (!run) {
          run = runs.filter(function (row) {
            return !!row && (hasRequest ? validRecordId(request.runId, 'r') && row.id === request.runId : (row.requestId === client.requestId || Records.protectedRun(row)) && row.projectId === target.projectId && row.checkoutId === target.checkoutId && row.actionId === target.actionId)
          })[0]
        }
        if (!response) {
          client.submissionUncertain = true
        } else if (run) {
          var matches = validRunIdentity(run) && run.projectId === target.projectId && run.checkoutId === target.checkoutId && run.actionId === target.actionId
          var receipt = requests.some(function (row) {
            return !!row && row.requestId === client.requestId && validRecordId(row.runId, 'r') && row.runId === run.id
          })
          var retained = runs.some(function (row) {
            return validRunIdentity(row) && row.id === run.id && row.projectId === target.projectId && row.checkoutId === target.checkoutId && row.actionId === target.actionId && row.definitionRevision === run.definitionRevision && row.definitionHash === run.definitionHash
          })
          // An authoritative refused restart returns recovery evidence for its original run,
          // not acceptance of the newly generated request. A coalesced acceptance has a receipt.
          var originalRefusal = !!response.run && method === 'restart' && !response.ok && matches && retained && !hasRequest && run.id === payload.runId && response.error && typeof response.error.code === 'string' && typeof response.error.message === 'string' && typeof response.error.recovery === 'string'
          if (!matches || !retained || (!receipt && !originalRefusal)) {
            client.submissionUncertain = true
            client.error = client.transportError('The returned run does not match the submitted identity.')
          } else {
            client.submissionUncertain = false
            client.publishRun(run)
            if (!originalRefusal)
              client.runAccepted(run)
            if (response.state && client.projectId === target.projectId) {
              client.snapshotGeneration++
              client.snapshot = response.state
              client.snapshotProjectId = target.projectId
              client.changed()
            }
          }
        }
        if (response && !run && (response.ok || hasRequest)) {
          client.submissionUncertain = true
          client.error = client.transportError('Acceptance response omitted its retained run identity.')
        }
        client.requestFinished(response)
        client.schedulePoll()
      })
    }
    try {
      if (!captureActive)
        runner(['/usr/bin/cat', '/proc/sys/kernel/random/uuid'], '', complete)
    } catch (e) {
      complete(-1, '', String(e))
    }
    return true
  }
  // Start the displayed definition revision once for the exact selected checkout.
  function start(actionId: string, displayedRevision: int): bool {
    if (captureActive || !projectId || !checkoutId || !actionId || displayedRevision < 1 || Records.activeRun(snapshot, projectId, checkoutId, actionId))
      return false
    var target = {
      projectId: projectId,
      checkoutId: checkoutId,
      actionId: actionId
    }
    return submit('start', {
      projectId: projectId,
      checkoutId: checkoutId,
      actionId: actionId,
      expectedDefinitionRevision: displayedRevision
    }, target)
  }
  // Explicit restart refuses unresolved cleanup or mismatched selection.
  function restart(id: string): bool {
    if (captureActive || !currentRun || currentRun.id !== id || !matchesSelection(currentRun) || currentRun.submissionUnconfirmed || currentRun.processState === 'unconfirmed' || !currentRun.definitionRevision || currentRun.definitionRevision < 1)
      return false
    return submit('restart', {
      runId: id,
      expectedDefinitionRevision: currentRun.definitionRevision
    }, {
      projectId: currentRun.projectId,
      checkoutId: currentRun.checkoutId,
      actionId: currentRun.actionId
    })
  }
  // Retained metadata read differs from an explicit fresh native observation.
  function observeRun(id: string): bool {
    return runCommand('inspect', id)
  }
  // Explicit fresh native observation for an exact retained ID.
  function refreshRun(id: string): bool {
    return runCommand('refresh', id)
  }
  // Explicit exact-run cancellation; the backend proves native ownership.
  function stop(id: string): bool {
    return runCommand('stop', id)
  }
  // Explicit bounded journal read; plaintext and truncation are preserved.
  function logs(id: string): bool {
    return runCommand('logs', id)
  }
  // Open only eligible exact running service; backend freshly rechecks ownership.
  function openPreview(id: string): bool {
    if (!currentRun || currentRun.id !== id || !Records.canOpenPreview(currentRun))
      return false
    return runCommand('open-preview', id)
  }
  // Exact-run callbacks cannot attach another run or an old selection.
  function runCommand(method: string, id: string): bool {
    if (captureActive || pending || !id)
      return false
    summaryGeneration++
    poll.stop()
    pending = true
    var read = ++runGeneration
    var selectedProject = projectId, selectedCheckout = checkoutId
    invoke(method, {
      runId: id
    }, function () {
      return read === client.runGeneration && selectedProject === client.projectId && selectedCheckout === client.checkoutId
    }, function (response, failure) {
      pending = false
      available = !!response
      error = failure || response.error
      if (response && response.run) {
        if (response.run.id !== id || !matchesSelection(response.run)) {
          error = transportError('The returned run does not match the selected identity.')
        } else {
          publishRun(response.run)
          if (response.state) {
            snapshotGeneration++
            snapshot = response.state
            snapshotProjectId = selectedProject
            changed()
          }
          if (method === 'logs') {
            output = typeof response.output === 'string' ? response.output : ''
            truncated = response.truncated === true
          }
        }
      }
      requestFinished(response)
      schedulePoll()
    })
    return true
  }
  // Observe one retained summary without changing the selected run.
  function observeSummary(): bool {
    if (captureActive || !summaryObservationActive || summaryRead || pending || !projectId || !checkoutId)
      return false
    var runs = Records.runs(snapshot, projectId, checkoutId).filter(function (run) {
      return Records.protectedRun(run) && !(client.observationActive && client.visible && client.matchesSelection(client.currentRun) && Records.protectedRun(client.currentRun) && client.currentRun.id === run.id)
    })
    if (!runs.length)
      return false
    var run = runs[summaryCursor % runs.length]
    summaryCursor++
    var read = {
      generation: summaryGeneration,
      snapshotGeneration: snapshotGeneration,
      projectId: projectId,
      checkoutId: checkoutId,
      run: run
    }
    summaryRead = read
    var complete = function (code, text, diagnostics) {
      if (client.summaryRead !== read)
        return
      client.summaryRead = null
      if (client.captureActive || !client.summaryObservationActive || read.generation !== client.summaryGeneration || read.projectId !== client.projectId || read.checkoutId !== client.checkoutId || read.snapshotGeneration !== client.snapshotGeneration)
        return
      var response = null
      try {
        response = JSON.parse(text)
      } catch (e) {}
      if (!response || typeof response.ok !== 'boolean' || !Object.prototype.hasOwnProperty.call(response, 'error')) {
        client.summaryError = {
          message: 'Service observation not available. Manage actions to retry.'
        }
        return
      }
      var observed = response.run
      var valid = client.validRunIdentity(observed) && observed.id === read.run.id && observed.requestId === read.run.requestId && observed.projectId === read.projectId && observed.checkoutId === read.checkoutId && observed.actionId === read.run.actionId && observed.definitionRevision === read.run.definitionRevision && observed.definitionHash === read.run.definitionHash
      var state = response.state
      if (!valid || !state || typeof state.revision !== 'number' || !isFinite(state.revision) || !Array.isArray(state.runs) || !state.runs.some(function (row) {
        return client.validRunIdentity(row) && row.actionId === observed.actionId && row.requestId === observed.requestId && row.id === observed.id && row.projectId === observed.projectId && row.checkoutId === observed.checkoutId && row.definitionRevision === observed.definitionRevision && row.definitionHash === observed.definitionHash
      })) {
        client.summaryError = response.error || {
          message: 'Service observation did not match this checkout. Manage actions to retry.'
        }
        return
      }
      if (state.revision < client.snapshot.revision)
        return
      client.summaryError = response.error
      client.snapshotGeneration++
      client.snapshot = state
      client.snapshotProjectId = read.projectId
      client.changed()
    }
    try {
      runner([backendPath, 'refresh'], JSON.stringify({
        runId: run.id
      }), complete)
    } catch (e) {
      complete(-1, '', String(e))
    }
    return true
  }
  // Visible polling observes protected intent without resubmission.
  function readRun(): void {
    if (captureActive || !observationActive || !visible || pending || !matchesSelection(currentRun) || !Records.protectedRun(currentRun))
      return
    refreshRun(currentRun.id)
  }
  Timer {
    id: poll
    interval: client.pollInterval
    onTriggered: client.readRun()
  }
}
