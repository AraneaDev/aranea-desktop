// A project or checkout switch reads the new selection's actions at once, not on the next poll.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held shared-client transport calls.
  property var calls: []
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: root
    windowEnabled: false
    captureActive: true
  }
  Projects.ProjectsSurface {
    id: surface
    root: root
    width: 1080
    height: 720
  }
  // Registry state with project q on the given checkout.
  function registry(qCheckout) {
    return {
      projects: [
        {
          id: 'p',
          name: 'Repo',
          lastCheckoutId: 'c',
          checkouts: [
            {
              id: 'c',
              path: '/repo',
              branch: 'main'
            }
          ]
        },
        {
          id: 'q',
          name: 'Other',
          lastCheckoutId: qCheckout,
          checkouts: [
            {
              id: 'd',
              path: '/other',
              branch: 'main'
            },
            {
              id: 'e',
              path: '/other-task',
              branch: 'task'
            }
          ]
        }
      ],
      roots: [],
      ignored: []
    }
  }
  // Snapshot reads issued for a project since the last reset.
  function snapshots(projectId) {
    return host.calls.filter(function (c) {
      return c.method === 'snapshot' && c.payload.projectId === projectId
    })
  }
  Component.onCompleted: t.step(80, function () {
    root.view = surface
    root.gitClient.runner = function () {}
    root.reviewClient.runner = function () {}
    root.projectClient.runner = function () {}
    root.projectController.runner = function () {}
    root.actionClient.runner = function (argv, input, done) {
      host.calls.push({
        method: argv[argv.length - 1],
        payload: JSON.parse(input || '{}'),
        done: done
      })
    }
    root.projectController.state = registry('d')
    root.projectId = 'p'
    root.opened = true
    root.captureActive = false
    t.step(30, function () {
      t.check(root.actionClient.observationActive, 'the visible Overview observes actions')
      t.check(snapshots('p').length >= 1, 'opening reads the selected project')
      host.calls = []
      root.projectId = 'q'
      t.step(30, function () {
        t.equal(snapshots('q').length, 1, 'a project switch reads the new project once, before the poll')
        t.equal(snapshots('p').length, 0, 'nothing reads the previous project')
        host.calls = []
        root.projectController.state = registry('e')
        t.step(30, function () {
          t.equal(root.actionClient.checkoutId, 'e', 'the checkout switch settled')
          t.equal(snapshots('q').length, 1, 'a checkout switch reads again once')
          host.calls = []
          root.opened = false
          root.projectId = 'p'
          t.step(30, function () {
            t.equal(snapshots('p').length, 0, 'a closed window does not read on a switch')
            t.done()
          })
        })
      })
    })
  })
}
