// Only explicit pre-mutation lock refusals may repeat a dismissal.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: host
  // Count mutation attempts independently from verification reads.
  property int mutations: 0
  // Count readback attempts after the accepted mutation.
  property int reads: 0
  // Simulate an unknown transport outcome that must never be replayed.
  property bool ambiguous: false
  // Exhaustion and domain refusals cannot turn into unbounded retries.
  property string mode: ''
  // Waits the runtime asked for before trying a busy store again.
  property var delays: []
  // Requests sent to the store, to check a set goes in one mutation.
  property var inputs: []
  QmlTest {
    id: t
  }
  // Uses the real retry timers.
  Activity.ActivityRuntime {
    id: realTimers
  }
  Activity.ActivityRuntime {
    id: runtime
    schedule: function (ms, fn) {
      host.delays = host.delays.concat([ms])
      Qt.callLater(fn)
    }
    processRunner: function (argv, input, done) {
      if (argv[1] === 'mutate') {
        mutations++
        host.inputs = host.inputs.concat([input])
        if (mode === 'many')
          done(0, JSON.stringify({
            ok: true,
            state: {
              tasks: [
                {
                  taskId: 'live'
                }
              ]
            },
            result: {
              removed: ['a', 'b'],
              missing: ['gone'],
              refused: ['live']
            }
          }), '')
        else if (host.ambiguous)
          done(124, '', 'Timed out')
        else if (mode === 'locked')
          done(1, JSON.stringify({
            ok: false,
            error: {
              code: 'ACTIVITY_LOCK_FAILED',
              message: 'Busy'
            }
          }), '')
        else if (mode === 'live')
          done(1, JSON.stringify({
            ok: false,
            error: {
              code: 'TASK_LIVE',
              message: 'Still working'
            }
          }), '')
        else if (mutations === 1)
          done(1, JSON.stringify({
            ok: false,
            error: {
              code: 'ACTIVITY_LOCK_FAILED',
              message: 'Busy'
            }
          }), '')
        else
          done(0, JSON.stringify({
            ok: true,
            state: {
              tasks: []
            }
          }), '')
      } else {
        reads++
        if (reads === 1)
          done(1, JSON.stringify({
            ok: false,
            error: {
              code: 'ACTIVITY_LOCK_FAILED',
              message: 'Busy'
            }
          }), '')
        else
          done(0, JSON.stringify({
            ok: true,
            state: {
              tasks: []
            }
          }), '')
      }
    }
  }
  // A capture that starts while a busy store waits for its retry ends the
  // dismissal right away instead of leaving it until the owner's deadline.
  function captureDuringBackoff() {
    var answer = null, tries = 0
    realTimers.processRunner = function (argv, input, done) {
      tries++
      done(1, JSON.stringify({
        ok: false,
        error: {
          code: 'ACTIVITY_LOCK_FAILED',
          message: 'Busy'
        }
      }), '')
    }
    realTimers.dismiss('busy-capture', function (response) {
      answer = response
    })
    t.check(answer === null && tries === 1, 'busy store waits for a retry')
    realTimers.captureActive = true
    t.step(400, function () {
      t.check(!!answer && !answer.ok && answer.error.code === 'INERT_MODE', 'capture answers the waiting dismissal')
      t.equal(tries, 1, 'no mutation is tried during the capture')
      t.done()
    })
  }
  Component.onCompleted: runtime.dismiss('old-task', function (response) {
    t.check(response.ok, 'explicit lock contention is retried to confirmed removal')
    t.equal(mutations, 2, 'only refused pre-mutation attempt is retried')
    t.equal(reads, 2, 'readback contention retries only the read, never the mutation')
    ambiguous = true
    var before = mutations
    runtime.dismiss('uncertain', function (lost) {
      t.check(!lost.ok && lost.transportUnconfirmed, 'ambiguous transport stays unconfirmed')
      t.equal(mutations, before + 1, 'ambiguous mutation is never repeated')
      ambiguous = false
      mode = 'locked'
      var bounded = mutations
      delays = []
      runtime.dismiss('busy', function (refused) {
        t.check(!refused.ok && refused.error.code === 'ACTIVITY_LOCK_FAILED', 'persistent lock refusal remains visible')
        t.equal(mutations, bounded + 4, 'lock retries are bounded to three retries')
        t.equal(delays, [250, 500, 1000], 'busy store is retried after 250, 500 and 1000 ms')
        mode = 'live'
        var liveBefore = mutations
        runtime.dismiss('live', function (active) {
          t.equal(active.error.code, 'TASK_LIVE', 'working-task refusal preserved')
          t.equal(mutations, liveBefore + 1, 'domain refusal never retries')
          mode = 'many'
          inputs = []
          runtime.dismissMany(['a', 'b', 'gone', 'live'], function (many) {
            t.check(many.ok, 'set dismissal confirmed')
            t.equal(inputs.map(function (input) {
              return JSON.parse(input)
            }), [
              {
                action: 'dismiss-many',
                args: {
                  taskIds: ['a', 'b', 'gone', 'live']
                }
              }
            ], 'whole set sent in one store mutation')
            t.equal(many.result, {
              removed: ['a', 'b'],
              missing: ['gone'],
              refused: ['live']
            }, 'store per-ID outcome kept after the confirmation read')
            captureDuringBackoff()
          })
        })
      })
    })
  })
}
