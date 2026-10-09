// A timed-out resume observer cannot publish evidence into a later explicit attempt.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: root
  // Held old proof completion survives its first deadline deliberately.
  property var oldProof: null
  // Count observation rounds without dispatching a provider.
  property int observations: 0
  // Stable native UUID is shared across distinct process epochs.
  property string nativeId: '12345678-1234-1234-1234-123456789abc'
  QmlTest {
    id: t
  }
  Activity.ActivityController {
    id: owner
    pollInterval: 60000
    operationTimeout: 120
    ready: true
    storeState: ({
        schemaVersion: 1,
        revision: 1,
        tasks: [
          {
            taskId: 't',
            provider: 'claude',
            providerSessionId: root.nativeId,
            producerEpoch: 'old',
            association: {
              status: 'registered',
              projectId: 'p',
              checkoutId: 'c'
            }
          }
        ],
        sessions: [
          {
            provider: 'claude',
            providerSessionId: root.nativeId,
            producerEpoch: 'old',
            provenance: {
              commandHash: 'proof'
            },
            nativeMetadata: {
              observedHooks: ['SessionStart']
            }
          }
        ]
      })
    runtime: ({
        sessionId: 'desktop',
        prepare: function (task, workspaceOnly, done) {
          done({
            ok: true
          })
        },
        launch: function (task, prep, done) {
          done({
            ok: true,
            identity: {
              pid: 10,
              startTime: '1'
            },
            spec: {},
            baseline: {
              windows: []
            }
          })
        },
        observeTerminal: function (op, done) {
          done({
            status: 'observed',
            binding: {
              address: '0xa'
            }
          })
        },
        observeResume: function (op, done) {
          root.observations++
          if (root.observations === 1)
            root.oldProof = done
          else
            done({
              terminal: {
                status: 'observed'
              },
              native: null
            })
        },
        validateReobserve: function (op, done) {
          done(true)
        }
      })
  }
  Component.onCompleted: {
    var accepted = owner.request({
      action: 'reopen',
      taskId: 't'
    })
    t.waitFor(function () {
      return owner.operation(accepted.operationId).state === 'completed'
    }, 1000, 'first observer deadline', function () {
      t.equal(owner.operation(accepted.operationId).outcome, 'partial', 'held native proof times out partial')
      owner.reobserve(accepted.operationId)
      t.step(20, function () {
        oldProof({
          terminal: {
            status: 'observed'
          },
          native: {
            provider: 'claude',
            providerSessionId: nativeId,
            producerEpoch: 'new',
            nativeVerified: true,
            observedAt: Date.now()
          }
        })
        t.equal(owner.operation(accepted.operationId).state, 'observing', 'old callback cannot complete the new observation attempt')
        t.done()
      })
    })
  }
}
