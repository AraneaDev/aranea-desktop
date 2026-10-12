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
  QmlTest {
    id: t
  }
  Activity.ActivityRuntime {
    id: runtime
    processRunner: function (argv, input, done) {
      if (argv[1] === 'mutate') {
        mutations++
        if (host.ambiguous)
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
      runtime.dismiss('busy', function (refused) {
        t.check(!refused.ok && refused.error.code === 'ACTIVITY_LOCK_FAILED', 'persistent lock refusal remains visible')
        t.equal(mutations, bounded + 4, 'lock retries are bounded to three retries')
        mode = 'live'
        var liveBefore = mutations
        runtime.dismiss('live', function (active) {
          t.equal(active.error.code, 'TASK_LIVE', 'working-task refusal preserved')
          t.equal(mutations, liveBefore + 1, 'domain refusal never retries')
          t.done()
        })
      })
    })
  })
}
