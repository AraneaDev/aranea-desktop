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
    client.captureActive = true
    client.refresh()
    client.reconnect()
    client.request({
      action: 'focus',
      taskId: 't'
    })
    t.equal(calls.length, 10, 'capture refuses all client I/O')
    t.done()
  }
}
