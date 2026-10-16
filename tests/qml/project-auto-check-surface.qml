// Registry refreshes keep automatic checks running, and the start block alone owns start errors.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects/ProjectProblems.js" as Problems

ShellRoot {
  id: host
  // Held owner calls of the shared project client.
  property var calls: []
  // Open requests emitted by the standalone details view.
  property var opens: []
  // Activation id shared by the start scenarios.
  readonly property string activation: 'a-00000000-0000-4000-8000-000000000001'
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    visible: true
    width: 900
    height: 700
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  // Project record with one editor profile.
  function project(id) {
    return {
      id: id,
      name: id,
      tools: {},
      profiles: [
        {
          id: 'f-a',
          name: 'VS Code',
          roles: ['editor'],
          tools: {
            editorId: 'code',
            terminalId: null,
            agentId: null
          },
          revision: 1
        }
      ],
      lastProfileId: 'f-a',
      lastCheckoutId: 'c-' + id,
      checkouts: [
        {
          id: 'c-' + id,
          path: '/fixture/' + id
        }
      ]
    }
  }
  // Publish a registry state (fresh project objects) and select one project.
  function show(ids, id, revision) {
    entry.projectController.state = {
      revision: revision,
      projects: ids.map(function (one) {
        return host.project(one)
      }),
      roots: [],
      ignored: []
    }
    entry.projectId = id
  }
  // Number of owner lookups made so far.
  function lookups() {
    return host.calls.filter(function (c) {
      return c.method === 'environmentActivation'
    })
  }
  Component.onCompleted: t.step(80, function () {
    entry.projectClient.runner = function (argv, done) {
      host.calls.push({
        method: argv[2],
        done: done
      })
    }
    entry.projectClient.autoCheckDelays = [100, 200, 300]
    entry.projectController.runner = function (argv, input, done) {
      if (argv[1] === 'snapshot')
        Qt.callLater(function () {
          done(0, JSON.stringify({
            ok: true,
            state: entry.projectController.state
          }), '')
        })
    }
    entry.gitClient.runner = function () {}
    entry.actionClient.runner = function () {}
    entry.projectClient.available = true
    entry.projectClient.snapshot = {
      availability: {
        compositor: true
      }
    }
    entry.opened = true
    entry.view = surface
    host.show(['p-one', 'p-two'], 'p-one', 1)
    t.step(150, startCase)
  })
  // A start whose acknowledgement is lost starts the automatic lookups.
  function startCase() {
    entry.projectClient.startEnvironment({
      projectId: 'p-one',
      checkoutId: 'c-p-one',
      profileId: 'f-a',
      profileRevision: 1,
      activationId: host.activation
    })
    host.calls[0].done(1, '', 'acknowledgement lost')
    t.check(entry.projectClient.autoChecking, 'automatic checks are running')
    // The registry is read back: new objects for the same project.
    host.show(['p-one', 'p-two'], 'p-one', 2)
    t.step(50, function () {
      host.show(['p-one', 'p-two'], 'p-one', 3)
      t.check(entry.projectClient.autoChecking, 'a registry refresh keeps the automatic checks')
      t.waitFor(function () {
        return host.lookups().length >= 1
      }, 2000, 'the first lookup still runs after the refresh', errorCase)
    })
  }
  // Start uncertainty shows one problem: the start block, not a page banner.
  function errorCase() {
    entry.projectClient.error = 'Project launch acknowledgement is unknown.'
    t.step(100, function () {
      var page = t.findChild(surface, 'projectsPage')
      var pageProblem = t.findChild(page, 'projectsPageProblem')
      t.check(!pageProblem.visible, 'no page problem while a start is uncertain')
      t.check(!t.findChild(page, 'projectsPageNote').visible, 'no page note while a start is uncertain')
      entry.projectClient.error = ''
      switchCase()
    })
  }
  // Switching to another project ends the checks.
  function switchCase() {
    host.show(['p-one', 'p-two'], 'p-two', 4)
    t.step(50, function () {
      t.check(!entry.projectClient.autoChecking, 'a different project ends the automatic checks')
      t.done()
    })
  }
}
