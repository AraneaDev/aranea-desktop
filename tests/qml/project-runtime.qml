// Window ownership, explicit workspace targeting and process failures use isolated boundaries.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Only new exact process/app identities may become owned windows.
  property var windows: []
  // Dispatch recorder catches moving unrelated windows or relying on current focus.
  property var commands: []
  // In-memory process identities model fresh start-time verification.
  property bool verified: true
  // Fresh start-time closure evidence must never be invented from window absence.
  property bool closed: false
  // Each fake PID is verified independently, including simultaneous unrelated new windows.
  property var verifiedPids: [44]
  // Independent observed compositor focus can change during launch.
  property int focused: 4
  // Exact focused address is confirmed independently of successful dispatch.
  property string activeAddress: ''
  // Direct JSON query counts expose overlapping snapshot reads and fabricated freshness.
  property int directReads: 0
  // Compositor instance evidence changes independently of application identity.
  property int instanceTime: 1
  // The queried focused workspace, rather than the requested dispatch, confirms focus.
  property int directFocused: 2
  QmlTest {
    id: t
  }
  Projects.ProjectRuntime {
    id: direct
    compositor: ({})
    processRunner: function (argv, input, done) {
      if (argv[1] === 'dispatch') {
        root.directFocused = 7
        done(0, '', '')
        return
      }
      root.directReads++
      var data = argv[2] === 'clients' ? [] : argv[2] === 'workspaces' ? [
        {
          id: 2,
          windows: 0
        }
      ] : argv[2] === 'activeworkspace' ? {
        id: root.directFocused
      } : [
        {
          pid: 100,
          time: root.instanceTime,
          instance: ''
        }
      ]
      Qt.callLater(function () {
        done(0, JSON.stringify(data), '')
      })
    }
  }
  Projects.ProjectRuntime {
    id: runtime
    sessionId: 'runtime-fixture'
    observationTimeout: 100
    compositor: ({
        snapshot: function () {
          return {
            available: true,
            observedAt: Date.now(),
            windows: root.windows,
            workspaces: [],
            currentWorkspaceId: root.focused,
            activeAddress: root.activeAddress
          }
        }
      })
    processRunner: function (argv, input, done) {
      if (argv[0].indexOf('identity') >= 0)
        done(0, JSON.stringify({
          ok: true,
          verified: root.verified && root.verifiedPids.indexOf(JSON.parse(input).pid) >= 0,
          startTime: '123',
          processes: root.closed ? [] : [
            {
              pid: 44,
              startTime: '123'
            }
          ],
          closed: root.closed
        }), '')
      else
        done(0, JSON.stringify({
          ok: true,
          status: 'accepted',
          identity: {
            pid: 44,
            startTime: '123'
          }
        }), '')
    }
    dispatchRunner: function (argv, done) {
      root.commands.push(argv)
      if (argv[2].indexOf('window =') >= 0 && argv[2].indexOf('window.move') < 0)
        root.activeAddress = '0xdef'
      if (argv[2].indexOf('window.move') >= 0)
        root.windows = root.windows.map(function (window) {
          return Object.assign({}, window, {
            workspaceId: 7
          })
        })
      done(0, '', '')
    }
  }
  Projects.ProjectRuntime {
    id: missing
    compositor: null
    launcherPath: '/missing-project-launcher'
  }
  // A unique launched app ID must still have matching process/start-time evidence.
  function spec(): var {
    return {
      argv: ['kitty', '--class', 'dev.aranea.fixture', '--directory', '/fixture'],
      cwd: '/fixture',
      role: 'terminal',
      projectId: 'p-fixture',
      checkoutId: 'c-main',
      workspaceId: 7,
      generation: 1,
      sessionId: 'runtime-fixture',
      expectedAppId: 'dev.aranea.fixture',
      evidenceMode: 'process-app-id',
      launchIdentity: {
        pid: 44,
        startTime: '123',
        sessionId: 'runtime-fixture',
        token: 'dev.aranea.fixture'
      }
    }
  }
  // Concurrent observers share one authoritative read; restart evidence invalidates sessions.
  function verifyDirect(): void {
    var completions = 0
    direct.refreshSnapshot(function (data) {
      completions++
      t.check(data.available && data.observedAt > 0, 'direct compositor read records actual timestamp')
    })
    direct.refreshSnapshot(function (data) {
      completions++
    })
    t.waitFor(function () {
      return completions === 2
    }, 2000, 'both snapshot observers complete', function () {
      t.equal(directReads, 5, 'concurrent observers share one compositor snapshot')
      var before = direct.sessionId
      instanceTime = 2
      direct.refreshSnapshot(function (data) {
        t.check(direct.sessionId !== before, 'compositor restart invalidates live session')
        direct.focusWorkspace(7, function (focus) {
          t.equal(focus.status, 'observed', 'focus dispatch confirmed by independent workspace readback')
          direct.processRunner = function (argv, input, done) {
            done(1, '', 'compositor disconnected')
          }
          direct.refreshSnapshot(function (unavailable) {
            t.check(!unavailable.available && unavailable.windows.length === 0, 'compositor failures never preserve stale available windows')
            t.done()
          })
        })
      })
    })
  }
  Component.onCompleted: {
    runtime.captureActive = true
    runtime.launch(spec(), function (result) {
      t.equal(result.code, 'INERT_MODE', 'capture refuses launch before process')
    })
    runtime.focusWorkspace(2, function (result) {
      t.equal(result.code, 'INERT_MODE', 'capture refuses dispatch')
    })
    runtime.captureActive = false
    runtime.focusWorkspace(-1, function (result) {
      t.equal(result.code, 'INVALID_WORKSPACE', 'invalid workspace never dispatches')
    })
    t.equal(commands.length, 0, 'capture and invalid workspace cause no dispatch')
    missing.focusWorkspace(1, function (result) {
      t.equal(result.code, 'COMPOSITOR_UNAVAILABLE', 'missing compositor disables focus')
    })
    windows = [
      {
        address: '0xabc',
        pid: 44,
        appId: 'dev.aranea.fixture',
        workspaceId: 4
      }
    ]
    var baseline = runtime.snapshot()
    runtime.observe(spec(), baseline, function (result) {
      t.equal(result.status, 'unconfirmed', 'baseline window cannot prove a new launch')
      verified = false
      windows = [
        {
          address: '0xdef',
          pid: 44,
          appId: 'dev.aranea.fixture',
          workspaceId: 4
        }
      ]
      runtime.observe(spec(), {
        windows: []
      }, function (result2) {
        t.equal(result2.status, 'unconfirmed', 'reused PID and app ID fail process proof')
        verified = true
        runtime.observe(spec(), {
          windows: []
        }, function (result3) {
          t.equal(result3.status, 'observed', 'new identity observed only after exact workspace readback')
          t.equal(result3.binding.workspaceId, 7, 'identified window targets reserved workspace despite user focus switch')
          t.equal(result3.binding.evidence.startTime, '123', 'binding retains verified process start time')
          t.check(result3.binding.evidence.processVerified, 'binding includes fresh process verification')
          t.check(commands.length === 1 && commands[0][2].indexOf('0xdef') >= 0, 'only exact launched address moved')
          runtime.focusBinding(result3.binding, function (focusResult) {
            t.equal(focusResult.status, 'observed', 'resume focuses only exact freshly verified address')
            t.equal(activeAddress, '0xdef', 'focus readback confirms exact owned window')
          })
          windows = [
            {
              address: '0xaaa',
              pid: 44,
              appId: 'code',
              workspaceId: 7
            },
            {
              address: '0xbbb',
              pid: 99,
              appId: 'kitty',
              workspaceId: 7
            }
          ]
          var processSpec = Object.assign({}, spec(), {
            evidenceMode: 'process-only',
            expectedAppId: null
          })
          runtime.observe(processSpec, {
            windows: []
          }, function (processResult) {
            t.equal(processResult.status, 'observed', 'process-only role checks independent new candidate ancestry')
            t.equal(processResult.binding && processResult.binding.address, '0xaaa', 'unrelated simultaneous launch never owns editor')
            windows = []
            runtime.validateBindings([result3.binding], function (uncertain) {
              t.equal(uncertain.missing.length, 0, 'window absence with remaining processes is uncertain')
              closed = true
              verified = false
              runtime.validateBindings([result3.binding], function (closure) {
                t.equal(closure.missing[0].identity, {
                  pid: 44,
                  startTime: '123',
                  address: '0xdef'
                }, 'exact observed closure has no owned descendants')
                runtime.sessionId = 'restarted'
                runtime.validateBindings([result3.binding], function (stale) {
                  t.equal(stale.bindings.length, 0, 'old session binding cannot resume')
                  t.equal(stale.missing.length, 0, 'old session cannot assert confirmed closure')
                  missing.processRunner(['/missing-process'], '', function (code, stdout, stderr) {
                    t.check(code !== 0 && !!stderr, 'real failed spawn delivers actionable completion')
                    verifyDirect()
                  })
                })
              })
            })
          })
        })
      })
    })
  }
}
