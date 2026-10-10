// Process and compositor adapter; detached applications outlive this observation owner.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../araneadev.shared" as Aranea

Item {
  id: runtime
  // Session identity is unique across shell loads and compositor reconnects.
  property string sessionId: 'projects-' + Date.now() + '-' + Math.random().toString(16).slice(2)
  // Inert captures refuse reads, helpers and dispatch unconditionally.
  property bool captureActive: false
  // Replaceable compositor; fixtures supply snapshot without using a desktop.
  property var compositor: Hyprland
  // Fixed helper paths follow the existing active-theme boundary.
  property string launcherPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-launch'
  // Read-only process proof helper, never a launcher.
  property string identityPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-identity'
  // Each independent role has a ten-second maximum observation deadline.
  property int observationTimeout: 10000
  // Cached authoritative compositor data carries its actual read time.
  property var live: ({
      available: false,
      observedAt: null,
      workspaces: [],
      windows: [],
      currentWorkspaceId: null
    })
  // Last confirmed compositor instance prevents bindings surviving compositor restart.
  property string compositorInstance: ''
  // Concurrent role observers share one authoritative compositor query.
  property bool snapshotReading: false
  // Waiting callbacks consume the same read timestamp without starting independent reads.
  property var snapshotWaiters: []
  // Capture changes invalidate outstanding readbacks before they can publish stale state.
  property int snapshotGeneration: 0
  onCaptureActiveChanged: {
    snapshotGeneration++
    snapshotReading = false
    snapshotWaiters = []
  }
  // Process boundary receives plain argv, optional stdin and one collector completion.
  property var processRunner: function (argv, input, done) {
    var process = processComponent.createObject(runtime, {
      command: argv,
      input: input || '',
      completion: done
    })
    process.startRequested = true
    process.running = true
  }
  // Dispatch uses the same tracked short-lived command boundary as reads.
  property var dispatchRunner: function (argv, done) {
    runtime.processRunner(argv, '', done)
  }
  // Helper processes complete even when the executable fails to start.
  property Component processComponent: Component {
    Process {
      id: process
      property string input: ''
      property var completion
      property bool startRequested: false
      property bool startedSuccessfully: false
      property bool completed: false
      stdinEnabled: true
      function finish(code, output, diagnostics) {
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
        finish(-1, '', 'Could not start ' + command[0] + '. Check that it is installed and executable.')
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
  // Standard callback envelope separates dispatch acceptance from observation.
  function result(ok: bool, status: string, code: var, message: var, binding: var): var {
    return {
      ok: ok,
      status: status,
      code: code || null,
      message: message || null,
      binding: binding || null
    }
  }
  // Expose timestamped cached data; fixture snapshots are explicitly isolated.
  function snapshot(): var {
    if (captureActive || !compositor)
      return {
        available: false,
        observedAt: null,
        workspaces: [],
        windows: [],
        currentWorkspaceId: null
      }
    return typeof compositor.snapshot === 'function' ? compositor.snapshot() : live
  }
  // Decode helper/IPC JSON without replacing failures with invented values.
  function parse(text: string): var {
    try {
      return JSON.parse(text)
    } catch (e) {
      return null
    }
  }
  // Invoke boundaries safely, including missing executables and thrown fixture callbacks.
  function run(argv: var, input: string, done: var): void {
    if (captureActive) {
      done(1, '', 'Inert project fixture.')
      return
    }
    try {
      processRunner(argv, input, done)
    } catch (e) {
      done(-1, '', String(e))
    }
  }
  // Read compositor JSON directly before decisions and window confirmation.
  function refreshSnapshot(done: var): void {
    if (captureActive || !compositor) {
      done(snapshot())
      return
    }
    if (typeof compositor.snapshot === 'function') {
      done(snapshot())
      return
    }
    snapshotWaiters = snapshotWaiters.concat([done])
    if (snapshotReading)
      return
    snapshotReading = true
    var revision = snapshotGeneration
    var rows = ({})
    var pending = 5
    var failed = false
    var queries = ['clients', 'workspaces', 'activeworkspace', 'activewindow', 'instances']
    queries.forEach(function (kind) {
      run(['hyprctl', '-j', kind], '', function (code, output, diagnostics) {
        if (captureActive || revision !== snapshotGeneration)
          return
        var data = parse(output)
        if (code !== 0 || !data)
          failed = true
        rows[kind] = data
        pending--
        if (pending)
          return
        var signature = Quickshell.env('HYPRLAND_INSTANCE_SIGNATURE') || ''
        var instance = Array.isArray(rows.instances) ? rows.instances.filter(function (row) {
          return row.instance === signature
        })[0] : null
        var key = instance ? String(instance.pid) + ':' + String(instance.time) + ':' + String(instance.instance) : ''
        if (compositorInstance && key !== compositorInstance)
          sessionId = 'projects-' + Date.now() + '-' + Math.random().toString(16).slice(2)
        compositorInstance = key
        if (failed || !key || !Array.isArray(rows.clients) || !Array.isArray(rows.workspaces)) {
          live = {
            available: false,
            observedAt: Date.now(),
            workspaces: [],
            windows: [],
            currentWorkspaceId: null
          }
        } else {
          live = {
            available: true,
            observedAt: Date.now(),
            currentWorkspaceId: rows.activeworkspace.id,
            activeAddress: rows.activewindow.address || null,
            workspaces: rows.workspaces.map(function (row) {
              return {
                id: row.id,
                windows: row.windows
              }
            }),
            windows: rows.clients.map(function (row) {
              return {
                address: row.address,
                pid: row.pid,
                appId: row.class,
                workspaceId: row.workspace ? row.workspace.id : null
              }
            })
          }
        }
        var waiters = snapshotWaiters
        snapshotWaiters = []
        snapshotReading = false
        waiters.forEach(function (callback) {
          callback(snapshot())
        })
      })
    })
  }
  // Focus only validated standard IDs and confirm the compositor's actual focus.
  function focusWorkspace(id: int, done: var): void {
    if (captureActive) {
      done(result(false, 'failed', 'INERT_MODE', 'Inert project fixture.', null))
      return
    }
    if (!Number.isInteger(id) || id < 1) {
      done(result(false, 'failed', 'INVALID_WORKSPACE', 'Choose a standard workspace.', null))
      return
    }
    if (!snapshot().available) {
      done(result(false, 'failed', 'COMPOSITOR_UNAVAILABLE', 'Connect to Hyprland to open project workspaces.', null))
      return
    }
    var session = sessionId
    try {
      dispatchRunner(['hyprctl', 'dispatch', 'hl.dsp.focus({ workspace = "' + id + '" })'], function (code, output, diagnostics) {
        if (session !== sessionId || captureActive) {
          done(result(false, 'failed', 'SESSION_CHANGED', 'The desktop session changed.', null))
          return
        }
        if (code !== 0) {
          done(result(false, 'failed', 'FOCUS_FAILED', diagnostics || 'Workspace focus failed.', null))
          return
        }
        refreshSnapshot(function (data) {
          done(result(data.available && data.currentWorkspaceId === id, data.currentWorkspaceId === id ? 'observed' : 'unconfirmed', data.currentWorkspaceId === id ? null : 'FOCUS_UNCONFIRMED', 'Workspace focus could not be confirmed.', null))
        })
      })
    } catch (e) {
      done(result(false, 'failed', 'FOCUS_FAILED', String(e), null))
    }
  }
  // Reprove ownership immediately before focusing only that exact window address.
  function focusBinding(binding: var, done: var): void {
    if (captureActive) {
      done(result(false, 'failed', 'INERT_MODE', 'Inert project fixture.', null))
      return
    }
    if (!binding || binding.sessionId !== sessionId || !(binding.pid > 0) || !/^0x[0-9a-fA-F]+$/.test(binding.address) || /^0x0+$/.test(binding.address)) {
      done(result(false, 'unconfirmed', 'OWNERSHIP_UNCONFIRMED', 'Window ownership is unavailable. Use Open new window explicitly.', null))
      return
    }
    var session = sessionId
    validateBindings([binding], function (proof) {
      if (captureActive || session !== sessionId) {
        done(result(false, 'failed', 'SESSION_CHANGED', 'The desktop session changed.', null))
        return
      }
      var fresh = proof.bindings[0]
      if (!fresh) {
        done(result(false, 'unconfirmed', 'OWNERSHIP_UNCONFIRMED', 'Window ownership could not be verified.', null))
        return
      }
      try {
        dispatchRunner(['hyprctl', 'dispatch', 'hl.dsp.focus({ window = "address:' + fresh.address + '" })'], function (code, output, diagnostics) {
          if (captureActive || session !== sessionId) {
            done(result(false, 'failed', 'SESSION_CHANGED', 'The desktop session changed.', null))
            return
          }
          if (code !== 0) {
            done(result(false, 'unconfirmed', 'FOCUS_FAILED', diagnostics || 'Window focus failed.', null))
            return
          }
          refreshSnapshot(function (data) {
            var observed = session === sessionId && data.available && data.activeAddress === fresh.address
            done(result(observed, observed ? 'observed' : 'unconfirmed', observed ? null : 'FOCUS_UNCONFIRMED', observed ? null : 'Exact window focus could not be confirmed.', observed ? fresh : null))
          })
        })
      } catch (e) {
        done(result(false, 'unconfirmed', 'FOCUS_FAILED', String(e), null))
      }
    })
  }
  // Submit a fixed adapter to the short-lived launcher; retain only accepted identity.
  function launch(spec: var, done: var): void {
    if (captureActive) {
      done(result(false, 'failed', 'INERT_MODE', 'Inert project fixture.', null))
      return
    }
    if (!spec || spec.sessionId !== sessionId || !Array.isArray(spec.argv) || !spec.cwd) {
      done(result(false, 'failed', 'INVALID_LAUNCH', 'The launch specification is invalid.', null))
      return
    }
    run([launcherPath], JSON.stringify({
      argv: spec.argv,
      cwd: spec.cwd
    }), function (code, output, diagnostics) {
      var response = parse(output)
      if (spec.sessionId !== sessionId || captureActive) {
        done(result(false, 'failed', 'SESSION_CHANGED', 'The desktop session changed.', null))
        return
      }
      if (code !== 0 || !response || !response.ok || !response.identity || !(response.identity.pid > 0) || !/^[0-9]+$/.test(response.identity.startTime)) {
        done(result(false, 'failed', response && response.code || 'LAUNCH_FAILED', response && response.message || diagnostics || 'The application could not start.', null))
        return
      }
      response.identity.sessionId = sessionId
      response.identity.token = spec.expectedAppId || spec.token
      done(Object.assign(result(true, 'accepted', null, null, null), {
        identity: response.identity
      }))
    })
  }
  // A process proof is scoped to an accepted session-bound launch, never title/class alone.
  function prove(launch: var, pid: int, startTime: var, known: var, done: var): void {
    if (!launch || launch.sessionId !== sessionId || !(launch.pid > 0) || !/^[0-9]+$/.test(launch.startTime)) {
      done(null)
      return
    }
    var input = {
      launch: {
        pid: launch.pid,
        startTime: launch.startTime
      },
      pid: pid,
      known: known || []
    }
    if (startTime)
      input.startTime = startTime
    run([identityPath], JSON.stringify(input), function (code, output, diagnostics) {
      done(code === 0 ? parse(output) : null)
    })
  }
  // Observe one role independently, rejecting baseline windows, handoff and reused PIDs.
  function observe(spec: var, baseline: var, done: var): void {
    if (captureActive) {
      done(result(false, 'failed', 'INERT_MODE', 'Inert project fixture.', null))
      return
    }
    var observer = observerComponent.createObject(runtime, {
      spec: spec,
      baselineSnapshot: baseline || {
        windows: []
      },
      completion: done,
      session: sessionId,
      deadline: Date.now() + observationTimeout
    })
  }
  // Reverify retained bindings asynchronously; exact closure evidence remains separate.
  function validateBindings(bindings: var, done: var): void {
    if (captureActive) {
      done({
        bindings: [],
        missing: []
      })
      return
    }
    var session = sessionId
    refreshSnapshot(function (data) {
      var fresh = []
      var missing = []
      var pending = bindings.length
      if (!pending) {
        done({
          bindings: fresh,
          missing: missing
        })
        return
      }
      bindings.forEach(function (binding) {
        var evidence = binding.evidence || ({})
        prove(binding.launchIdentity, binding.pid, evidence.startTime, evidence.processes, function (proof) {
          if (session === sessionId && proof && proof.ok && data.available) {
            var window = snapshot().windows.filter(function (row) {
              return row.address === binding.address && row.pid === binding.pid && (evidence.mode === 'process-only' || row.appId === binding.appId)
            })[0]
            if (proof.verified && window) {
              fresh.push(Object.assign({}, binding, {
                workspaceId: window.workspaceId,
                evidence: Object.assign({}, evidence, {
                  processVerified: true,
                  verifiedAt: Date.now(),
                  processes: proof.processes
                })
              }))
            } else if (proof.closed && !window && !snapshot().windows.some(function (row) {
              return (proof.processes || []).some(function (process) {
                return row.pid === process.pid
              })
            })) {
              missing.push({
                binding: binding,
                identity: {
                  pid: binding.pid,
                  startTime: evidence.startTime,
                  address: binding.address
                }
              })
            }
          }
          pending--
          if (!pending)
            done({
              bindings: fresh,
              missing: missing
            })
        })
      })
    })
  }
  // Each role owns only a timer and short-lived proof/dispatch processes.
  property Component observerComponent: Component {
    Item {
      id: observer
      property var spec
      property var baselineSnapshot
      property var completion
      property string session
      property double deadline
      property bool completed: false
      property bool busy: false
      property string movedAddress: ''
      property var known: []
      function finish(response) {
        if (completed)
          return
        completed = true
        completion(response)
        observer.destroy()
      }
      function poll() {
        if (observer.completed)
          return
        if (runtime.captureActive || observer.session !== runtime.sessionId) {
          observer.finish(runtime.result(false, 'failed', 'SESSION_CHANGED', 'The desktop session changed.', null))
          return
        }
        if (Date.now() >= observer.deadline) {
          observer.finish(runtime.result(false, 'unconfirmed', 'OBSERVATION_TIMEOUT', 'Launch accepted without reliable window evidence. Use Open new window explicitly.', null))
          return
        }
        if (observer.busy)
          return
        observer.busy = true
        runtime.refreshSnapshot(function (data) {
          if (observer.completed)
            return
          if (!data.available) {
            observer.finish(runtime.result(false, 'unconfirmed', 'COMPOSITOR_UNAVAILABLE', 'The compositor is unavailable; launch remains unconfirmed.', null))
            return
          }
          var candidates = data.windows.filter(function (row) {
            return row.pid > 0 && /^0x[0-9a-fA-F]+$/.test(row.address) && !/^0x0+$/.test(row.address) && !observer.baselineSnapshot.windows.some(function (old) {
              return old.address === row.address
            }) && (observer.spec.evidenceMode === 'process-only' || row.appId === observer.spec.expectedAppId)
          })
          if (!candidates.length) {
            observer.busy = false
            return
          }
          var pending = candidates.length
          var owned = []
          candidates.forEach(function (candidate) {
            runtime.prove(observer.spec.launchIdentity, candidate.pid, null, observer.known, function (proof) {
              if (!observer || observer.completed)
                return
              if (proof && proof.ok && proof.verified)
                owned.push({
                  window: candidate,
                  proof: proof
                })
              pending--
              if (pending)
                return
              if (observer.session !== runtime.sessionId || runtime.captureActive) {
                observer.finish(runtime.result(false, 'failed', 'SESSION_CHANGED', 'The desktop session changed.', null))
                return
              }
              if (owned.length !== 1) {
                observer.busy = false
                return
              }
              observer.confirm(owned[0].window, owned[0].proof)
            })
          })
        })
      }
      function confirm(window, proof) {
        observer.known = proof.processes || []
        if (window.workspaceId !== observer.spec.workspaceId) {
          if (observer.movedAddress === window.address) {
            observer.busy = false
            return
          }
          observer.movedAddress = window.address
          runtime.dispatchRunner(['hyprctl', 'dispatch', 'hl.dsp.window.move({ window = "address:' + window.address + '", workspace = "' + observer.spec.workspaceId + '", follow = false })'], function (code, output, diagnostics) {
            if (code !== 0) {
              observer.finish(runtime.result(false, 'unconfirmed', 'WINDOW_TARGET_UNCONFIRMED', diagnostics || 'Could not target the launched window.', null))
              return
            }
            observer.busy = false
            observer.poll()
          })
          return
        }
        var binding = {
          projectId: observer.spec.projectId,
          checkoutId: observer.spec.checkoutId,
          role: observer.spec.role,
          workspaceId: observer.spec.workspaceId,
          address: window.address,
          appId: window.appId || null,
          pid: window.pid,
          sessionId: observer.session,
          launchIdentity: observer.spec.launchIdentity,
          evidence: {
            mode: observer.spec.evidenceMode,
            processVerified: true,
            startTime: proof.startTime,
            verifiedAt: Date.now(),
            processes: observer.known
          }
        }
        observer.finish(runtime.result(true, 'observed', null, null, binding))
      }
      Component.onCompleted: Qt.callLater(observer.poll)
      Timer {
        interval: 50
        repeat: true
        running: !observer.completed
        onTriggered: observer.poll()
      }
    }
  }
}
