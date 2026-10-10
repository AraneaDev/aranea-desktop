// Deferred real owner policy callbacks expose refresh, replacement and suppression races.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: root
  // The store boundary succeeds synchronously while policy replies are held separately.
  property var state: ({
      tasks: [],
      sessions: []
    })
  // Retained callbacks may arrive in any order, including after capture ends.
  property var policies: []
  // Every emitted notice comes from the real owner's fixed delivery path.
  property var notices: []
  QmlTest {
    id: t
  }
  Activity.ActivityController {
    id: owner
    pollInterval: 60000
    runtime: ({
        sessionId: 'fixture-desktop',
        readStore: function (done) {
          done({
            ok: true,
            state: root.state
          })
        },
        readNotificationPolicy: function (done) {
          root.policies.push(done)
        },
        notifyAttention: function (notice, done) {
          root.notices.push(notice)
        }
      })
  }
  // Publish the current task identity, with optional same-key text changes.
  function change(value, description) {
    state = {
      tasks: value ? [
        {
          taskId: 't',
          producerEpoch: 'e',
          reportedState: value,
          description: description || 'Task',
          blockers: []
        }
      ] : [],
      sessions: []
    }
    owner.refresh()
  }
  // Complete one held native policy read; retaining it allows duplicate-callback assertions.
  function reply(index, policy) {
    if (index >= policies.length) {
      t.check(false, 'expected deferred policy request ' + index)
      return
    }
    policies[index](policy)
  }
  // Resolve a final policy check only if this flush actually queued one.
  function flushAllowed() {
    var before = policies.length
    owner.flushNotifications()
    if (policies.length > before)
      reply(before, {
        available: true,
        suppressed: false
      })
  }
  Component.onCompleted: {
    change('working')
    change('needs-input')
    var original = policies.length - 1
    change('needs-input', 'Latest unchanged refresh')
    t.step(10, function () {
      reply(original, {
        available: true,
        suppressed: false
      })
      flushAllowed()
      t.equal(notices.length, 1, 'unchanged successful refresh preserves exactly one pending transition')
      if (notices.length)
        t.equal(notices[0].body, 'Latest unchanged refresh', 'late policy uses latest same-key text')
      reply(original, {
        available: true,
        suppressed: false
      })
      flushAllowed()
      t.equal(notices.length, 1, 'repeated callback cannot duplicate a consumed transition')

      change('working')
      change('needs-input')
      var old = policies.length - 1
      change('failed')
      var latest = policies.length - 1
      reply(latest, {
        available: true,
        suppressed: false
      })
      reply(old, {
        available: true,
        suppressed: false
      })
      flushAllowed()
      t.equal(notices.length, 2, 'out-of-order replies emit only the latest task identity')
      if (notices.length > 1)
        t.check(notices[1].title.indexOf('Failed') >= 0, 'new state is not overwritten by older policy')

      change('needs-input')
      var removed = policies.length - 1
      change(null)
      reply(removed, {
        available: true,
        suppressed: false
      })
      flushAllowed()
      t.equal(notices.length, 2, 'removed target pending policy never emits')

      change('working')
      change('needs-input')
      var suppressed = policies.length - 1
      change('needs-input')
      reply(suppressed, {
        available: true,
        suppressed: true
      })
      reply(suppressed, {
        available: true,
        suppressed: false
      })
      change('needs-input')
      flushAllowed()
      t.equal(notices.length, 2, 'suppressed pending transition is consumed without late replay')

      change('failed')
      var unavailable = policies.length - 1
      change('failed')
      reply(unavailable, {
        available: false,
        suppressed: false
      })
      reply(unavailable, {
        available: true,
        suppressed: false
      })
      change('failed')
      flushAllowed()
      t.equal(notices.length, 2, 'unknown pending policy consumes without late backlog')

      change('needs-input')
      var beforeCapture = policies.length - 1
      owner.captureActive = true
      owner.captureActive = false
      reply(beforeCapture, {
        available: true,
        suppressed: false
      })
      flushAllowed()
      t.equal(notices.length, 2, 'capture lifetime invalidates held policy even after capture ends')

      change('failed')
      reply(policies.length - 1, {
        available: true,
        suppressed: false
      })
      var beforeFlush = policies.length
      owner.flushNotifications()
      change('working')
      change('failed')
      var newerSameKey = policies.length - 1
      reply(newerSameKey, {
        available: true,
        suppressed: false
      })
      reply(beforeFlush, {
        available: true,
        suppressed: false
      })
      flushAllowed()
      t.equal(notices.length, 3, 'late final policy cannot duplicate a newer occurrence of the same key')
      // Suppression during the final check consumes the token, including late duplicate replies.
      change('needs-input')
      reply(policies.length - 1, {
        available: true,
        suppressed: false
      })
      var finalSuppressed = policies.length
      owner.flushNotifications()
      reply(finalSuppressed, {
        available: true,
        suppressed: true
      })
      reply(finalSuppressed, {
        available: true,
        suppressed: false
      })
      change('needs-input')
      flushAllowed()
      t.equal(notices.length, 3, 'final DND check consumes without a late allowed replay')

      change('failed')
      reply(policies.length - 1, {
        available: true,
        suppressed: false
      })
      var finalUnknown = policies.length
      owner.flushNotifications()
      reply(finalUnknown, {
        available: false,
        suppressed: false
      })
      reply(finalUnknown, {
        available: true,
        suppressed: false
      })
      change('failed')
      flushAllowed()
      t.equal(notices.length, 3, 'final unknown policy consumes without a late backlog')

      change('needs-input')
      reply(policies.length - 1, {
        available: true,
        suppressed: false
      })
      var capturedDelivery = policies.length
      owner.flushNotifications()
      owner.captureActive = true
      owner.captureActive = false
      reply(capturedDelivery, {
        available: true,
        suppressed: false
      })
      t.equal(notices.length, 3, 'capture invalidates an outstanding final policy check')
      owner.captureActive = true
      t.done()
    })
  }
}
