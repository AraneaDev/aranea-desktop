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
  QmlTest {
    id: t
  }
  Projects.ProjectClient {
    id: client
    pollInterval: 20
    runner: function (argv, done) {
      root.commands.push(argv)
      Qt.callLater(function () {
        var method = argv[2]
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
  Component.onCompleted: {
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
        client.runner = function (argv, done) {
          done(1, '', 'owner unavailable')
        }
        client.refresh()
        t.check(!client.available && !!client.error, 'unavailable IPC surfaces actionable error')
        t.done()
      })
    })
  }
}
