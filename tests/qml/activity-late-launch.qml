// Observation timeout cannot cancel a submitted launcher or lose its late identity.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: root
  // Detached launcher acceptance is deliberately held past the observation deadline.
  property var launchCallback: null
  // Duplicate submissions must not increment the real runtime boundary counter.
  property int launches: 0
  // Reobservation never prepares a second workspace.
  property int preparations: 0
  // Unrelated actions must progress while a previous launch reply is unresolved.
  property int focuses: 0
  // Count public requests independently from the native launcher invocation.
  property int requests: 0
  // Client observation survives destruction through a retained operation ID.
  property var observer: null
  // Current desktop lifetime guards late submission responses too.
  property string desktopId: 'desktop'
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
            providerSessionId: '12345678-1234-1234-1234-123456789abc',
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
            providerSessionId: '12345678-1234-1234-1234-123456789abc',
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
        sessionId: root.desktopId,
        focusSession: function (task, session, done) {
          root.focuses++
          done({
            ok: true,
            status: 'observed'
          })
        },
        prepare: function (task, only, done) {
          root.preparations++
          done({
            ok: true
          })
        },
        launch: function (task, prep, done) {
          root.launches++
          root.launchCallback = done
        },
        observeTerminal: function (op, done) {
          t.check(false, 'late acceptance never dispatches automatic terminal placement')
          done({
            status: 'observed'
          })
        },
        observeResume: function (op, done) {
          done({
            terminal: null,
            native: null
          })
        },
        validateReobserve: function (op, done) {
          done(true)
        }
      })
  }
  Component {
    id: clientComponent
    Activity.ActivityClient {
      pollInterval: 10
      runner: function (argv, done) {
        var response
        if (argv[2] === 'request') {
          root.requests++
          response = owner.requestJSON(argv[3])
        } else if (argv[2] === 'operation')
          response = owner.operation(argv[3])
        else if (argv[2] === 'reobserve')
          response = owner.reobserve(argv[3])
        else
          response = owner.snapshot()
        done(0, JSON.stringify(response), '')
      }
    }
  }
  // Release a successful launch using only a fixed identity/spec fixture.
  function acceptLaunch() {
    launchCallback({
      ok: true,
      identity: {
        pid: 10,
        startTime: '1'
      },
      spec: {
        marker: 'retained'
      },
      baseline: {
        windows: []
      }
    })
  }
  Component.onCompleted: {
    observer = clientComponent.createObject(root)
    observer.request({
      action: 'reopen',
      taskId: 't'
    })
    var id = observer.operationId
    t.check(!!id, 'first client receives accepted owner operation ID')
    observer.destroy()
    observer = null
    t.waitFor(function () {
      return owner.operation(id).state === 'completed'
    }, 1000, 'observation deadline without launch acceptance', function () {
      t.equal(owner.operation(id).outcome, 'partial', 'unresolved submission has bounded partial observation')
      t.equal(owner.operation(id).submissionPending, true, 'unresolved launch remains retained after deadline')
      observer = clientComponent.createObject(root)
      observer.reconnect(id)
      t.equal(observer.operationId, id, 'new observer reconnects before launcher acceptance')
      t.equal(requests, 1, 'observer close/reconnect never resubmits')
      var focus = owner.request({
        action: 'focus',
        taskId: 't'
      })
      var duplicate = owner.request({
        action: 'reopen',
        taskId: 't'
      })
      t.equal(duplicate.operationId, id, 'same-session reopen dedupes while acceptance unresolved')
      t.step(20, function () {
        t.equal(focuses, 1, 'unrelated queued action progresses while launch acceptance unresolved')
        t.equal(owner.operation(focus.operationId).outcome, 'observed', 'unrelated action reaches authoritative completion')
        t.equal(launches, 1, 'unresolved submission prevents a duplicate launcher')
        acceptLaunch()
        var retained = owner.operation(id)
        t.check(!!retained.launchIdentity, 'late accepted identity retained on original operation')
        t.equal(retained.spec.marker, 'retained', 'late acceptance retains observation specification')
        t.equal(retained.submissionPending, false, 'acceptance resolves submission authority')
        t.equal(retained.outcome, 'partial', 'late acceptance alone does not imply observed native resume')
        observer.reconnect()
        t.check(!!observer.currentOperation.launchIdentity, 'reconnect exposes late accepted identity')
        t.check(observer.reobserve(), 'late acceptance supports explicit read-only reobserve')
        t.waitFor(function () {
          return owner.operation(id).state === 'completed'
        }, 1000, 'reobservation deadline', function () {
          t.equal(launches, 1, 'late acceptance reobserve never launches again')
          t.equal(preparations, 1, 'late acceptance reobserve never prepares again')
          t.equal(requests, 1, 'reobserve never submits public reopen')
          observer.destroy()
          observer = null
          var uncertain = owner.request({
            action: 'reopen',
            taskId: 't'
          })
          t.waitFor(function () {
            return owner.operation(uncertain.operationId).state === 'completed'
          }, 1000, 'second submission observation deadline', function () {
            launchCallback({
              ok: false,
              submissionUnconfirmed: true,
              code: 'LAUNCH_UNCONFIRMED',
              message: 'transport deadline'
            })
            var unresolved = owner.operation(uncertain.operationId)
            t.equal(unresolved.submissionUnconfirmed, true, 'transport timeout remains uncertainty rather than failed launch')
            t.equal(owner.request({
              action: 'reopen',
              taskId: 't'
            }).operationId, uncertain.operationId, 'transport uncertainty retains no-repeat authority')
            t.equal(owner.reobserve(uncertain.operationId).error.code, 'SUBMISSION_PENDING', 'missing acceptance has actionable retained-operation refusal')
            var afterTimeout = owner.request({
              action: 'focus',
              taskId: 't'
            })
            t.step(20, function () {
              t.equal(owner.operation(afterTimeout.operationId).outcome, 'observed', 'unrelated action progresses after transport timeout')
              t.equal(launches, 2, 'uncertain submission is never repeated')
              root.desktopId = 'new-desktop'
              acceptLaunch()
              t.check(!owner.operation(uncertain.operationId).launchIdentity, 'late response from old desktop cannot authorize new lifetime')
              t.equal(owner.request({
                action: 'reopen',
                taskId: 't'
              }).operationId, uncertain.operationId, 'desktop loss does not prove unresolved provider was never launched')
              t.done()
            })
          })
        })
      })
    })
  }
}
