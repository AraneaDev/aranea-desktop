// A failing snapshot read must not stop observation or resubmit accepted work.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Recorded helper requests, used to detect accidental resubmission.
  property var calls: []
  // Deferred snapshot responses supplied by each scenario.
  property var results: []
  // Current transport-failure scenario index.
  property int scenario: 0
  // Whether the injected snapshot runner throws before replying.
  property bool throwSnapshot: false
  QmlTest {
    id: t
  }
  Projects.ProjectClient {
    id: client
    pollInterval: 20
    runner: function (argv, done) {
      if (host.throwSnapshot && argv[2] === 'snapshot')
        throw new Error('Snapshot transport failed')
      host.calls.push({
        method: argv[2],
        args: argv.slice(3),
        done: done
      })
    }
    onOperationChanged: function (operation) {
      host.results.push(operation)
    }
  }
  // Deliver real IPC-shaped operation state through the external boundary.
  function operation(state: string): string {
    return JSON.stringify({
      id: 'op-refresh',
      state: state,
      outcome: state === 'completed' ? 'partial' : null,
      steps: [
        {
          role: 'terminal',
          status: 'unconfirmed'
        }
      ],
      error: null
    })
  }
  // Run exit failure, invalid JSON and thrown transport without desktop access.
  function checkAcceptedObservation(): void {
    client.captureActive = true
    client.captureActive = false
    calls = []
    results = []
    throwSnapshot = false
    t.check(client.request({
      projectId: 'p-refresh',
      checkoutId: 'c-refresh'
    }), 'request is submitted')
    calls[0].done(0, '{"ok":true,"operationId":"op-refresh","error":null}', '')
    calls[1].done(0, operation('observing'), '')
    throwSnapshot = scenario === 2
    client.refresh()
    if (scenario === 0)
      calls[2].done(1, '', 'Snapshot unavailable')
    else if (scenario === 1)
      calls[2].done(0, 'invalid JSON', '')
    t.check(client.pending, 'snapshot failure preserves pending accepted observation')
    t.equal(client.operationId, 'op-refresh', 'snapshot failure retains the accepted operation identity')
    t.check(!!client.error, 'snapshot failure remains actionable')
    t.waitFor(function () {
      return calls.filter(function (call) {
        return call.method === 'operation'
      }).length === 2
    }, 1000, 'accepted operation continues polling after snapshot failure', function () {
      var read = calls.filter(function (call) {
        return call.method === 'operation'
      })[1]
      read.done(0, operation('completed'), '')
      t.check(!client.pending, 'completion clears pending observation')
      t.equal(results[results.length - 1].outcome, 'partial', 'observer preserves the authoritative terminal outcome')
      t.equal(calls.filter(function (call) {
        return call.method === 'request'
      }).length, 1, 'snapshot failure never resubmits accepted work')
      scenario++
      if (scenario < 3)
        checkAcceptedObservation()
      else
        checkPreparation()
    })
  }
  // A snapshot error cannot discard a request refused only for bounded readiness.
  function checkPreparation(): void {
    client.captureActive = true
    client.captureActive = false
    throwSnapshot = false
    calls = []
    client.request({
      projectId: 'p-refresh',
      checkoutId: 'c-refresh'
    })
    calls[0].done(0, '{"ok":false,"operationId":null,"error":{"code":"OWNER_NOT_READY","message":"Preparing checkout"}}', '')
    client.refresh()
    calls[1].done(1, '', 'Snapshot unavailable')
    t.check(client.pending && client.preparing, 'snapshot failure preserves rejected-only readiness preparation')
    t.waitFor(function () {
      return calls.filter(function (call) {
        return call.method === 'request'
      }).length === 2
    }, 1000, 'bounded readiness retry continues after snapshot failure', function () {
      var requests = calls.filter(function (call) {
        return call.method === 'request'
      })
      t.equal(requests[1].args, requests[0].args, 'readiness retry preserves the exact original request')
      requests[1].done(0, '{"ok":true,"operationId":"op-refresh","error":null}', '')
      var read = calls.filter(function (call) {
        return call.method === 'operation'
      })[0]
      read.done(0, operation('completed'), '')
      t.check(!client.pending && !client.preparing, 'prepared request completes once accepted')
      client.captureActive = true
      t.done()
    })
  }
  Component.onCompleted: checkAcceptedObservation()
}
