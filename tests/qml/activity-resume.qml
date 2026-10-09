// Accepted fixed launches and read-only resume observations share real runtime adapters.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: root
  // All compositor windows belong only to this fixture.
  property var windows: []
  // Native epoch changes are supplied by the store, never terminal appearance.
  property string epoch: 'old'
  // Kernel proof can disappear while the same title/class remains visible.
  property bool nativeValid: true
  // Retained resume arguments remain data passed to the fixed launcher.
  property var launchRequest: null
  // No observer is allowed to dispatch a focus or move.
  property int dispatches: 0
  QmlTest {
    id: t
  }
  Activity.ActivityRuntime {
    id: runtime
    processRunner: function (argv, input, done) {
      var name = argv[0].split('/').pop(), response
      if (name === 'aranea-project-discover')
        response = {
          ok: true,
          metadata: {
            path: '/repo',
            commonDir: '/repo/.git'
          }
        }
      else if (name === 'aranea-project-tools')
        response = {
          terminals: [
            {
              id: 'kitty',
              available: true
            }
          ],
          defaults: {}
        }
      else if (name === 'aranea-agent-launch') {
        root.launchRequest = JSON.parse(input)
        response = {
          ok: true,
          identity: {
            pid: 50,
            startTime: '500'
          }
        }
      } else if (name === 'aranea-agent-store')
        response = {
          ok: true,
          state: {
            sessions: [
              {
                provider: 'claude',
                providerSessionId: '12345678-1234-1234-1234-123456789abc',
                producerEpoch: root.epoch,
                connection: {
                  connected: true,
                  receivedAt: Math.floor(Date.now() / 1000)
                },
                nativeMetadata: {
                  observedHooks: ['SessionStart']
                },
                provenance: {
                  pid: 60,
                  startTime: '600',
                  commandHash: 'proof',
                  ancestors: [
                    {
                      pid: 50,
                      startTime: '500'
                    }
                  ]
                }
              }
            ]
          }
        }
      else if (name === 'aranea-agent-identity') {
        t.equal(JSON.parse(input).terminalPid, 50, 'native resume proof descends from observed hosting terminal')
        response = {
          ok: true,
          verified: root.nativeValid
        }
      } else {
        t.check(false, 'unexpected resume process')
        response = {
          ok: false
        }
      }
      done(0, JSON.stringify(response), '')
    }
  }
  Component.onCompleted: {
    runtime.engine.compositor = {
      snapshot: function () {
        return {
          available: true,
          windows: root.windows,
          workspaces: [],
          observedAt: Date.now()
        }
      }
    }
    runtime.engine.processRunner = function (argv, input, done) {
      done(0, '{"ok":true,"verified":true,"startTime":"500","processes":[]}', '')
    }
    runtime.engine.dispatchRunner = function (argv, done) {
      root.dispatches++
      done(0, '', '')
    }
    var task = {
      provider: 'claude',
      providerSessionId: '12345678-1234-1234-1234-123456789abc',
      description: '$(touch nope)',
      association: {
        cwd: '/repo'
      }
    }
    runtime.launch(task, {
      cwd: '/repo',
      commonDir: '/repo/.git',
      terminalId: 'kitty',
      workspaceId: 2,
      projectId: 'p',
      checkoutId: 'c'
    }, function (result) {
      t.check(result.ok, 'fixed launcher acceptance is retained')
      t.equal(launchRequest.providerSessionId, task.providerSessionId, 'only validated session identity forwarded')
      t.equal(launchRequest.description, undefined, 'agent display text never enters launcher specification')
      root.windows = [
        {
          pid: 50,
          address: '0xa',
          appId: result.spec.expectedAppId,
          workspaceId: 2
        }
      ]
      var op = {
        desktopId: runtime.sessionId,
        launchIdentity: result.identity,
        spec: result.spec,
        baseline: result.baseline,
        sessionKey: 'claude:' + task.providerSessionId,
        priorEpoch: 'old',
        acceptedAt: Date.now()
      }
      runtime.observeResume(op, function (observed) {
        t.equal(observed.terminal.status, 'observed', 'terminal independently observed')
        t.equal(observed.native, null, 'old native epoch cannot prove resumed agent')
      })
      root.epoch = 'new'
      root.nativeValid = false
      runtime.observeResume(op, function (observed) {
        t.equal(observed.native, null, 'fresh event without current native process proof remains unconfirmed')
      })
      root.nativeValid = true
      runtime.observeResume(op, function (observed) {
        t.check(observed.native.nativeVerified, 'fresh matching native epoch and hosting ancestry prove resume')
      })
      runtime.validateReobserve(op, function (valid) {
        t.check(valid, 'retained launch can be explicitly reobserved')
      })
      runtime.engine.sessionId = 'new-desktop'
      runtime.validateReobserve(op, function (valid) {
        t.equal(valid, false, 'desktop restart refuses retained launch reobservation')
      })
      t.equal(dispatches, 0, 'resume observation and reobservation never move or focus')
      t.done()
    })
  }
}
