// Read-only IPC client cannot become a launch owner or dispatch in inert fixtures.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Safe argument-array IPC requests are the only external boundary.
  property var commands: []
  // Latest result observed by consumers after submission.
  property var result: null
  // Only rejected readiness requests may be retried by this submission client.
  property int readinessRefusals: 0
  // Arbitrary refusals are never retried, even when the owner is reachable.
  property string refusalCode: 'OWNER_NOT_READY'
  QmlTest {
    id: t
  }
  Projects.ProjectClient {
    id: client
    pollInterval: 20
    runner: function (argv, done) {
      root.commands.push(argv)
      if (argv[2] === 'request')
        t.check(!client.preparing || Date.now() < client.submissionDeadline, 'readiness retry remains inside its bounded wait')
      Qt.callLater(function () {
        var method = argv[2]
        if (method === 'request' && root.readinessRefusals > 0) {
          root.readinessRefusals--
          done(0, JSON.stringify({
            ok: false,
            operationId: null,
            error: {
              code: root.refusalCode,
              message: 'Preparing a fresh checkout. Retry the rejected request.'
            }
          }), '')
          return
        }
        done(0, JSON.stringify(method === 'snapshot' ? {
          sessionId: 'client-fixture',
          observedAt: 1,
          availability: {
            compositor: true
          },
          projects: [],
          bindings: [],
          operations: []
        } : method === 'request' ? {
          ok: true,
          operationId: 'op-fixture',
          error: null
        } : {
          id: 'op-fixture',
          state: 'completed',
          outcome: 'partial',
          steps: [
            {
              role: 'terminal',
              status: 'unconfirmed'
            }
          ],
          error: null
        }), '')
      })
    }
    onOperationChanged: function (operation) {
      root.result = operation
    }
  }
  // Held IPC callbacks prove read freshness without cancelling accepted observations.
  property var heldReads: []
  Projects.ProjectClient {
    id: ordered
    pollInterval: 60000
    runner: function (argv, done) {
      root.heldReads.push({
        argv: argv,
        done: done
      })
    }
  }
  // Provide current owner state through the real client's replaceable IPC boundary.
  function ownerSnapshot(session, generation, status) {
    return JSON.stringify({
      sessionId: session,
      availability: {
        compositor: true
      },
      projects: [],
      bindings: [],
      operations: [
        {
          id: 'op-read-' + generation,
          sessionId: session,
          projectId: 'p-order',
          checkoutId: 'c-order',
          generation: generation,
          state: 'completed',
          steps: [
            {
              role: 'terminal',
              status: status
            }
          ]
        }
      ]
    })
  }
  Component.onCompleted: {
    ordered.refresh()
    ordered.refresh()
    heldReads[1].done(0, ownerSnapshot('session-one', 2, 'observed'), '')
    heldReads[0].done(0, ownerSnapshot('session-one', 1, 'unconfirmed'), '')
    t.equal(ordered.snapshot.operations[0].generation, 2, 'inverted snapshot callbacks cannot roll back operation generation')
    ordered.refresh()
    ordered.refresh()
    heldReads[3].done(0, ownerSnapshot('session-two', 1, 'observed'), '')
    heldReads[2].done(0, ownerSnapshot('session-one', 3, 'unconfirmed'), '')
    t.equal(ordered.snapshot.sessionId, 'session-two', 'older response cannot resurrect previous owner session')
    ordered.request({
      projectId: 'p-order',
      checkoutId: 'c-order'
    })
    ordered.refresh()
    ordered.refresh()
    heldReads[6].done(0, ownerSnapshot('session-two', 2, 'observed'), '')
    heldReads[4].done(0, JSON.stringify({
      ok: true,
      operationId: 'op-accepted',
      error: null
    }), '')
    heldReads[5].done(1, '', 'superseded snapshot transport failed')
    t.check(ordered.available && ordered.pending && !ordered.error, 'stale snapshot error cannot stop accepted operation observation')
    t.equal(ordered.operationId, 'op-accepted', 'overlapping refresh preserves accepted operation identity')
    heldReads[7].done(0, JSON.stringify({
      id: 'op-accepted',
      state: 'completed',
      outcome: 'observed',
      steps: [],
      error: null
    }), '')
    t.check(!ordered.pending, 'accepted callback completes despite overlapping snapshot reads')
    t.equal(heldReads.filter(function (read) {
      return read.argv[2] === 'request'
    }).length, 1, 'snapshot refresh never resubmits accepted operation')
    ordered.captureActive = true
    client.captureActive = true
    client.refresh()
    client.request({
      projectId: 'p-fixture'
    })
    client.observeOperation('op-fixture')
    t.equal(commands.length, 0, 'capture client cannot read or submit IPC')
    client.captureActive = false
    client.refresh()
    t.waitFor(function () {
      return client.available
    }, 2000, 'client reads owner snapshot', function () {
      t.check(client.request({
        projectId: 'p-fixture',
        checkoutId: 'c-main'
      }), 'client submits request')
      t.waitFor(function () {
        return result !== null
      }, 2000, 'client observes completed operation', function () {
        t.equal(result.outcome, 'partial', 'client preserves observed partial outcome')
        t.check(!client.pending && client.available, 'owner completion clears client pending')
        t.equal(commands.slice(0, 3).map(function (argv) {
          return argv.slice(1)
        }), [['aranea.projects', 'snapshot'], ['aranea.projects', 'request', '{"projectId":"p-fixture","checkoutId":"c-main"}'], ['aranea.projects', 'operation', 'op-fixture']], 'client only invokes shared IPC contract')
        commands = []
        result = null
        readinessRefusals = 2
        client.request({
          projectId: 'p-fixture'
        })
        t.waitFor(function () {
          return result !== null
        }, 2000, 'readiness refusals prepare then accept one operation', function () {
          t.equal(commands.filter(function (argv) {
            return argv[2] === 'request'
          }).length, 3, 'client retries only rejected readiness requests')
          t.equal(commands.filter(function (argv) {
            return argv[2] === 'operation'
          }).length, 1, 'accepted operation is observed without resubmission')
          t.check(client.available && !client.pending && !client.error, 'ready owner remains available after bounded preparation')
          commands = []
          client.readyTimeout = 90
          readinessRefusals = 999
          client.request({
            projectId: 'p-fixture'
          })
          t.waitFor(function () {
            return !client.pending
          }, 1000, 'unready owner stops after bounded preparation', function () {
            t.check(client.available && !client.preparing && !client.operationId, 'reachable unready owner has no accepted operation')
            t.equal(client.requestError.code, 'OWNER_NOT_READY', 'readiness timeout keeps structured refusal for caller')
            t.check(!!client.error, 'readiness timeout keeps actionable recovery text')
            commands = []
            refusalCode = 'INVALID_REQUEST'
            readinessRefusals = 1
            client.request({
              projectId: 'p-fixture'
            })
            t.waitFor(function () {
              return !client.pending
            }, 1000, 'non-readiness refusal completes once', function () {
              t.equal(commands.length, 1, 'client never retries another refusal code')
              t.equal(client.requestError.code, 'INVALID_REQUEST', 'non-readiness refusal remains structured')
              client.runner = function (argv, done) {
                done(1, '', 'owner unavailable')
              }
              client.refresh()
              t.check(!client.available && !!client.error, 'unavailable IPC surfaces actionable error')
              t.done()
            })
          })
        })
      })
    })
  }
}
