// Registration reaches Overview without the UI writing preset profiles.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held real-client transport observes each registry action and its revision.
  property var requests: []
  // Callbacks return controlled authoritative registry observations.
  property var callbacks: []
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
  Component.onCompleted: t.step(80, function () {
    entry.projectController.runner = function (argv, input, done) {
      host.requests.push(JSON.parse(input))
      host.callbacks.push(done)
    }
    entry.projectClient.runner = function () {}
    entry.gitClient.runner = function () {}
    entry.actionClient.runner = function () {}
    entry.projectController.state = {
      revision: 1,
      projects: [],
      roots: [],
      ignored: []
    }
    entry.projectController.tools = {
      defaults: {
        terminalId: 'kitty'
      },
      editors: [
        {
          id: 'code',
          label: 'VS Code',
          available: true,
          supported: true
        }
      ],
      terminals: [
        {
          id: 'kitty',
          label: 'Kitty',
          available: true,
          supported: true
        }
      ],
      agents: [
        {
          id: 'codex',
          label: 'Codex',
          available: true,
          supported: true
        }
      ]
    }
    entry.view = surface
    var page = t.findChild(surface, 'projectsPage')
    page.startSetup()
    var picker = t.findChild(page, 'projectExactPicker')
    picker.setPath('/fixture/one')
    picker.confirm()
    var project = {
      id: 'p-one',
      name: 'One',
      tools: {},
      profiles: [],
      lastCheckoutId: 'c-one',
      checkouts: [
        {
          id: 'c-one',
          path: '/fixture/one'
        }
      ]
    }
    var registered = {
      revision: 2,
      projects: [project],
      roots: [],
      ignored: []
    }
    callbacks.shift()(0, JSON.stringify({
      ok: true,
      state: registered
    }), '')
    t.check(!page.setupActive && surface.section === 'overview', 'exact registration reaches Overview before any optional transport')
    t.step(60, function () {
      t.equal(requests.map(function (r) {
        return r.action
      }).filter(function (a) {
        return a === 'profile-save'
      }), [], 'registration never saves presets from the UI; the store seeds them')
      t.check(!!entry.selectedProject, 'registered project stays selected')
      t.done()
    })
  })
}
