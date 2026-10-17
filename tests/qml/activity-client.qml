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
      detailsBesideWork()
      mismatchedPage({
        token: 'other-read',
        total: 2
      }, 'page of another read')
      mismatchedPage({
        token: 'read-7',
        total: 3
      }, 'page with another total')
      finishCapture()
    })
  }
  // A details read is read-only: its failure leaves a dismissal being observed
  // alone, and a submission started meanwhile does not drop its answer.
  function detailsBesideWork() {
    client.dismiss('d')
    var index = calls.length - 1
    calls[index].done(0, '{"ok":true,"operationId":"dismiss-d","ownerId":"o"}', '')
    t.check(client.pending && calls[index + 1].argv[2] === 'operation', 'dismissal observed')
    client.readTask('a')
    calls[calls.length - 1].done(1, '', 'Socket Error QLocalSocket::PeerClosedError')
    t.check(client.pending, 'failed details read keeps the dismissal pending')
    t.equal(client.error, null, 'failed details read sets no shared error')
    t.check(client.available, 'failed details read does not mark the owner unavailable')
    calls[index + 1].done(0, '{"id":"dismiss-d","ownerId":"o","state":"completed","outcome":"observed"}', '')
    t.check(!client.pending, 'dismissal completes')
    client.readTask('b')
    var details = calls.length - 1
    client.dismiss('e')
    calls[details].done(0, JSON.stringify({
      ok: true,
      task: {
        taskId: 'b',
        result: 'full b'
      }
    }), '')
    t.equal(client.taskDetails.result, 'full b', 'details answer kept although a submission started')
    calls[calls.length - 1].done(0, '{"ok":true,"operationId":"dismiss-e","ownerId":"o"}', '')
    calls[calls.length - 1].done(0, '{"id":"dismiss-e","ownerId":"o","state":"completed","outcome":"observed"}', '')
  }
  // A page that does not belong to the read in progress abandons that read
  // and keeps the last snapshot.
  function mismatchedPage(fields, name) {
    var kept = client.snapshot
    client.refresh()
    var first = calls.length - 1
    calls[first].done(0, JSON.stringify({
      ownerId: 'o',
      revision: 7,
      tasks: [
        {
          taskId: 'x'
        }
      ],
      operations: [],
      taskPage: {
        token: 'read-7',
        total: 2
      }
    }), '')
    calls[first + 1].done(0, JSON.stringify(Object.assign({
      ok: true,
      offset: 1,
      tasks: [
        {
          taskId: 'y'
        }
      ]
    }, fields)), '')
    t.equal(client.snapshot, kept, name + ' keeps the last snapshot')
    t.equal(client.pagingRead, 0, name + ' ends the read')
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
