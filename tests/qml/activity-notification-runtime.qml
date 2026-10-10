// Fixed native argv and policy parsing, with every process replaced by inert replies.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: root
  // Inert fixture state for the actual notification boundary.
  property string dnd: 'off'
  // Inert fixture state for the actual notification boundary.
  property string quiet: 'scheduled'
  // Inert fixture state for the actual notification boundary.
  property var calls: []
  // Inert fixture state for the actual notification boundary.
  property var policy: null
  QmlTest {
    id: t
  }
  Activity.ActivityRuntime {
    id: runtime
    processRunner: function (argv, input, done) {
      root.calls.push(argv)
      if (argv.indexOf('dndState') >= 0)
        done(0, root.dnd, '')
      else if (argv.indexOf('quietState') >= 0)
        done(0, root.quiet, '')
      else if (argv.indexOf('notify-send') >= 0)
        done(0, '42\ndefault\n', '')
      else
        done(1, '', 'Missing Agents widget')
    }
  }
  Component.onCompleted: {
    t.check(typeof runtime.readNotificationPolicy === 'function', 'policy reader exists')
    if (typeof runtime.readNotificationPolicy !== 'function') {
      t.done()
      return
    }
    runtime.readNotificationPolicy(function (value) {
      root.policy = value
    })
    t.check(policy.available && !policy.suppressed, 'scheduled inactive quiet hours permits normal notification')
    quiet = 'on'
    runtime.readNotificationPolicy(function (value) {
      root.policy = value
    })
    t.check(policy.available && policy.suppressed, 'active quiet hours suppresses')
    dnd = 'unknown'
    runtime.readNotificationPolicy(function (value) {
      root.policy = value
    })
    t.check(!policy.available, 'malformed DND is unavailable')
    runtime.notifyAttention({
      title: 'Title',
      body: 'literal $(false)',
      taskId: 't'
    }, function (result) {
      t.check(result.accepted && result.activated, 'native fixed default action decoded')
    })
    var argv = calls[calls.length - 1]
    t.check(argv.indexOf('--urgency=normal') >= 0 && argv.indexOf('--action=default=Open task') >= 0, 'normal urgency and fixed action only')
    t.equal(argv[argv.length - 1], 'literal $(false)', 'text stays a bounded argument')
    runtime.showTask('t', function (result) {
      t.check(!result.ok, 'missing panel is explicitly unavailable')
    })
    var before = calls.length
    runtime.captureActive = true
    runtime.notifyAttention({
      title: 'Title',
      body: 'Body'
    }, function () {})
    runtime.readNotificationPolicy(function () {})
    runtime.showTask('t', function () {})
    t.equal(calls.length, before, 'capture refuses all native notification and navigation I/O')
    t.done()
  }
}
