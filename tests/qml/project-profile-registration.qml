// Explicit registration presets serialize with visit metadata and retain partial success.
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
    t.check(!page.setupActive && surface.section === 'overview', 'exact registration reaches Overview before optional preset transport')
    t.step(30, function () {
      t.equal(requests.map(function (r) {
        return r.action
      }), ['register', 'navigation-set'], 'project visit metadata serializes ahead of optional presets')
      callbacks.shift()(0, JSON.stringify({
        ok: true,
        state: Object.assign({}, registered, {
          revision: 3
        })
      }), '')
      t.step(30, function () {
        t.equal(requests[2].action, 'profile-save', 'first preset waits for visit acknowledgement')
        t.equal(requests[2].expectedRevision, 3, 'preset uses latest metadata registry revision')
        t.equal(requests[2].args.profile.name, 'VS Code', 'first usable preset is editor-only')
        var saved = Object.assign({}, requests[2].args.profile, {
          id: 'f-code',
          revision: 1
        })
        var partial = Object.assign({}, registered, {
          revision: 4,
          projects: [Object.assign({}, project, {
              profiles: [saved]
            })]
        })
        callbacks.shift()(0, JSON.stringify({
          ok: true,
          state: partial
        }), '')
        t.step(30, function () {
          t.equal(requests[3].args.profile.name, 'Terminal + Agent', 'additional explicit preset follows first acknowledgement')
          t.equal(requests[3].expectedRevision, 4, 'each preset uses latest successful revision')
          callbacks.shift()(0, 'truncated receipt', '')
          t.step(30, function () {
            t.equal(page.selectedProject.profiles.length, 1, 'unknown later acceptance preserves earlier usable saved preset')
            t.equal(page.selectedProject.profiles[0].id, 'f-code', 'partial failure does not rewrite saved profile identity')
            t.equal(page.profilePresetQueue.length, 0, 'unknown acceptance clears automatic replay queue')
            t.check(!!page.profileSetupError && !entry.projectController.pending, 'partial failure offers direct optional recovery')
            entry.projectController.state = Object.assign({}, partial)
            page.startSetup()
            page.setupRegistrationPaths = ['/fixture/one']
            page.registryMutationCompleted('register', {
              paths: ['/fixture/one']
            }, entry.projectController.state)
            t.step(30, function () {
              t.equal(requests.length, 4, 'refresh and re-registering existing saved profiles do not duplicate presets')
              t.done()
            })
          })
        })
      })
    })
  })
}
