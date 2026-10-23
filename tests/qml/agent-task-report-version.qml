// Same-second report updates must request new details and reject late reads.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents

ShellRoot {
  id: host
  // Full-detail reads requested by the production Tasks view.
  property var reads: []
  QmlTest {
    id: t
  }
  Agents.AgentTasks {
    id: view
    width: 400
    onDetailsNeeded: function (taskId) {
      host.reads.push(taskId)
    }
  }
  // Build two reports with equal receipt time and distinct content identities.
  function row(version, result) {
    return {
      taskId: 'task',
      provider: 'claude',
      reportedState: 'finished',
      lastReceivedAt: 100,
      reportVersion: version,
      result: result,
      association: {
        status: 'unassigned',
        cwd: '/checkout'
      }
    }
  }
  Component.onCompleted: t.step(60, function () {
    var old = row('first', 'Old full result')
    var current = row('second', 'New full result')
    view.snapshot = {
      tasks: [Object.assign({}, old, {
          preview: true,
          result: 'Old…'
        })]
    }
    view.selectedId = 'task'
    view.detailTask = old
    t.equal(reads.length, 1, 'opening a preview requests full details')
    view.snapshot = {
      tasks: [Object.assign({}, current, {
          preview: true,
          result: 'New…'
        })]
    }
    t.equal(reads.length, 2, 'a same-second report requests fresh details')
    t.equal(view.selectedRow.result, 'New…', 'stale cached text cannot replace current preview')
    view.detailTask = current
    t.equal(view.selectedRow.result, 'New full result', 'matching new read expands full content')
    view.detailTask = old
    t.equal(view.selectedRow.result, 'New…', 'late old response cannot restore stale content')
    t.done()
  })
}
