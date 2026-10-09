// Real persistent owner with inert policy, delivery and navigation boundaries.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: root
  // Inert fixture state for the actual notification boundary.
  property var state: ({
      tasks: [],
      sessions: []
    })
  // Inert fixture state for the actual notification boundary.
  property var policy: ({
      available: true,
      suppressed: false
    })
  // Inert fixture state for the actual notification boundary.
  property var notices: []
  // Inert fixture state for the actual notification boundary.
  property var activations: []
  // Inert fixture state for the actual notification boundary.
  property int opened: 0
  QmlTest {
    id: t
  }
  Activity.ActivityController {
    id: owner
    pollInterval: 60000
    runtime: ({
        sessionId: 'inert',
        readStore: function (done) {
          done({
            ok: true,
            state: root.state
          })
        },
        readNotificationPolicy: function (done) {
          done(root.policy)
        },
        notifyAttention: function (notice, done) {
          root.notices.push(notice)
          root.activations.push(done)
        },
        showTask: function (id, done) {
          root.opened++
          done({
            ok: true,
            status: 'requested'
          })
        }
      })
  }
  // Supply the next successful durable snapshot without store I/O.
  function change(value) {
    state = {
      tasks: value ? [
        {
          taskId: 't',
          producerEpoch: 'e',
          reportedState: value,
          description: 'Task',
          blockers: []
        }
      ] : [],
      sessions: []
    }
    owner.refresh()
  }
  Component.onCompleted: {
    t.check(typeof owner.flushNotifications === 'function', 'persistent notification queue exists')
    if (typeof owner.flushNotifications !== 'function') {
      t.done()
      return
    }
    change('needs-input')
    owner.flushNotifications()
    t.equal(notices.length, 0, 'restart consumes historical attention')
    change('working')
    change('needs-input')
    change('ready-for-review')
    state = {
      tasks: [Object.assign({}, state.tasks[0], {
          description: 'Latest burst summary'
        })],
      sessions: []
    }
    owner.refresh()
    t.step(1000, function () {
      t.equal(notices.length, 0, 'burst does not emit before two seconds')
      t.step(1200, function () {
        t.equal(notices.length, 1, 'two-second burst coalesces latest task state')
        t.check(notices[0].title.indexOf('Ready for review') >= 0, 'coalesced notice uses latest state')
        t.equal(notices[0].body, 'Latest burst summary', 'same-identity updates refresh the queued notification text')
        change('ready-for-review')
        owner.flushNotifications()
        t.equal(notices.length, 1, 'repeated state does not duplicate')
        policy = {
          available: true,
          suppressed: true
        }
        change('failed')
        owner.flushNotifications()
        policy = {
          available: true,
          suppressed: false
        }
        change('failed')
        owner.flushNotifications()
        t.equal(notices.length, 1, 'DND consumes without replay')
        policy = {
          available: false,
          suppressed: false
        }
        change('needs-input')
        owner.flushNotifications()
        policy = {
          available: true,
          suppressed: false
        }
        change('needs-input')
        owner.flushNotifications()
        t.equal(notices.length, 1, 'unknown policy never means known off')
        change(null)
        activations[0]({
          accepted: true,
          activated: true
        })
        t.equal(opened, 0, 'removed notification target cannot open another task')
        change('failed')
        owner.flushNotifications()
        state = {
          tasks: [Object.assign({}, state.tasks[0], {
              description: 'Fresh activation snapshot'
            })],
          sessions: []
        }
        activations[1]({
          accepted: true,
          activated: true
        })
        t.equal(owner.snapshot().tasks[0].description, 'Fresh activation snapshot', 'panel lookup can read the fresh activation snapshot')
        t.equal(opened, 1, 'activation rereads current stable task before showTask')
        owner.captureActive = true
        activations[1]({
          accepted: true,
          activated: true
        })
        owner.flushNotifications()
        t.equal(opened, 1, 'capture refuses activation and notification effects')
        t.done()
      })
    })
  }
}
