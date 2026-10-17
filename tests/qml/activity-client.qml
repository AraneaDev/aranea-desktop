// IPC reconnect is read-only after acceptance, independent of snapshot generations.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: root
  // Captured transport callbacks permit deterministic disconnect and stale-read tests.
  property var calls: []
  QmlTest {
    id: t
  }
  Activity.ActivityClient {
    id: client
    pollInterval: 60000
    runner: function (argv, done) {
      root.calls.push({
        argv: argv,
        done: done
      })
    }
  }
  Component.onCompleted: {
    client.refresh()
    client.refresh()
    calls[1].done(0, '{"ownerId":"o","revision":2,"tasks":[]}', '')
    calls[0].done(0, '{"ownerId":"o","revision":1,"tasks":[]}', '')
    t.equal(client.snapshot.revision, 2, 'stale snapshot rejected')
    client.request({
      action: 'reopen',
      taskId: 't'
    })
    calls[2].done(0, '{"ok":false,"operationId":null,"error":{"code":"OWNER_NOT_READY","message":"Wait"}}', '')
    client.submitRequest()
    calls[3].done(0, '{"ok":true,"operationId":"op","ownerId":"o"}', '')
    t.equal(client.operationId, 'op', 'acceptance retains stable ID')
    calls[4].done(1, '', 'disconnected')
    t.equal(client.operationId, 'op', 'postaccept disconnect retains ID')
    client.reconnect()
    t.equal(calls[5].argv[2], 'operation', 'reconnect queries operation only')
    calls[5].done(0, '{"id":"op","ownerId":"o","state":"completed","outcome":"partial"}', '')
    client.reobserve()
    t.equal(calls[6].argv[2], 'reobserve', 'explicit reobserve uses observation-only endpoint')
    calls[6].done(0, '{"ok":true,"operationId":"op","ownerId":"o"}', '')
    calls[7].done(0, '{"id":"op","ownerId":"other","state":"completed","outcome":"observed"}', '')
    t.equal(client.error.code, 'OPERATION_LOST', 'owner restart rejects stale accepted ID')
    t.equal(calls.filter(function (c) {
      return c.argv[2] === 'request'
    }).length, 2, 'only preaccept readiness refusal resubmitted')
    client.dismiss('t')
    t.equal(calls[8].argv[2], 'dismiss', 'dismiss uses owner queue endpoint')
    calls[8].done(0, '{"ok":true,"operationId":"dismiss-op","ownerId":"o"}', '')
    calls[9].done(0, '{"id":"dismiss-op","ownerId":"o","state":"completed","outcome":"observed"}', '')
    t.equal(client.operationId, 'dismiss-op', 'dismiss acceptance observed by stable ID')
    // A refresh while later pages load waits for them instead of starting over.
    client.refresh()
    var first = calls.length - 1
    calls[first].done(0, JSON.stringify({
      ownerId: 'o',
      revision: 5,
      tasks: [
        {
          taskId: 'a',
          preview: true
        }
      ],
      operations: [],
      taskPage: {
        token: 'read-5',
        total: 2
      }
    }), '')
    t.equal(calls[first + 1].argv.slice(2), ['snapshotPage', 'read-5', '1'], 'next page requested')
    client.refresh()
    client.refresh()
    t.equal(calls.length, first + 2, 'refresh during paging does not abandon the read')
    calls[first + 1].done(0, JSON.stringify({
      ok: true,
      token: 'read-5',
      offset: 1,
      total: 2,
      tasks: [
        {
          taskId: 'b',
          preview: true
        }
      ]
    }), '')
    t.equal(client.snapshot.tasks.map(function (task) {
      return task.taskId
    }), ['a', 'b'], 'paged read completes')
    t.equal(client.snapshot.tasks[0].diagnostics, [], 'preview rows expanded to the full shape')
    t.equal(client.snapshot.tasks[0].verification.status, 'unknown', 'preview verification restored')
    t.step(30, function () {
      t.equal(calls.length, first + 3, 'one queued refresh runs after the read')
      t.equal(calls[first + 2].argv[2], 'snapshot', 'queued refresh reads again')
      calls[first + 2].done(0, JSON.stringify({
        ownerId: 'o',
        revision: 6,
        tasks: [],
        operations: []
      }), '')
      client.readTask('a')
      t.equal(calls[first + 3].argv.slice(2), ['task', 'a'], 'details read the task by ID')
      calls[first + 3].done(0, JSON.stringify({
        ok: true,
        task: {
          taskId: 'a',
          result: 'full'
        }
      }), '')
      t.equal(client.taskDetails.result, 'full', 'details task kept')
      finishCapture()
    })
  }
  // Capture refuses every later read and action.
  function finishCapture() {
    var before = calls.length
    client.captureActive = true
    client.refresh()
    client.reconnect()
    client.readTask('a')
    client.request({
      action: 'focus',
      taskId: 't'
    })
    t.equal(calls.length, before, 'capture refuses all client I/O')
    t.done()
  }
}
