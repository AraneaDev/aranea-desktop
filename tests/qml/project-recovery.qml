// Real owner and runtime recovery, with only store/process/compositor boundaries replaced.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Persisted association survives changes of the runtime session.
  property var registry: ({
      schemaVersion: 1,
      revision: 0,
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-one',
          name: 'One',
          commonDir: '/repo/.git',
          lastCheckoutId: 'c-one',
          workspaceMode: 'dedicated',
          tools: {
            editorId: 'code',
            terminalId: 'kitty'
          },
          checkouts: [
            {
              id: 'c-one',
              path: '/repo',
              branch: 'main',
              primary: true
            }
          ],
          associations: [
            {
              checkoutId: 'c-one',
              mode: 'dedicated',
              workspaceId: 2,
              separate: false
            }
          ]
        }
      ]
    })
  // Windows and occupancy are independent of the owner's evidence.
  property var windows: [
    {
      address: '0x100',
      pid: 100,
      appId: 'code',
      workspaceId: 2
    }
  ]
  // Actual launcher boundary calls, including role identity and original token.
  property var launches: []
  // Exact compositor dispatches expose accidental focus during read-only recovery.
  property var dispatches: []
  // Proof requests expose reuse of the original accepted process identity.
  property var proofs: []
  // Re-observation must not depend on current installed-tool availability.
  property bool toolsUnavailable: false
  // Positive closure must not erase older independently uncertain attempts.
  property var closedPids: []
  // Window PID may be proven only from the exact submitted launch identity.
  property var provable: []
  QmlTest {
    id: t
  }
  Projects.ProjectRuntime {
    id: runtime
    captureActive: true
    sessionId: 'recovery-cold'
    observationTimeout: 100
    compositor: ({
        snapshot: function () {
          return {
            available: true,
            observedAt: Date.now(),
            currentWorkspaceId: 2,
            workspaces: [
              {
                id: 2,
                windows: root.windows.length
              }
            ],
            windows: root.windows
          }
        }
      })
    processRunner: function (argv, input, done) {
      var data = JSON.parse(input)
      if (argv[0].indexOf('identity') >= 0) {
        root.proofs.push(data)
        var verified = root.provable.indexOf(data.pid) >= 0 && data.launch.pid === data.pid && data.launch.startTime === String(data.pid)
        done(0, JSON.stringify({
          ok: true,
          verified: verified,
          startTime: String(data.pid),
          processes: [
            {
              pid: data.launch.pid,
              startTime: data.launch.startTime
            }
          ],
          closed: root.closedPids.indexOf(data.pid) >= 0
        }), '')
      } else {
        root.launches.push(data)
        var pid = 200 + root.launches.length
        done(0, JSON.stringify({
          ok: true,
          status: 'accepted',
          identity: {
            pid: pid,
            startTime: String(pid),
            sessionId: runtime.sessionId,
            token: data.token
          }
        }), '')
      }
    }
    dispatchRunner: function (argv, done) {
      root.dispatches.push(argv)
      done(0, '', '')
    }
  }
  Projects.ProjectsController {
    id: owner
    captureActive: true
    runtime: runtime
    roleTimeout: 150
    storeRunner: function (argv, done, input) {
      if (argv[1] === 'mutate') {
        var request = JSON.parse(input), next = JSON.parse(JSON.stringify(root.registry))
        t.equal(request.expectedRevision, next.revision, 'recovery mutation respects revision')
        next.revision++
        if (request.action === 'associate') {
          var args = request.args
          next.projects[0].associations = [
            {
              checkoutId: args.checkoutId,
              mode: args.mode,
              workspaceId: args.workspaceId,
              separate: args.separate
            }
          ]
        }
        root.registry = next
      }
      done({
        ok: true,
        state: root.registry,
        error: null
      })
    }
    metadataRunner: function (argv, done) {
      done({
        ok: true,
        metadata: {
          path: '/repo',
          commonDir: '/repo/.git'
        },
        error: null
      })
    }
    toolsRunner: function (argv, done) {
      if (root.toolsUnavailable) {
        done({
          ok: false,
          error: {
            code: 'DEPENDENCY_MISSING'
          }
        })
        return
      }
      done({
        defaults: {},
        editors: [
          {
            id: 'code'
          }
        ],
        terminals: [
          {
            id: 'kitty'
          }
        ]
      })
    }
  }
  // Drive accepted production requests through terminal outcomes, never a mock owner.
  function open(options, done) {
    var result = owner.request(Object.assign({
      projectId: 'p-one',
      checkoutId: 'c-one'
    }, options || {}))
    t.check(result.ok, 'owner accepts recovery request ' + JSON.stringify(options))
    if (!result.ok) {
      done({
        steps: []
      })
      return
    }
    t.waitFor(function () {
      return owner.operation(result.operationId).state === 'completed' && !owner.queueActive
    }, 2000, 'recovery reaches bounded terminal result', function () {
      done(owner.operation(result.operationId))
    })
  }
  // An occupied restored association cannot recreate ownership from its occupants.
  function cold() {
    open({}, function (op) {
      t.equal(launches.length, 0, 'cold occupied association holds both unknown roles')
      t.equal(op.outcome, 'partial', 'cold association publishes uncertainty')
      t.equal(owner.snapshot().bindings, [], 'workspace and application class never prove ownership')
      windows = []
      open({}, function () {
        t.equal(launches.length, 0, 'uncertainty survives later empty workspace read')
        windows = [
          {
            address: '0x100',
            pid: 100,
            appId: 'code',
            workspaceId: 2
          }
        ]
        open({
          newWindowRole: 'terminal'
        }, function () {
          t.equal(launches.length, 1, 'explicit cold recovery launches selected role only')
          runtime.sessionId = 'recovery-changed'
          owner.snapshot()
          open({}, function (changed) {
            t.equal(launches.length, 1, 'in-process session change holds surviving roles')
            t.equal(changed.outcome, 'partial', 'session change reports uncertainty')
            open({
              reobserveRole: 'terminal'
            }, function (stale) {
              t.equal(launches.length, 1, 'stale identity re-observation never launches')
              t.check(stale.steps.some(function (step) {
                return step.role === 'terminal' && step.status === 'unconfirmed'
              }), 'stale-session attempt remains unconfirmed')
              fresh()
            })
          })
        })
      })
    })
  }
  // A genuinely empty restored association remains safe for ordinary first Open.
  function fresh() {
    runtime.sessionId = 'recovery-empty'
    windows = []
    owner.snapshot()
    open({}, function (original) {
      t.equal(launches.length, 3, 'empty restored association launches both new roles')
      t.equal(original.outcome, 'partial', 'initial accepted launches time out independently')
      t.check(original.steps.filter(function (step) {
        return step.reobserveAvailable
      }).length === 2, 'unconfirmed roles publish re-observation capability')
      var immutable = JSON.stringify(original)
      var attempts = owner.launchAttempts.slice()
      var editor = attempts.filter(function (attempt) {
        return attempt.role === 'editor'
      })[0]
      if (!editor) {
        t.check(false, 'accepted editor attempt retained')
        t.done()
        return
      }
      var pid = editor.launchIdentity.pid
      windows = [
        {
          address: '0xabc',
          pid: pid,
          appId: 'code',
          workspaceId: 2
        }
      ]
      provable = [pid]
      var savedRevision = registry.revision, savedDispatches = dispatches.length
      toolsUnavailable = true
      open({
        reobserveRole: 'editor'
      }, function (late) {
        toolsUnavailable = false
        t.equal(registry.revision, savedRevision, 're-observation does not allocate or persist workspace associations')
        t.equal(late.outcome, 'observed', 'late provable editor is observed without a new launch')
        t.equal(launches.length, 3, 're-observation does not call launcher or launch sibling')
        t.equal(JSON.stringify(owner.operation(original.id)), immutable, 'original completed operation remains immutable')
        t.check(owner.snapshot().bindings.some(function (binding) {
          return binding.pid === pid && binding.sessionId === runtime.sessionId
        }), 'late proof publishes current-session binding')
        t.check(proofs.some(function (proof) {
          return proof.launch.pid === pid && proof.launch.startTime === String(pid)
        }), 'runtime verifies retained exact PID and start time')
        open({
          reobserveRole: 'terminal'
        }, function (uncertain) {
          t.equal(registry.revision, savedRevision, 'continued re-observation does not write associations')
          t.equal(dispatches.length, savedDispatches, 'controller re-observation never focuses or reallocates workspace')
          t.equal(uncertain.outcome, 'partial', 'continued uncertainty ends bounded re-observation')
          t.equal(launches.length, 3, 'continued uncertainty never automatically retries launch')
          baselineAndCopies()
        })
      })
    })
  }
  // Baseline windows and independently unresolved older copies survive new recovery results.
  function baselineAndCopies() {
    // Next accepted terminal PID is 204; an already-present address must be excluded.
    windows = windows.concat([
      {
        address: '0xddd',
        pid: 204,
        appId: 'unrelated',
        workspaceId: 2
      }
    ])
    open({
      newWindowRole: 'terminal'
    }, function () {
      var attempt = owner.launchAttempts.filter(function (a) {
        return a.launchIdentity && a.launchIdentity.pid === 204
      })[0]
      if (!attempt) {
        t.check(false, 'new accepted terminal retained')
        t.done()
        return
      }
      windows = [
        {
          address: '0xddd',
          pid: 204,
          appId: attempt.launchIdentity.token,
          workspaceId: 2
        }
      ]
      provable = [204]
      open({
        reobserveRole: 'terminal'
      }, function (excluded) {
        t.equal(excluded.outcome, 'partial', 'original pre-launch baseline is retained across re-observation')
        windows = [
          {
            address: '0xeee',
            pid: 204,
            appId: attempt.launchIdentity.token,
            workspaceId: 2
          }
        ]
        open({
          reobserveRole: 'terminal'
        }, function (observed) {
          t.equal(observed.outcome, 'observed', 'new exact terminal window can be proven later')
          t.check(owner.launchAttempts.some(function (a) {
            return a.role === 'terminal' && a.launchIdentity.pid === 203
          }), 'observing newer copy retains independent older uncertainty')
          t.equal(launches.length, 4, 'all checks preserve launch counts')
          windows = []
          closedPids = [204]
          open({}, function () {
            t.equal(launches.length, 4, 'closing re-observed copy does not authorize duplication of older uncertain attempt')
            staleCallback()
          })
        })
      })
    })
  }
  // Old observer completion after a session reset cannot republish binding or alter outcome.
  function staleCallback() {
    windows = []
    var result = owner.request({
      projectId: 'p-one',
      checkoutId: 'c-one',
      reobserveRole: 'terminal'
    })
    t.check(result.ok, 'retained older attempt may be checked explicitly')
    t.waitFor(function () {
      return owner.operation(result.operationId).state === 'observing'
    }, 1000, 're-observation begins', function () {
      runtime.sessionId = 'recovery-final'
      owner.snapshot()
      var terminal = JSON.stringify(owner.operation(result.operationId))
      t.step(250, function () {
        t.equal(JSON.stringify(owner.operation(result.operationId)), terminal, 'stale observation cannot mutate terminal session-change result')
        t.equal(owner.snapshot().bindings, [], 'stale observation cannot restore lost-session ownership')
        t.equal(launches.length, 4, 'session interruption launches nothing')
        owner.captureActive = true
        runtime.captureActive = true
        t.done()
      })
    })
  }
  Component.onCompleted: {
    runtime.captureActive = false
    owner.captureActive = false
    owner.refresh()
    cold()
  }
}
