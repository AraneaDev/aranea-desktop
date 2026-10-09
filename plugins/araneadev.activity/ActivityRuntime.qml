// Compose Phase 1 process/compositor adapters; project IPC alone allocates workspaces.
pragma ComponentBehavior: Bound
import QtQuick
import "../araneadev.projects" as Projects
import "../araneadev.shared" as Aranea

Item {
  id: runtime
  // Captures refuse every process, project IPC and compositor boundary.
  property bool captureActive: false
  // Existing runtime supplies guarded short-lived processes and window proof.
  property alias engine: desktop
  // Compositor lifetime includes owner reload; no proof is restored from disk.
  readonly property string sessionId: desktop.sessionId
  // Fixed installation paths never come from task data.
  property string scriptsPath: Aranea.RuntimePaths.themeRoot + '/scripts'
  // All process calls can be replaced in isolated behavior fixtures.
  property var processRunner: function (argv, input, done) {
    desktop.run(argv, input, done)
  }
  // Public IPC executable is fixed, with a per-call timeout.
  property string ipcPath: 'omarchy-shell'
  Projects.ProjectRuntime {
    id: desktop
    captureActive: runtime.captureActive
  }
  // Decode helper envelopes, retaining explicit errors rather than invented data.
  function json(argv: var, input: string, done: var): void {
    if (captureActive) {
      done({
        ok: false,
        error: {
          code: 'INERT_MODE',
          message: 'Inert activity fixture.'
        }
      })
      return
    }
    try {
      processRunner(argv, input, function (code, output, diagnostics) {
        if (runtime.captureActive)
          return
        var data = null
        try {
          data = JSON.parse(output)
        } catch (e) {}
        done(code === 0 && data ? data : {
          ok: false,
          transportUnconfirmed: !data || code === 124 || code === 137 || data.ok === true,
          error: data && data.error || {
            code: data && data.code || 'DEPENDENCY_MISSING',
            message: data && data.message || diagnostics || 'Activity dependency unavailable.'
          }
        })
      })
    } catch (e) {
      done({
        ok: false,
        transportUnconfirmed: true,
        error: {
          code: 'DEPENDENCY_MISSING',
          message: String(e)
        }
      })
    }
  }
  // Store reads carry boot and monotonic receipt projection from the shared store.
  function readStore(done: var): void {
    json([scriptsPath + '/aranea-agent-store', 'snapshot'], '', done)
  }
  // Confirm successful dismissal using a fresh store read; no provider process is signalled.
  function dismiss(taskId: string, done: var): void {
    json([scriptsPath + '/aranea-agent-store', 'mutate'], JSON.stringify({
      action: 'dismiss',
      args: {
        taskId: taskId
      }
    }), function (response) {
      if (!response.ok) {
        done(response)
        return
      }
      readStore(done)
    })
  }
  // The native validator independently rechecks boot, executable, hash and parent chain.
  function proveNative(session: var, terminalPid: var, done: var): void {
    if (!session || session.provider !== 'claude' || !session.provenance || !(session.nativeMetadata && (session.nativeMetadata.observedHooks || []).indexOf('SessionStart') >= 0)) {
      done(false)
      return
    }
    var input = {
      provenance: session.provenance
    }
    if (terminalPid !== null)
      input.terminalPid = terminalPid
    json([scriptsPath + '/aranea-agent-identity'], JSON.stringify(input), function (result) {
      done(result.ok && result.verified === true)
    })
  }
  // Focus only a uniquely proven hosting terminal; never infer a pane or title match.
  function focusSession(task: var, session: var, done: var): void {
    var refused = function () {
      done({
        ok: false,
        status: 'unconfirmed',
        code: 'OWNERSHIP_UNCONFIRMED',
        message: 'Cannot prove this native session owns a current hosting terminal. Open checkout or explicitly reopen the session.'
      })
    }
    if (captureActive || !session || !session.connection || !session.connection.connected || Date.now() - session.connection.receivedAt * 1000 >= 60000 || Date.now() < session.connection.receivedAt * 1000) {
      refused()
      return
    }
    desktop.refreshSnapshot(function (data) {
      var lifetime = runtime.sessionId, instance = desktop.compositorInstance
      if (!data.available || !instance) {
        refused()
        return
      }
      var ancestors = session.provenance && session.provenance.ancestors || []
      var windows = data.windows.filter(function (w) {
        return /^0x[0-9a-fA-F]+$/.test(w.address) && !/^0x0+$/.test(w.address) && ancestors.some(function (a) {
          return a.pid === w.pid
        })
      })
      if (windows.length !== 1) {
        refused()
        return
      }
      var window = windows[0]
      proveNative(session, window.pid, function (valid) {
        if (!valid || lifetime !== runtime.sessionId) {
          refused()
          return
        }
        desktop.refreshSnapshot(function (fresh) {
          if (runtime.captureActive || lifetime !== runtime.sessionId || instance !== desktop.compositorInstance || !fresh.available || !fresh.windows.some(function (w) {
            return w.pid === window.pid && w.address === window.address
          })) {
            refused()
            return
          }
          // Recheck process proof after the final compositor read, immediately before dispatch.
          proveNative(session, window.pid, function (current) {
            if (!current || runtime.captureActive || lifetime !== runtime.sessionId || instance !== desktop.compositorInstance) {
              refused()
              return
            }
            desktop.dispatchRunner(['hyprctl', 'dispatch', 'hl.dsp.focus({ window = "address:' + window.address + '" })'], function (code, output, diagnostics) {
              if (code !== 0) {
                refused()
                return
              }
              desktop.refreshSnapshot(function (observed) {
                var ok = lifetime === runtime.sessionId && instance === desktop.compositorInstance && observed.available && observed.activeAddress === window.address
                done({
                  ok: ok,
                  status: ok ? 'observed' : 'unconfirmed',
                  code: ok ? null : 'FOCUS_UNCONFIRMED',
                  scope: 'hosting-terminal'
                })
              })
            })
          })
        })
      })
    })
  }
  // Project owner request/operation/snapshot is the sole checkout workspace authority.
  function prepare(task: var, workspaceOnly: bool, done: var): void {
    if (captureActive) {
      done({
        ok: false,
        error: {
          code: 'INERT_MODE',
          message: 'Inert activity fixture.'
        }
      })
      return
    }
    projectObserver.createObject(runtime, {
      task: task,
      workspaceOnly: workspaceOnly,
      completion: done,
      lifetime: sessionId
    })
  }
  // Launch only after a fresh exact checkout and registered terminal preference check.
  function launch(task: var, preparation: var, done: var): void {
    var lifetime = sessionId
    json([scriptsPath + '/aranea-project-discover', '--metadata', preparation.cwd, '--json'], '', function (metadata) {
      if (!metadata.ok || !metadata.metadata || metadata.metadata.path !== preparation.cwd || metadata.metadata.commonDir !== preparation.commonDir || lifetime !== runtime.sessionId) {
        done({
          ok: false,
          code: 'CHECKOUT_INVALID',
          message: 'Registered checkout identity changed.'
        })
        return
      }
      json([scriptsPath + '/aranea-project-tools', '--json'], '', function (tools) {
        var terminal = preparation.terminalId || tools.defaults && tools.defaults.terminalId
        if (!terminal || !(tools.terminals || []).some(function (row) {
          return row.id === terminal && row.available !== false
        })) {
          done({
            ok: false,
            code: 'TOOL_CHOICE_REQUIRED',
            message: 'Choose an installed supported terminal in project details.'
          })
          return
        }
        desktop.refreshSnapshot(function (baseline) {
          if (!baseline.available || lifetime !== runtime.sessionId) {
            done({
              ok: false,
              code: 'COMPOSITOR_UNAVAILABLE',
              message: 'Desktop unavailable.'
            })
            return
          }
          var token = 'dev.aranea.activity.r' + Date.now() + 'x' + Math.random().toString(16).slice(2)
          var spec = {
            provider: task.provider,
            providerSessionId: task.providerSessionId,
            cwd: preparation.cwd,
            terminalId: terminal,
            token: token
          }
          json(['/usr/bin/timeout', '2s', scriptsPath + '/aranea-agent-launch'], JSON.stringify(spec), function (response) {
            var accepted = response.ok === true && response.identity && Number.isInteger(response.identity.pid) && response.identity.pid > 0 && typeof response.identity.startTime === 'string' && /^[0-9]+$/.test(response.identity.startTime)
            if (!accepted || lifetime !== runtime.sessionId) {
              var refusal = response.ok === false && response.error && ['RESUME_UNAVAILABLE', 'INVALID_LAUNCH', 'CHECKOUT_INVALID', 'TOOL_MISSING', 'DEPENDENCY_MISSING'].indexOf(response.error.code) >= 0
              done({
                ok: false,
                submissionUnconfirmed: response.transportUnconfirmed === true || lifetime !== runtime.sessionId || !refusal,
                code: response.error && response.error.code || 'LAUNCH_UNCONFIRMED',
                message: response.error && response.error.message || 'Launch remains unconfirmed.'
              })
              return
            }
            var identity = Object.assign({}, response.identity, {
              sessionId: lifetime,
              token: token
            })
            done({
              ok: true,
              identity: identity,
              baseline: baseline,
              spec: {
                projectId: preparation.projectId,
                checkoutId: preparation.checkoutId,
                role: 'agent-terminal',
                workspaceId: preparation.workspaceId,
                sessionId: lifetime,
                launchIdentity: identity,
                expectedAppId: token,
                evidenceMode: 'process-app-id'
              }
            })
          })
        })
      })
    })
  }
  // Initial explicit launch may place its proven new terminal in the prepared workspace.
  function observeTerminal(op: var, done: var): void {
    desktop.observe(op.spec, op.baseline, done)
  }
  // Explicit reobserve proves the retained launch and never dispatches focus or moves.
  function validateReobserve(op: var, done: var): void {
    if (captureActive || op.desktopId !== sessionId) {
      done(false)
      return
    }
    desktop.prove(op.launchIdentity, op.launchIdentity.pid, op.launchIdentity.startTime, [], function (proof) {
      done(!!proof && proof.ok && proof.verified && op.desktopId === runtime.sessionId)
    })
  }
  // Read-only terminal discovery and native same-session/new-epoch confirmation.
  function observeResume(op: var, done: var): void {
    if (captureActive || op.desktopId !== sessionId) {
      done({
        terminal: null,
        native: null
      })
      return
    }
    desktop.refreshSnapshot(function (data) {
      var candidates = data.available ? data.windows.filter(function (w) {
        return w.appId === op.spec.expectedAppId && /^0x[0-9a-fA-F]+$/.test(w.address) && !/^0x0+$/.test(w.address) && !(op.baseline.windows || []).some(function (old) {
          return old.address === w.address
        })
      }) : []
      if (candidates.length !== 1) {
        done({
          terminal: null,
          native: null
        })
        return
      }
      var window = candidates[0]
      desktop.prove(op.launchIdentity, window.pid, null, [], function (proof) {
        if (!proof || !proof.verified || op.desktopId !== runtime.sessionId) {
          done({
            terminal: null,
            native: null
          })
          return
        }
        var terminal = {
          status: 'observed',
          binding: {
            address: window.address,
            pid: window.pid,
            workspaceId: window.workspaceId,
            sessionId: runtime.sessionId,
            evidence: {
              startTime: proof.startTime
            }
          }
        }
        readStore(function (response) {
          var sessions = response.ok && response.state ? response.state.sessions : []
          var native = sessions.filter(function (s) {
            return s.provider + ':' + s.providerSessionId === op.sessionKey && s.producerEpoch !== op.priorEpoch && s.connection.connected && s.connection.receivedAt >= Math.floor(op.acceptedAt / 1000) && Date.now() - s.connection.receivedAt * 1000 < 60000
          })[0]
          proveNative(native, window.pid, function (valid) {
            done({
              terminal: terminal,
              native: valid ? {
                provider: native.provider,
                providerSessionId: native.providerSessionId,
                producerEpoch: native.producerEpoch,
                nativeVerified: true,
                observedAt: Math.max(op.acceptedAt, native.connection.receivedAt * 1000)
              } : null
            })
          })
        })
      })
    })
  }
  // A project operation observer retries only an explicit preacceptance readiness refusal.
  property Component projectObserver: Component {
    Item {
      id: observer
      property var task
      property bool workspaceOnly
      property var completion
      property string lifetime
      property string operationId: ''
      property string projectSession: ''
      property int remaining: 30000
      property bool busy: false
      property bool finished: false
      function finish(response) {
        if (finished)
          return
        finished = true
        completion(response)
        observer.destroy()
      }
      function start() {
        if (busy || finished)
          return
        if (runtime.captureActive || lifetime !== runtime.sessionId || remaining <= 0) {
          finish({
            ok: false,
            outcome: operationId ? 'partial' : 'failed',
            error: {
              code: 'PROJECT_UNCONFIRMED',
              message: 'Project owner observation unavailable; accepted work is not resubmitted.'
            }
          })
          return
        }
        busy = true
        if (!operationId) {
          runtime.json(['timeout', '2s', runtime.ipcPath, 'aranea.projects', workspaceOnly ? 'prepareWorkspace' : 'request', JSON.stringify({
              projectId: task.association.projectId,
              checkoutId: task.association.checkoutId
            })], '', function (response) {
            busy = false
            if (response.ok && response.operationId) {
              operationId = response.operationId
              start()
            } else if (!(response.error && response.error.code === 'OWNER_NOT_READY'))
              finish({
                ok: false,
                error: response.error
              })
          })
        } else {
          runtime.json(['timeout', '2s', runtime.ipcPath, 'aranea.projects', 'operation', operationId], '', function (op) {
            busy = false
            if (!op.id || op.id !== operationId || op.projectId !== task.association.projectId || op.checkoutId !== task.association.checkoutId || (projectSession && projectSession !== op.sessionId)) {
              finish({
                ok: false,
                outcome: 'partial',
                error: {
                  code: 'OPERATION_LOST',
                  message: 'Project operation no longer belongs to the accepted owner.'
                }
              })
              return
            }
            projectSession = op.sessionId
            if (op.state !== 'completed')
              return
            if (op.outcome !== 'observed' || !workspaceOnly) {
              finish({
                ok: op.outcome === 'observed',
                outcome: op.outcome,
                steps: op.steps,
                error: op.error
              })
              return
            }
            runtime.json(['timeout', '2s', runtime.ipcPath, 'aranea.projects', 'snapshot'], '', function (snapshot) {
              var project = (snapshot.projects || []).filter(function (p) {
                return p.id === task.association.projectId
              })[0]
              var checkout = project && (project.checkouts || []).filter(function (c) {
                return c.id === task.association.checkoutId && c.path === task.association.cwd
              })[0]
              if (!checkout || snapshot.sessionId !== projectSession) {
                finish({
                  ok: false,
                  error: {
                    code: 'CHECKOUT_INVALID',
                    message: 'The exact registered checkout is unavailable.'
                  }
                })
                return
              }
              finish({
                ok: true,
                workspaceId: op.workspaceId,
                projectId: project.id,
                checkoutId: checkout.id,
                cwd: checkout.path,
                commonDir: project.commonDir,
                terminalId: project.tools && project.tools.terminalId,
                steps: op.steps
              })
            })
          })
        }
      }
      Component.onCompleted: Qt.callLater(observer.start)
      Timer {
        interval: 250
        repeat: true
        running: !observer.finished
        onTriggered: {
          observer.remaining -= interval
          observer.start()
        }
      }
    }
  }
}
