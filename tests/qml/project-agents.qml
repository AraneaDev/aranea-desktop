// Standalone project activity protects accepted launches and exact checkout association.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: host
  // Count only actual activity request transport submissions.
  property int requests: 0
  // Simulate loss of the first observation after a real acceptance.
  property bool failRead: true
  // Only matching owner identity may resolve retained uncertainty.
  property string observedOwner: 'different-owner'
  QmlTest {
    id: t
  }
  Activity.ActivityClient {
    id: observer
    captureActive: true
    runner: function (argv, done) {
      if (argv[2] === 'request') {
        host.requests++
        done(0, JSON.stringify({
          ok: true,
          operationId: 'op-accepted',
          ownerId: 'accepted-owner'
        }), '')
      } else if (argv[2] === 'operation') {
        if (host.failRead)
          done(1, '', 'lost')
        else
          done(0, JSON.stringify({
            id: 'op-accepted',
            ownerId: host.observedOwner,
            taskId: 'task-one',
            action: 'reopen',
            state: 'completed',
            outcome: 'observed'
          }), '')
      } else if (argv[2] === 'snapshot')
        done(0, JSON.stringify(observer.snapshot), '')
    }
  }
  FloatingWindow {
    implicitWidth: 420
    implicitHeight: 680
    visible: true
    Projects.ProjectAgents {
      id: view
      anchors.fill: parent
      client: observer
      project: ({
          id: 'p-one',
          name: 'One',
          checkouts: [
            {
              id: 'c-one',
              path: '/repo'
            }
          ]
        })
      registry: ({
          projects: [view.project]
        })
    }
  }
  Component.onCompleted: t.step(80, function () {
    var task = {
      taskId: 'task-one',
      provider: 'claude',
      source: 'native',
      nativeSessionEligible: true,
      reportedState: 'working',
      displayState: 'connection-lost',
      freshness: 'connection-lost',
      resumeCommand: 'display only',
      association: {
        status: 'registered',
        projectId: 'p-one',
        checkoutId: 'c-one',
        cwd: '/repo'
      }
    }
    observer.snapshot = {
      tasks: [task, Object.assign({}, task, {
          taskId: 'other-project',
          association: {
            status: 'registered',
            projectId: 'p-two',
            checkoutId: 'c-one',
            cwd: '/repo'
          }
        }), Object.assign({}, task, {
          taskId: 'wrong-path',
          association: {
            status: 'registered',
            projectId: 'p-one',
            checkoutId: 'c-one',
            cwd: '/other'
          }
        })],
      operations: []
    }
    t.equal(view.projectTasks.map(function (v) {
      return v.taskId
    }), ['task-one'], 'Agents contains only the exact registered project and checkout path')
    var tasks = t.findChildren(view, '').filter(function (item) {
      return typeof item.openDetails === 'function'
    })[0]
    t.check(!!tasks, 'real task presentation is composed')
    observer.captureActive = false
    view.submit('reopen', 'task-one')
    t.equal(requests, 1, 'explicit reopen submits once')
    t.equal(observer.currentOperation, null, 'accepted operation may be lost before first read')
    observer.refresh()
    view.submit('reopen', 'task-one')
    t.equal(requests, 1, 'snapshot refresh cannot clear accepted launch uncertainty')
    tasks.selectedId = 'task-one'
    t.check(tasks.selectedOperation && tasks.selectedOperation.ownerUnconfirmed, 'exact accepted owner and operation remain protected')
    failRead = false
    observer.reconnect()
    t.check(tasks.selectedOperation.ownerUnconfirmed, 'different owner cannot resolve the acceptance')
    observedOwner = 'accepted-owner'
    observer.reconnect()
    t.check(!tasks.selectedOperation.ownerUnconfirmed, 'same-owner observation resolves uncertainty')
    tasks.navigate(0)
    var saved = view.captureSnapshot()
    t.check(saved.tasks && saved.tasks.detail, 'capture includes nested task detail presentation')
    t.check(typeof view.handleKey === 'function', 'standalone activity supplies keyboard navigation')
    var event = {
      key: Qt.Key_Escape,
      accepted: false
    }
    view.handleKey(event)
    t.check(event.accepted && !tasks.selectedId, 'Escape returns from details before closing Projects')
    observer.captureActive = true
    view.captureRestore({})
    view.captureRestore(saved)
    t.step(80, function () {
      var restored = view.captureSnapshot()
      t.equal(restored.tasks.detail, saved.tasks.detail, 'capture restores nested detail cursor and scroll exactly')
      t.equal(restored.tasks.selectedId, saved.tasks.selectedId, 'capture restores exact task selection')
      t.done()
    })
  })
}
