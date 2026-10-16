// Focused registry/tool operation client; the backend owns persistence and identity.
import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea

QtObject {
  id: client
  // Capture refusal happens before creating any helper process.
  property bool captureActive: false
  // Private store helper supplies roots and durable ignored metadata offline.
  property string storePath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-store'
  // Supported installed tool probe never launches applications.
  property string toolsPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-tools'
  // Read cache; neither presentation nor this client writes registry files.
  property var state: ({
      roots: [],
      ignored: [],
      projects: []
    })
  // Installed supported choices and resolved desktop defaults.
  property var tools: ({
      defaults: {},
      editors: [],
      terminals: []
    })
  // One registry mutation request may be in flight.
  property bool pending: false
  // Capture also refuses unfinished backend reads, preserving readback drafts.
  property bool reading: false
  // Actionable failures never replace unreadable registry data with empty defaults.
  property string error: ''
  // The original {code, message, recovery} behind `error`, or null; problem views use it.
  property var errorObject: null
  // The tools failure when the registry read failed too, or null; both stay visible.
  property var extraErrorObject: null
  // Reject callbacks from superseded reads or capture transactions.
  property int generation: 0
  // Typed successful mutations let the composition root update presentation.
  signal mutationCompleted(string action, var args, var state)
  // A mutation request failed; carries the exact request and its message.
  signal mutationFailed(string action, var args, string message)
  // Canonical root identity comes from backend readback, independent of entered spelling.
  signal rootReady(string rootId)
  // Safe helper argv/stdin transport, injectable for inert offscreen fixtures.
  property var runner: function (argv, input, done) {
    var process = processComponent.createObject(client, {
      command: argv,
      input: input,
      completion: done
    })
    process.startRequested = true
    process.running = true
  }
  onCaptureActiveChanged: generation++
  // Startup exceptions and duplicate completions obey the same one-result contract.
  function runHelper(argv: var, input: string, done: var): void {
    var completed = false
    function complete(code, output, diagnostics) {
      if (completed)
        return
      completed = true
      done(code, output, diagnostics)
    }
    try {
      runner(argv, input, complete)
    } catch (e) {
      complete(-1, '', 'Project backend executable not available. Activate Aranea and retry.')
    }
  }
  // Parse one private store response without silently resetting malformed data.
  function parseStore(output: string, code: int): var {
    try {
      var value = JSON.parse(output)
      if (value && typeof value.ok === 'boolean' && (!value.ok || value.state && Array.isArray(value.state.projects) && Array.isArray(value.state.roots) && Array.isArray(value.state.ignored)))
        return value
    } catch (e) {}
    return {
      ok: false,
      state: null,
      error: {
        code: 'REGISTRY_UNAVAILABLE',
        message: 'Project registry not available. Check registry storage and retry.'
      }
    }
  }
  // Refresh independent registry and tool observations without requiring live IPC.
  function refresh(): bool {
    if (captureActive || pending || reading)
      return false
    generation++
    var revision = generation
    reading = true
    var remaining = 2
    var failures = ['', '']
    var failureObjects = [null, null]
    // Complete the grouped read only after both independent helpers return.
    function finished(index, message, object) {
      failures[index] = message
      failureObjects[index] = object || null
      remaining--
      var combined = failures.filter(function (failure) {
        return !!failure
      }).join(' ')
      // Retain an earlier error until the entire retry succeeds. Independent
      // failures are reported in registry/tool order regardless of callback timing.
      if (combined || !remaining) {
        error = combined
        errorObject = combined ? failureObjects[0] || failureObjects[1] : null
        extraErrorObject = failureObjects[0] && failureObjects[1] ? failureObjects[1] : null
      }
      if (!remaining)
        reading = false
    }
    runHelper([storePath, 'snapshot'], '', function (code, output, diagnostics) {
      if (captureActive || revision !== generation)
        return
      var value = parseStore(output, code)
      if (code === 0 && value.ok) {
        state = value.state
        finished(0, '', null)
      } else {
        var message = value.error ? value.error.message + (value.error.recovery ? ' ' + value.error.recovery : '') : diagnostics
        finished(0, message || 'Project registry not available. Check registry storage and retry.', value.error || {
          code: 'REGISTRY_UNAVAILABLE',
          message: diagnostics || 'Project registry not available. Check registry storage and retry.'
        })
      }
    })
    runHelper([toolsPath, '--json'], '', function (code, output, diagnostics) {
      if (captureActive || revision !== generation)
        return
      var message = ''
      try {
        var value = JSON.parse(output)
        if (code !== 0 || !Array.isArray(value.editors) || !Array.isArray(value.terminals))
          throw new Error('Invalid tool response')
        tools = value
      } catch (e) {
        tools = {
          defaults: {},
          editors: [],
          terminals: []
        }
        message = diagnostics || 'Tool choices not available. Install supported tools and retry.'
      }
      finished(1, message, message ? {
        code: 'TOOL_MISSING',
        message: message
      } : null)
    })
    return true
  }
  // Submit only fixed registry actions with data encoded on stdin, never shell code.
  function request(action: string, args: var): bool {
    if (captureActive || pending || reading || ['root-add', 'root-remove', 'register', 'ignore', 'unignore', 'configure', 'select-checkout', 'relocate', 'remove', 'navigation-set', 'profile-save', 'profile-remove', 'profiles-seed'].indexOf(action) < 0)
      return false
    if (!args || typeof args !== 'object' || Array.isArray(args))
      return false
    var priorRoots = state.roots || []
    pending = true
    generation++
    var revision = generation
    var payload = {
      action: action,
      args: args
    }
    if (typeof state.revision === 'number')
      payload.expectedRevision = state.revision
    runHelper([storePath, 'mutate'], JSON.stringify(payload), function (code, output, diagnostics) {
      if (captureActive || revision !== generation)
        return
      var value = parseStore(output, code)
      if (code !== 0 || !value.ok) {
        error = value.error ? value.error.message + (value.error.recovery ? ' ' + value.error.recovery : '') : diagnostics
        extraErrorObject = null
        errorObject = value.error || {
          code: 'REGISTRY_UNAVAILABLE',
          message: diagnostics || ''
        }
        pending = false
        mutationFailed(action, args, error)
        return
      }
      state = value.state
      error = ''
      errorObject = null
      extraErrorObject = null
      // Complete registry feedback before an explicit folder scan is requested.
      function complete(rootId) {
        pending = false
        mutationCompleted(action, args, state)
        if (rootId)
          rootReady(rootId)
      }
      if (action === 'root-add') {
        var matched = state.roots.filter(function (r) {
          return r.path === args.path || !priorRoots.some(function (prior) {
            return prior.id === r.id
          })
        })[0]
        if (matched) {
          complete(matched.id)
          return
        }
        // An already registered root may be entered through a symlink or dot segments.
        runHelper(['realpath', '--', args.path], '', function (code, output, diagnostics) {
          if (captureActive || revision !== generation)
            return
          var path = output.replace(/\n$/, '')
          var existing = state.roots.filter(function (r) {
            return r.path === path
          })[0]
          if (code !== 0 || !existing)
            error = 'Folder saved. Select Refresh beside its canonical path to scan.'
          complete(existing ? existing.id : '')
        })
        return
      }
      complete('')
    })
    return true
  }
  // Each short-lived helper completes once after collected output or failed spawn.
  property Component processComponent: Component {
    Process {
      id: process
      property string input: ''
      property var completion
      property bool startRequested: false
      property bool startedSuccessfully: false
      property bool completed: false
      stdinEnabled: true
      // Complete collected backend output, then release this process object.
      function finish(code: int, output: string, diagnostics: string): void {
        if (completed)
          return
        completed = true
        completion(code, output, diagnostics)
        process.destroy()
      }
      onStarted: {
        startedSuccessfully = true
        if (input)
          write(input + '\n')
        stdinEnabled = false
      }
      onRunningChanged: if (startRequested && !running && !startedSuccessfully)
        finish(-1, '', 'Project backend executable not available. Activate Aranea and retry.')
      stdout: StdioCollector {
        id: output
      }
      stderr: StdioCollector {
        id: diagnostics
      }
      // Quickshell metadata omits the unused exit-status enum.
      // qmllint disable signal-handler-parameters
      onExited: function (exitCode) {
        process.finish(exitCode, output.text, diagnostics.text)
      }
      // qmllint enable signal-handler-parameters
    }
  }
}
