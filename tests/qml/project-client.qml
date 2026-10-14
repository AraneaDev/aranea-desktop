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
  // Environment transport failures retain an immutable activation for explicit lookup only.
  property var environmentCalls: []
  // Only validated start receipts allow the presentation to dismiss.
  property int acceptedSignals: 0
  // Return dismisses only after exact observed focus.
  property int returnSignals: 0
  Projects.ProjectClient {
    id: environmentClient
    pollInterval: 20
    runner: function (argv, done) {
      root.environmentCalls.push({
        method: argv[2],
        args: argv.slice(3),
        done: done
      })
    }
  }
  Connections {
    target: environmentClient
    ignoreUnknownSignals: true
    function onSubmissionAccepted() {
      root.acceptedSignals++
    }
    function onReturnObserved() {
      root.returnSignals++
    }
  }
  // Lost and malformed acknowledgements may never authorize automatic replay.
  function environmentTests() {
    t.check(typeof environmentClient.startEnvironment === 'function', 'client exposes prepared profile launch')
    if (typeof environmentClient.startEnvironment !== 'function') {
      t.done()
      return
    }
    var payload = {
      projectId: 'p-one',
      checkoutId: 'c-one',
      profileId: 'f-one',
      profileRevision: 1,
      activationId: 'a-00000000-0000-4000-8000-000000000001'
    }
    environmentClient.startEnvironment(payload)
    t.equal(environmentClient.activationId, payload.activationId, 'client retains supplied activation identity')
    environmentCalls[0].done(0, JSON.stringify({
      ok: false,
      operationId: null,
      error: {
        code: 'OWNER_NOT_READY',
        message: 'preparing'
      }
    }), '')
    t.waitFor(function () {
      return environmentCalls.length === 2
    }, 1000, 'only explicit readiness refusal retries start', function () {
      t.equal(environmentCalls[1].args, environmentCalls[0].args, 'readiness retry preserves exact activation and target')
      environmentCalls[1].done(1, '', 'acknowledgement lost')
      t.check(environmentClient.acceptanceUnknown && !environmentClient.pending, 'lost start acceptance remains explicit uncertainty')
      t.equal(environmentClient.activationId, payload.activationId, 'unknown acceptance keeps recovery identity')
      t.equal(acceptedSignals, 0, 'unknown acceptance never signals dismissal')
      environmentClient.checkEnvironmentActivation()
      t.equal(environmentCalls[2].method, 'environmentActivation', 'recovery queries instead of replaying start')
      environmentCalls[2].done(0, JSON.stringify({
        ok: true,
        sessionId: 'owner-one',
        activationId: payload.activationId,
        found: false
      }), '')
      t.check(environmentClient.acceptanceUnknown, 'not-found cannot prove an earlier start was refused')
      t.equal(environmentCalls.filter(function (row) {
        return row.method === 'startEnvironment'
      }).length, 2, 'not-found never replays unknown start')
      environmentClient.checkEnvironmentActivation()
      var op = {
        id: 'op-start',
        projectId: 'p-one',
        checkoutId: 'c-one',
        environmentId: 'e-00000000-0000-4000-8000-000000000001',
        activationId: payload.activationId,
        startTarget: payload,
        sessionId: 'owner-one',
        state: 'completed',
        outcome: 'partial',
        steps: []
      }
      environmentCalls[3].done(0, JSON.stringify({
        ok: true,
        found: true,
        sessionId: 'owner-one',
        activationId: payload.activationId,
        environmentId: op.environmentId,
        operationId: op.id,
        operation: Object.assign({}, op, {
          projectId: 'p-wrong'
        })
      }), '')
      t.equal(acceptedSignals, 0, 'mismatched retained operation identity cannot validate acceptance')
      if (acceptedSignals !== 0) {
        t.done()
        return
      }
      environmentClient.checkEnvironmentActivation()
      environmentCalls[environmentCalls.length - 1].done(0, JSON.stringify({
        ok: true,
        found: true,
        sessionId: 'owner-one',
        activationId: payload.activationId,
        environmentId: op.environmentId,
        operationId: op.id,
        operation: op
      }), '')
      t.equal(acceptedSignals, 1, 'validated retained acceptance emits exactly one launch acknowledgement')
      t.equal(environmentClient.operationId, op.id, 'lookup reconnects exact accepted identity')
      t.check(!environmentClient.pending, 'completed retained receipt finishes even after ordinary operation eviction')
      t.equal(environmentCalls.filter(function (row) {
        return row.method === 'operation'
      }).length, 0, 'completed receipt does not require an evicted operation query')
      environmentClient.returnEnvironment({
        projectId: 'p-one',
        environmentId: op.environmentId
      })
      var returnCall = environmentCalls[environmentCalls.length - 1]
      returnCall.done(0, JSON.stringify({
        ok: true,
        operationId: 'op-return',
        environmentId: op.environmentId
      }), '')
      var observed = environmentCalls[environmentCalls.length - 1]
      observed.done(0, JSON.stringify({
        id: 'op-return',
        projectId: 'p-one',
        environmentId: op.environmentId,
        environmentReturn: true,
        sessionId: 'owner-one',
        workspaceId: 2,
        state: 'completed',
        outcome: 'partial',
        steps: [
          {
            role: 'workspace',
            status: 'unconfirmed',
            workspaceId: 2
          }
        ]
      }), '')
      t.equal(returnSignals, 0, 'unconfirmed Return never dismisses')
      t.equal(acceptedSignals, 1, 'Return acceptance is not launch acceptance')
      environmentClient.returnEnvironment({
        projectId: 'p-one',
        environmentId: op.environmentId
      })
      environmentCalls[environmentCalls.length - 1].done(0, JSON.stringify({
        ok: true,
        operationId: 'op-return-two',
        environmentId: op.environmentId
      }), '')
      environmentCalls[environmentCalls.length - 1].done(0, JSON.stringify({
        id: 'op-return-two',
        projectId: 'p-one',
        environmentId: op.environmentId,
        environmentReturn: true,
        sessionId: 'owner-one',
        workspaceId: 2,
        state: 'completed',
        outcome: 'observed',
        steps: [
          {
            role: 'workspace',
            status: 'observed',
            workspaceId: 2
          }
        ]
      }), '')
      t.equal(returnSignals, 1, 'only exact observed Return emits dismissal')
      var next = Object.assign({}, payload, {
        activationId: 'a-00000000-0000-4000-8000-000000000002'
      })
      environmentClient.startEnvironment(next)
      environmentCalls[environmentCalls.length - 1].done(0, JSON.stringify({
        ok: true,
        operationId: 'op-next',
        environmentId: op.environmentId
      }), '')
      t.check(!environmentClient.submitting, 'acceptance releases submission busy before windows appear')
      environmentClient.identityRunner = function (done) {
        done('00000000-0000-4000-8000-000000000003')
      }
      t.check(environmentClient.startEnvironment({
        projectId: 'p-one',
        checkoutId: 'c-one',
        profileId: 'f-one',
        profileRevision: 1
      }), 'later deliberate activation is allowed while prior owner operation is observing')
      if (environmentClient.activationId !== 'a-00000000-0000-4000-8000-000000000003') {
        t.done()
        return
      }
      t.equal(environmentClient.activationId, 'a-00000000-0000-4000-8000-000000000003', 'new deliberate start receives a new kernel identity')
      var before = acceptedSignals
      environmentCalls[environmentCalls.length - 1].done(0, JSON.stringify({
        ok: true,
        operationId: 'op-malformed'
      }), '')
      t.check(environmentClient.acceptanceUnknown, 'incomplete acknowledgement is unknown acceptance')
      t.equal(acceptedSignals, before, 'incomplete acknowledgement cannot dismiss Projects')
      t.check(!environmentClient.startEnvironment(next), 'unknown acceptance holds another start until explicitly recovered')
      t.check(typeof environmentClient.startAnotherEnvironment === 'function', 'uncertainty permits explicitly starting different work while preserving the old identity')
      if (typeof environmentClient.startAnotherEnvironment !== 'function') {
        t.done()
        return
      }
      var uncertain = environmentClient.activationId
      var retained = JSON.parse(JSON.stringify(environmentClient.environmentTarget))
      environmentClient.captureActive = true
      t.check(!environmentClient.startAnotherEnvironment(next), 'capture refuses the explicit uncertainty escape')
      environmentClient.captureActive = false
      environmentClient.identityRunner = function (done) {
        done('00000000-0000-4000-8000-000000000004')
      }
      t.check(environmentClient.startAnotherEnvironment(next), 'explicit escape starts a fresh activation')
      t.equal(environmentClient.unresolvedEnvironmentActivations[0].activationId, uncertain, 'uncertain original activation stays recoverable')
      t.equal(environmentClient.unresolvedEnvironmentActivations[0].target, retained, 'uncertain original target remains immutable')
      t.equal(environmentClient.activationId, 'a-00000000-0000-4000-8000-000000000004', 'explicit escape ignores supplied old activation and generates a fresh UUID')
      t.equal(environmentCalls.filter(function (row) {
        return row.method === 'startEnvironment' && JSON.parse(row.args[0]).activationId === uncertain
      }).length, 1, 'explicit escape never replays the uncertain request')
      t.check(!environmentClient.startAnotherEnvironment(next), 'rapid escape duplicate cannot generate another activation')
      t.done()
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
              environmentTests()
            })
          })
        })
      })
    })
  }
}
