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
  // Use exact IDs and owner lifetimes in the actual client's observation path.
  function accept(index, id) {
    calls[index].done(0, JSON.stringify({
      ok: true,
      operationId: 'op-' + id,
      ownerId: 'owner'
    }), '')
  }
  // Owner completion, not submission, permits the next deletion.
  function complete(index, id) {
    calls[index].done(0, JSON.stringify({
      id: 'op-' + id,
      ownerId: 'owner',
      taskId: id,
      action: 'dismiss',
      state: 'completed',
      outcome: 'observed'
    }), '')
  }
  // A task that is already gone counts as cleared, and a failed list read
  // while the batch runs does not cancel it.
  function resilientBatch() {
    t.check(queue.start(['already-gone', 'still-here']), 'new batch starts')
    var first = calls.length - 1
    t.equal(calls[first].argv.slice(2), ['dismiss', 'already-gone'], 'first identity submitted')
    calls[first].done(0, JSON.stringify({
      ok: false,
      operationId: null,
      error: {
        code: 'TASK_NOT_FOUND',
        message: 'The task is no longer tracked.'
      }
    }), '')
    t.waitFor(function () {
      return calls.some(function (c, i) {
        return i > first && c.argv[2] === 'dismiss' && c.argv[3] === 'still-here'
      })
    }, 1500, 'missing task moves on to the next identity', function () {
      var index = calls.length - 1
      t.check(queue.pending && !queue.error, 'missing task is not a batch failure')
      client.refresh()
      calls[calls.length - 1].done(0, '', 'Socket Error QLocalSocket::PeerClosedError')
      t.check(queue.pending, 'failed list read does not cancel the batch')
      accept(index, 'still-here')
      complete(calls.length - 1, 'still-here')
      t.waitFor(function () {
        return !queue.pending
      }, 1500, 'batch completes after the failed read', function () {
        t.check(!queue.error, 'batch finished without error')
        t.done()
      })
    })
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
      t.equal(calls.length, 1, 'one dismissal submitted on click')
      t.equal(calls[0].argv.slice(2), ['dismiss', ids[0]], 'exact first identity submitted')
      t.check(queue.pending && !button.enabled, 'bulk pending disables repeat click')
      pointer.mouseClick(button, button.width / 2, button.height / 2)
      t.equal(calls.length, 1, 'double click cannot duplicate submission')
      accept(0, ids[0])
      t.equal(calls[1].argv[2], 'operation', 'acceptance observed before next dismissal')
      complete(1, ids[0])
      t.waitFor(function () {
        return calls.length === 3
      }, 1500, 'next dismissal after observation', function () {
        t.equal(calls[2].argv.slice(2), ['dismiss', ids[1]], 'exact second identity submitted')
        accept(2, ids[1])
        complete(3, ids[1])
        t.waitFor(function () {
          return calls.length === 5
        }, 1500, 'refresh after bulk completion', function () {
          t.equal(calls[4].argv[2], 'snapshot', 'completion reads authoritative panel snapshot')
          calls[4].done(0, JSON.stringify({
            tasks: [task('live', 'working', 'connected'), task('uncertain', 'finished', 'connected')],
            operations: client.snapshot.operations
          }), '')
          t.check(!queue.pending && !queue.error, 'successful clear completes without error')
          t.equal(view.taskRows.map(function (r) {
            return r.key
          }).sort(), ['live', 'uncertain'], 'live/protected rows remain visible')
          t.check(!button.enabled, 'no eligible entries disables clear')
          queue.start(['became-live', 'later'])
          t.equal(calls[5].argv.slice(2), ['dismiss', 'became-live'], 'fresh explicit batch submits once')
          calls[5].done(0, JSON.stringify({
            ok: false,
            error: {
              code: 'TASK_LIVE',
              message: 'Task is live'
            }
          }), '')
          t.check(!queue.pending && queue.error.code === 'TASK_LIVE', 'store refusal stops batch and exposes reason')
          t.step(60, function () {
            t.check(!calls.some(function (c) {
              return c.argv[2] === 'dismiss' && c.argv[3] === 'later'
            }), 'refusal never clears remaining entries')
            if (calls[6])
              calls[6].done(0, JSON.stringify(client.snapshot), '')
            var before = calls.length
            t.check(!queue.start([]) && !queue.start(['same', 'same']), 'empty or duplicate identity lists refused')
            queue.captureActive = true
            t.check(!queue.start(['done']), 'capture refuses clearing')
            t.equal(calls.length, before, 'capture and invalid inputs produce no I/O')
            queue.captureActive = false
            var disconnected = calls.length
            queue.start(['uncertain-clear', 'later'])
            accept(disconnected, 'uncertain-clear')
            calls[disconnected + 1].done(1, '', 'Owner disconnected')
            t.check(!queue.pending && queue.error.code === 'OWNER_UNAVAILABLE', 'uncertain accepted dismissal stops bulk clearing')
            t.equal(client.operationId, 'op-uncertain-clear', 'uncertain acceptance ID retained for reconnection')
            var dismissCount = calls.filter(function (c) {
              return c.argv[2] === 'dismiss'
            }).length
            t.step(60, function () {
              t.equal(calls.filter(function (c) {
                return c.argv[2] === 'dismiss'
              }).length, dismissCount, 'transport uncertainty never advances or resubmits')
              client.snapshot = {
                tasks: [task('keyboard', 'finished', 'connected')],
                operations: []
              }
              view.disarmCursor()
              view.navigate(1)
              view.navigate(1)
              t.equal(view.cursorId, '-clear-inactive', 'clear reachable through task keyboard navigation')
              view.navigate(0)
              t.equal(calls[calls.length - 1].argv.slice(2), ['dismiss', 'keyboard'], 'confirmed keyboard clear uses exact eligible identity')
              var cancelled = calls.length - 1
              accept(cancelled, 'keyboard')
              queue.captureActive = true
              complete(cancelled + 1, 'keyboard')
              t.step(60, function () {
                t.check(!queue.pending, 'capture cancels queued work without resubmitting accepted dismissal')
                t.equal(client.operationId, 'op-keyboard', 'capture does not discard accepted owner identity')
                queue.captureActive = false
                resilientBatch()
              })
            })
          })
        })
      })
    })
  }
}
