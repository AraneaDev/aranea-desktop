// Persistent queue, retained reads and observer lifetime use inert injected boundaries.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: root
  // Held store callbacks expose stale snapshot ordering.
  property var reads: []
  // Deferred actions prove global queue serialization.
  property var pendingActions: []
  // Count accepted provider launches without executing a provider.
  property int launched: 0
  // Count project workspace requests without desktop mutation.
  property int prepared: 0
  // Reobservation must clear stale terminal observation after window disappearance.
  property bool loseTerminal: false
  // Store refusal and success exercise serialized dismissal without process effects.
  property bool allowDismiss: false
  // Injected wall time independent of real heartbeat clocks.
  property double now: 2000
  // Retained task fixture has one exact registered checkout.
  property var task: ({
      taskId: 't',
      provider: 'claude',
      providerSessionId: '12345678-1234-1234-1234-123456789abc',
      producerEpoch: 'old',
      reportedState: 'working',
      association: {
        status: 'registered',
        projectId: 'p',
        checkoutId: 'c',
        cwd: '/repo'
      },
      verification: {
        status: 'unknown'
      }
    })
  // Validated store fixture with private native epoch evidence.
  property var state: ({
      schemaVersion: 1,
      revision: 1,
      tasks: [task],
      sessions: [
        {
          provider: 'claude',
          providerSessionId: task.providerSessionId,
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
  QmlTest {
    id: t
  }
  Activity.ActivityController {
    id: owner
    pollInterval: 60000
    operationTimeout: 80
    clock: function () {
      return root.now
    }
    runtime: ({
        sessionId: 'desktop',
        readStore: function (done) {
          root.reads.push(done)
        },
        focusSession: function (task, session, done) {
          root.pendingActions.push(done)
        },
        prepare: function (task, workspaceOnly, done) {
          root.prepared++
          done({
            ok: true,
            workspaceId: 2,
            projectId: 'p',
            checkoutId: 'c',
            cwd: '/repo'
          })
        },
        launch: function (task, preparation, done) {
          root.launched++
          done({
            ok: true,
            identity: {
              pid: 55,
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
          done({
            terminal: root.loseTerminal ? null : {
              status: 'observed',
              binding: {
                address: '0xa'
              }
            },
            native: null
          })
        },
        dismiss: function (id, done) {
          done(root.allowDismiss ? {
            ok: true,
            state: {
              schemaVersion: 1,
              revision: 2,
              tasks: [],
              sessions: []
            }
          } : {
            ok: false,
            error: {
              code: 'TASK_LIVE',
              message: 'Active task'
            }
          })
        },
        validateReobserve: function (op, done) {
          done(true)
        }
      })
  }
  Component.onCompleted: {
    owner.refresh()
    owner.refresh()
    reads[1]({
      ok: true,
      state: state
    })
    reads[0]({
      ok: true,
      state: {
        schemaVersion: 1,
        revision: 0,
        tasks: [],
        sessions: []
      }
    })
    t.equal(owner.snapshot().revision, 1, 'late snapshot cannot overwrite newer state')
    owner.refresh()
    reads[2]({
      ok: false,
      error: {
        code: 'STORE_BAD',
        message: 'Retained'
      }
    })
    t.equal(owner.snapshot().tasks.length, 1, 'store error retains last valid activity')
    t.equal(owner.snapshot().error.code, 'STORE_BAD', 'store errors visible')
    var a = owner.requestJSON(JSON.stringify({
      action: 'focus',
      taskId: 't'
    }))
    var b = owner.requestJSON(JSON.stringify({
      action: 'focus',
      taskId: 't'
    }))
    t.equal(a.operationId, b.operationId, 'pending action retains accepted ID')
    t.step(20, function () {
      t.equal(pendingActions.length, 1, 'one serialized focus dispatch')
      pendingActions[0]({
        ok: true,
        status: 'observed'
      })
      var r = owner.requestJSON(JSON.stringify({
        action: 'reopen',
        taskId: 't'
      }))
      var duplicate = owner.requestJSON(JSON.stringify({
        action: 'reopen',
        taskId: 't'
      }))
      t.equal(r.operationId, duplicate.operationId, 'concurrent reopen cannot double launch')
      t.step(150, function () {
        t.equal(owner.operation(r.operationId).outcome, 'partial', 'terminal observed does not prove native resumed')
        t.equal(launched, 1, 'one accepted launch')
        t.equal(prepared, 1, 'one workspace preparation')
        root.loseTerminal = true
        owner.reobserve(r.operationId)
        owner.reobserve(r.operationId)
        t.step(150, function () {
          t.equal(owner.operation(r.operationId).steps[0].status, 'unconfirmed', 'reobserve clears stale terminal observation')
          t.equal(launched, 1, 'reobserve never relaunches')
          t.equal(prepared, 1, 'reobserve never prepares or focuses workspace')
          t.equal(owner.operation(r.operationId).id, r.operationId, 'reobserve retains operation ID')
          var rejected = owner.dismiss('t')
          t.step(20, function () {
            t.equal(owner.operation(rejected.operationId).error.code, 'TASK_LIVE', 'store refuses live dismissal')
            t.equal(owner.snapshot().tasks.length, 1, 'refused dismissal retains task')
            root.allowDismiss = true
            var dismissed = owner.dismiss('t')
            t.step(20, function () {
              t.equal(owner.operation(dismissed.operationId).outcome, 'observed', 'stale dismissal observes store removal')
              t.equal(owner.snapshot().tasks.length, 0, 'successful dismissal publishes fresh store snapshot')
              t.equal(launched, 1, 'dismissal never terminates or launches a provider')
              finishCapture()
            })
          })
        })
      })
    })
  }
  // Capture safety is checked after both store-authoritative dismissal outcomes.
  function finishCapture() {
    owner.captureActive = true
    var n = reads.length
    owner.refresh()
    t.equal(reads.length, n, 'capture refuses store I/O')
    t.equal(owner.requestJSON('{"action":"focus","taskId":"t"}').error.code, 'INERT_MODE', 'capture refuses actions')
    t.done()
  }
}
