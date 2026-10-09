// Inert Tasks navigation and identity tests; provider data never invokes a process.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents

ShellRoot {
  id: host
  // Stable actions emitted by the actual view.
  property var actions: []
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }
  QmlTest {
    id: t
  }
  FloatingWindow {
    visible: true
    width: 300
    height: 500
    Agents.AgentTasks {
      id: view
      width: 280
      maxHeight: 260
      captureActive: true
      snapshot: ({
          tasks: [host.task('one', 'working'), host.task('two', 'needs-input')]
        })
      onAction: function (kind, taskId) {
        host.actions.push([kind, taskId])
      }
    }
    Agents.AgentTaskNavigation {
      id: tabs
      width: 280
      taskRows: view.taskRows
      usageCount: 0
      onAction: function (kind, taskId) {
        host.actions.push([kind, taskId])
      }
    }
  }
  // Fixtures retain exact association identities.
  function task(id, state) {
    return {
      taskId: id,
      provider: 'claude',
      reportedState: state,
      displayState: state,
      freshness: 'connected',
      description: '<b>Long task summary</b>',
      association: {
        status: 'unassigned',
        cwd: '/a/very/long/checkout/path'
      }
    }
  }
  Component.onCompleted: t.step(60, function () {
    t.equal(view.taskRows[0].key, 'two', 'attention row comes first')
    t.equal(tabs.destination, 'tasks', 'task-only session defaults to Tasks')
    tabs.usageCount = 1
    view.snapshot = {
      tasks: []
    }
    tabs.remembered = ''
    t.equal(tabs.destination, 'usage', 'Usage-only session defaults to Usage')
    tabs.choose('tasks')
    t.equal(tabs.destination, 'tasks', 'empty Tasks remains accessible and remembered')
    t.check(t.findChild(view, 'tasksEmpty').visible, 'empty task setup is visible')
    view.navigate(1)
    view.navigate(1)
    view.navigate(-1)
    t.check(actions.every(function (a) {
      return a[0] !== 'setup'
    }), 'empty arrow and j/k direction changes never activate setup')
    view.disarmCursor()
    view.navigate(0)
    t.check(actions.every(function (a) {
      return a[0] !== 'setup'
    }), 'first empty Enter reveals setup')
    view.navigate(0)
    t.equal(actions.pop(), ['setup', ''], 'setup emits a fixed action')
    view.snapshot = {
      tasks: [task('one', 'working'), task('two', 'needs-input')]
    }
    view.navigate(0)
    t.equal(actions.filter(function (a) {
      return a[0] === 'details'
    }).length, 0, 'first Enter only reveals cursor')
    view.navigate(0)
    t.equal(view.selectedId, 'two', 'second Enter selects stable task')
    view.back()
    view.snapshot = {
      tasks: [task('one', 'working')]
    }
    view.navigate(0)
    t.equal(view.selectedId, '', 'removed cursor cannot transfer Enter')
    view.navigate(0)
    t.equal(view.selectedId, 'one', 'subsequent confirmed Enter selects replacement')
    view.back()
    view.snapshot = {
      tasks: [task('one', 'working'), task('two', 'failed')]
    }
    view.cursorId = 'one'
    view.keyboardCursor = true
    view.snapshot = {
      tasks: [task('two', 'needs-input'), task('one', 'working')]
    }
    view.navigate(0)
    t.equal(view.selectedId, 'one', 'sort preserves keyboard identity')
    view.back()
    view.layoutChangedAt = Date.now()
    t.equal(view.openDetails('two', true), false, 'settling blocks pointer adoption')
    view.error = {
      message: 'Owner unavailable',
      recovery: 'Activate Aranea'
    }
    t.check(t.findChild(view, 'tasksError').visible, 'structured owner error is reachable')
    t.equal(t.findChild(view, 'tasksError').textFormat, Text.PlainText, 'error text is plaintext')
    t.check(view.height <= 260, 'narrow list obeys height cap')
    t.check(view.scroll.contentHeight > view.scroll.height, 'narrow tall content scrolls')
    t.equal(t.findChild(view, 'taskSummary').textFormat, Text.PlainText, 'provider summary is plaintext')
    view.snapshot = {
      tasks: ['working', 'needs-input', 'ready-for-review', 'failed', 'finished', 'connection-lost'].map(function (state, index) {
        return Object.assign(task(state, state), {
          provider: index % 2 ? 'codex' : 'claude'
        })
      })
    }
    t.equal(view.taskRows.map(function (r) {
      return r.stateLabel
    }), ['Needs input', 'Ready for review', 'Failed', 'Working', 'Connection lost', 'Finished'], 'all six states render in attention order')
    t.equal(t.findChildren(view, 'taskRow').length, 6, 'actual delegates display all states')
    t.check(view.taskRows.some(function (r) {
      return r.providerLabel === 'Codex'
    }), 'multiple providers remain visible')
    t.findChildren(view, 'taskSummary').forEach(function (label) {
      label.font.pixelSize = 26
    })
    t.step(350, function () {
      t.check(view.scroll.contentHeight > view.scroll.height && view.height <= 260, 'large-font list scrolls within cap')
      var control = t.findChild(view, 'taskDetailsControl')
      pointer.mousePress(control)
      view.snapshot = {
        tasks: [task('replacement', 'working')]
      }
      pointer.mouseRelease(t.findChild(view, 'taskDetailsControl'))
      t.equal(view.selectedId, '', 'changed pointer release cannot adopt replacement')
      pointer.mouseClick(t.findChild(view, 'taskDetailsControl'))
      t.equal(view.selectedId, '', 'unsettled actual pointer click is refused')
      t.step(350, function () {
        pointer.mouseClick(t.findChild(view, 'taskDetailsControl'))
        t.equal(view.selectedId, 'replacement', 'settled pointer opens exact task')
        view.back()
        view.nowMs = 172805000
        view.snapshot = {
          tasks: [Object.assign(task('recent', 'finished'), {
              freshness: 'connection-lost',
              lastReceivedAt: 172800
            }), Object.assign(task('older', 'finished'), {
              freshness: 'connection-lost',
              lastReceivedAt: 5
            })]
        }
        t.step(50, function () {
          var labels = t.findChildren(view, 'taskLastReport').map(function (label) {
            return label.text
          })
          t.check(labels.indexOf('Last report 5s ago') >= 0 && labels.indexOf('Last report 2d ago') >= 0, 'real rows distinguish report ages with equal connection freshness')
          view.selectedId = 'recent'
          t.check(t.findChild(view, 'lastReportTime').text.indexOf('Received 1970-01-03 00:00:00 UTC') >= 0, 'real details display exact receipt time separately')
          t.equal(t.findChild(view, 'lastReportTime').textFormat, Text.PlainText, 'receipt time remains plaintext')
          actions = []
          view.navigate(0)
          view.navigate(0)
          t.equal(actions.length, 0, 'local result inspection never emits an owner action from the Tasks composition')
          view.snapshot = {
            tasks: []
          }
          t.check(t.findChild(view, 'taskSetupCommands').text.indexOf('aranea agents adapter install codex') >= 0, 'setup includes explicit Codex opt-in command')
          t.check(t.findChild(view, 'taskSetupCommands').text.indexOf('trust') >= 0, 'setup explains configuration is not trust or observation')
          t.done()
        })
      })
    })
  })
}
