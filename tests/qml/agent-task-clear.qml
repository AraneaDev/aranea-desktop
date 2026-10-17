// Bulk clearing exercises the real view/client without starting providers.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: host
  // Deferred transport responses expose exact accepted operation ordering.
  property var calls: []
  TestCase {
    id: pointer
    name: "clearPointer"
    when: false
  }
  QmlTest {
    id: t
  }
  Activity.ActivityClient {
    id: client
    pollInterval: 60000
    runner: function (argv, done) {
      host.calls.push({
        argv: argv,
        done: done
      })
    }
  }
  Agents.TaskClearQueue {
    id: queue
    client: client
  }
  FloatingWindow {
    visible: true
    width: 340
    height: 600
    Agents.AgentTasks {
      id: view
      width: 320
      maxHeight: 500
      allowClear: true
      snapshot: client.snapshot
      pending: queue.pending || client.pending
      clearing: queue.pending
      error: queue.error || client.error
      onAction: function (kind, taskId) {
        if (kind === 'clear-inactive')
          queue.start(view.dismissibleTaskIds)
      }
    }
  }
  // Finished and disconnected records are independently eligible.
  function task(id, state, freshness) {
    return {
      taskId: id,
      provider: 'claude',
      reportedState: state,
      displayState: state,
      freshness: freshness,
      association: {
        status: 'unassigned'
      }
    }
  }
  // IDs the call at INDEX asked the owner to dismiss as one set.
  function sent(index) {
    return calls[index].argv[2] === 'dismissMany' ? JSON.parse(calls[index].argv[3]) : null
  }
  // Use exact IDs and owner lifetimes in the actual client's observation path.
  function accept(index, key) {
    calls[index].done(0, JSON.stringify({
      ok: true,
      operationId: 'op-' + key,
      ownerId: 'owner'
    }), '')
  }
  // Owner completion, not submission, permits the next set.
  function complete(index, key, refused) {
    calls[index].done(0, JSON.stringify({
      id: 'op-' + key,
      ownerId: 'owner',
      action: 'dismiss-many',
      state: 'completed',
      outcome: 'observed',
      result: {
        removed: 1,
        missing: 0,
        refused: refused || 0
      }
    }), '')
  }
  Component.onCompleted: {
    client.snapshot = {
      tasks: [task('live', 'working', 'connected'), task('done', 'finished', 'connected'), task('lost', 'working', 'connection-lost'), task('uncertain', 'finished', 'connected')],
      operations: [
        {
          taskId: 'uncertain',
          id: 'protected',
          action: 'reopen',
          submissionUnconfirmed: true
        }
      ]
    }
    t.step(400, function () {
      var ids = view.dismissibleTaskIds.slice()
      t.equal(ids.slice().sort(), ['done', 'lost'], 'clear excludes live and uncertain tasks')
      var button = t.findChild(view, 'clearInactiveTasks')
      t.check(button.visible && button.enabled, 'clear control available for eligible tasks')
      pointer.mouseClick(button, button.width / 2, button.height / 2)
      t.equal(calls.length, 1, 'one request on click')
      t.equal(sent(0), ids, 'every eligible identity sent as one set')
      t.check(queue.pending && !button.enabled, 'bulk pending disables repeat click')
      pointer.mouseClick(button, button.width / 2, button.height / 2)
      t.equal(calls.length, 1, 'double click cannot duplicate submission')
      accept(0, 'first')
      t.equal(calls[1].argv[2], 'operation', 'acceptance observed before completion')
      complete(1, 'first')
      t.waitFor(function () {
        return calls.length === 3
      }, 1500, 'refresh after bulk completion', function () {
        t.equal(calls[2].argv[2], 'snapshot', 'completion reads authoritative panel snapshot')
        calls[2].done(0, JSON.stringify({
          tasks: [task('live', 'working', 'connected'), task('uncertain', 'finished', 'connected')],
          operations: client.snapshot.operations
        }), '')
        t.check(!queue.pending && !queue.error, 'successful clear completes without error')
        t.equal(view.taskRows.map(function (r) {
          return r.key
        }).sort(), ['live', 'uncertain'], 'live/protected rows remain visible')
        t.check(!button.enabled, 'no eligible entries disables clear')
        refusedTasks()
      })
    })
  }
  // A task that became live is kept, and the batch says so.
  function refusedTasks() {
    var index = calls.length
    queue.start(['became-live', 'later'])
    t.equal(sent(index), ['became-live', 'later'], 'fresh explicit batch submits once')
    accept(index, 'refused')
    complete(index + 1, 'refused', 1)
    t.waitFor(function () {
      return !queue.pending
    }, 1500, 'batch with a kept task ends', function () {
      t.equal(queue.error && queue.error.code, 'TASK_LIVE', 'kept live task reported')
      t.check(queue.error.message.indexOf('1 task') >= 0, 'message counts the kept tasks')
      if (calls[calls.length - 1].argv[2] === 'snapshot')
        calls[calls.length - 1].done(0, JSON.stringify(client.snapshot), '')
      refusedAcceptance()
    })
  }
  // An owner refusal before acceptance stops the batch and keeps its reason.
  function refusedAcceptance() {
    var index = calls.length
    queue.start(['a', 'b'])
    calls[index].done(0, JSON.stringify({
      ok: false,
      operationId: null,
      error: {
        code: 'OWNER_NOT_READY',
        message: 'Activity is still loading.'
      }
    }), '')
    t.check(!queue.pending && queue.error.code === 'OWNER_NOT_READY', 'refused submission stops batch and exposes reason')
    t.step(60, function () {
      if (calls[calls.length - 1].argv[2] === 'snapshot')
        calls[calls.length - 1].done(0, JSON.stringify(client.snapshot), '')
      var before = calls.length
      t.check(!queue.start([]) && !queue.start(['same', 'same']), 'empty or duplicate identity lists refused')
      queue.captureActive = true
      t.check(!queue.start(['done']), 'capture refuses clearing')
      t.equal(calls.length, before, 'capture and invalid inputs produce no I/O')
      queue.captureActive = false
      uncertainTransport()
    })
  }
  // A lost owner after acceptance stops clearing and never resubmits.
  function uncertainTransport() {
    var index = calls.length
    queue.start(['uncertain-clear', 'later'])
    accept(index, 'uncertain-clear')
    calls[index + 1].done(1, '', 'Owner disconnected')
    t.check(!queue.pending && queue.error.code === 'OWNER_UNAVAILABLE', 'uncertain accepted dismissal stops bulk clearing')
    t.equal(client.operationId, 'op-uncertain-clear', 'uncertain acceptance ID retained for reconnection')
    var submissions = calls.filter(function (c) {
      return c.argv[2] === 'dismissMany'
    }).length
    t.step(60, function () {
      t.equal(calls.filter(function (c) {
        return c.argv[2] === 'dismissMany'
      }).length, submissions, 'transport uncertainty never advances or resubmits')
      largeBatch()
    })
  }
  // A long ID list goes in sets small enough for one IPC argument, in order,
  // and a failed list read between them does not cancel the batch.
  function largeBatch() {
    var ids = []
    for (var i = 0; i < 300; i++)
      ids.push('claude:' + 'x'.repeat(150) + ':' + i)
    var first = calls.length
    t.check(queue.start(ids), 'large batch starts')
    var seen = []
    var step = function () {
      var index = calls.length - 1
      var set = sent(index)
      t.check(!!set && calls[index].argv[3].length <= 16000, 'each set fits one IPC argument')
      seen = seen.concat(set || [])
      client.refresh()
      calls[calls.length - 1].done(0, '', 'Socket Error QLocalSocket::PeerClosedError')
      t.check(queue.pending, 'failed list read does not cancel the batch')
      accept(index, 'large-' + index)
      complete(calls.length - 1, 'large-' + index)
      t.waitFor(function () {
        return calls.length > index + 3 || !queue.pending
      }, 1500, 'next set or completion', function () {
        if (queue.pending && calls[calls.length - 1].argv[2] === 'dismissMany')
          step()
        else {
          t.equal(seen, ids, 'every identity sent once, in order')
          t.check(calls.filter(function (c, n) {
            return n >= first && c.argv[2] === 'dismissMany'
          }).length > 1, 'large batch split into several sets')
          t.check(!queue.pending && !queue.error, 'large batch finished without error')
          if (calls[calls.length - 1].argv[2] === 'snapshot')
            calls[calls.length - 1].done(0, JSON.stringify(client.snapshot), '')
          keyboardClear()
        }
      })
    }
    step()
  }
  // Keyboard clearing uses the same exact identities; capture cancels queued work.
  function keyboardClear() {
    client.snapshot = {
      tasks: [task('keyboard', 'finished', 'connected')],
      operations: []
    }
    view.disarmCursor()
    view.navigate(1)
    view.navigate(1)
    t.equal(view.cursorId, '-clear-inactive', 'clear reachable through task keyboard navigation')
    view.navigate(0)
    var index = calls.length - 1
    t.equal(sent(index), ['keyboard'], 'confirmed keyboard clear uses exact eligible identity')
    accept(index, 'keyboard')
    queue.captureActive = true
    complete(index + 1, 'keyboard')
    t.step(60, function () {
      t.check(!queue.pending, 'capture cancels queued work without resubmitting accepted dismissal')
      t.equal(client.operationId, 'op-keyboard', 'capture does not discard accepted owner identity')
      t.done()
    })
  }
}
