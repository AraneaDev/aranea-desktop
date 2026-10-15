// Actual store registration and profile mutations drive the rendered first-use header.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Only native owner transport is held; registry operations remain real.
  property var calls: []
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
  // Exercise enabled, visible identity and exact submission without accepting native work.
  function primary(expectedName, checkoutId) {
    host.calls = []
    var header = t.findChild(surface, 'projectHeader')
    var button = t.findChild(header, 'projectPrimaryStart')
    var summary = t.findChild(header, 'projectProfileSummary')
    t.check(header.visible && button.enabled, 'first saved usable profile enables visible primary')
    t.check(summary.text.indexOf(expectedName + ' · ') === 0 && summary.text.indexOf('Choose') < 0, 'primary exposes selected profile name and actual tools')
    var profile = entry.selectedProject.profiles[0]
    t.equal(entry.selectedProject.lastProfileId, null, 'local initial choice never invents remembered acceptance')
    button.clicked()
    t.check(calls.length > 0, 'primary click submits usable initial profile')
    if (calls.length) {
      var target = JSON.parse(calls[calls.length - 1].args[0])
      t.equal([target.projectId, target.checkoutId, target.profileId, target.profileRevision], [entry.projectId, checkoutId, profile.id, profile.revision], 'primary sends exact current checkout and saved profile revision')
    }
    entry.projectClient.captureActive = true
    entry.projectClient.captureActive = false
    entry.clearDismissalIntent()
  }
  // Wait for queued visit and preset writes to finish through the real store.
  function settled(done) {
    t.waitFor(function () {
      return !entry.projectController.pending && !entry.navigationQueue.length
    }, 5000, 'real registry mutations settle', done)
  }
  Component.onCompleted: t.step(60, function () {
    entry.gitClient.captureActive = true
    entry.actionClient.captureActive = true
    entry.activityClient.captureActive = true
    entry.projectClient.runner = function (argv, done) {
      host.calls.push({
        method: argv[2],
        args: argv.slice(3),
        done: done
      })
    }
    entry.projectClient.identityRunner = function (done) {
      done('00000000-0000-4000-8000-000000000011')
    }
    entry.projectClient.available = true
    entry.projectClient.snapshot = {
      availability: {
        compositor: true
      }
    }
    entry.opened = true
    entry.view = surface
    entry.projectController.refresh()
    t.waitFor(function () {
      return !entry.projectController.reading
    }, 3000, 'actual supported probe ready', function () {
      var page = t.findChild(surface, 'projectsPage')
      page.startSetup()
      var picker = t.findChild(page, 'projectExactPicker')
      picker.setPath(Quickshell.env('ARANEA_FIRST_USE_PATH'))
      picker.confirm()
      t.waitFor(function () {
        return !!entry.selectedProject && entry.selectedProject.profiles.length > 0
      }, 5000, 'registration persists usable presets', function () {
        settled(function () {
          t.check(!page.setupActive && surface.section === 'overview', 'actual registration reaches Overview')
          primary('VS Code', entry.selectedProject.lastCheckoutId)
          // Add and select a second actual checkout before another primary activation.
          entry.projectController.request('register', {
            paths: [Quickshell.env('ARANEA_FIRST_USE_SIBLING')]
          })
          settled(function () {
            // Both worktrees belong to this project: explicitly choose the sibling checkout.
            var sibling = entry.selectedProject.checkouts.find(function (c) {
              return c.path === Quickshell.env('ARANEA_FIRST_USE_SIBLING')
            })
            entry.projectController.request('select-checkout', {
              projectId: entry.projectId,
              checkoutId: sibling.id
            })
            settled(function () {
              primary('VS Code', sibling.id)
              entry.projectController.request('register', {
                paths: [Quickshell.env('ARANEA_FIRST_USE_MANUAL')]
              })
              settled(saveManual)
            })
          })
        })
      })
    })
  })
  // Direct registration has no setup intent but seeds detected presets; one more is saved explicitly.
  function saveManual() {
    t.check(entry.selectedProject.profiles.length > 0, 'direct registration seeds detected presets')
    entry.projectController.request('profile-save', {
      projectId: entry.projectId,
      profile: {
        name: 'Manual Terminal',
        roles: ['terminal'],
        tools: {
          editorId: null,
          terminalId: 'kitty',
          agentId: null
        }
      }
    })
    settled(function () {
      t.check(entry.selectedProject.profiles.some(function (p) {
        return p.name === 'Manual Terminal'
      }), 'manually saved profile exists beside the seeded presets')
      // The first saved profile (the seeded VS Code preset) stays the initial default.
      t.equal(entry.selectedProject.profiles[0].name, 'VS Code', 'first seeded preset is VS Code')
      primary('VS Code', entry.selectedProject.lastCheckoutId)
      var original = entry.projectController.state, tools = entry.projectController.tools
      var state = JSON.parse(JSON.stringify(original))
      var selected = state.projects.find(function (p) {
        return p.id === entry.projectId
      })
      selected.lastProfileId = 'stale-profile'
      entry.projectController.state = state
      var header = t.findChild(surface, 'projectHeader'), button = t.findChild(header, 'projectPrimaryStart')
      t.equal(header.profile.id, selected.profiles[0].id, 'stale remembered ID falls back to the first usable saved profile')
      t.check(button.enabled && selected.lastProfileId === 'stale-profile', 'fallback starts without rewriting the remembered ID')
      state = JSON.parse(JSON.stringify(original))
      selected = state.projects.find(function (p) {
        return p.id === entry.projectId
      })
      selected.lastProfileId = selected.profiles[0].id
      entry.projectController.state = state
      entry.projectController.tools = {
        editors: [],
        terminals: [],
        agents: [],
        defaults: {}
      }
      t.check(!header.profile && !button.enabled, 'no usable profile without tools')
      t.check(header.profileSummary.indexOf('Choose') >= 0, 'unavailable profiles expose recovery')
      t.check(header.blockedReason !== '', 'blocked start is explained')
      entry.projectController.state = original
      t.check(!header.profile && !button.enabled, 'zero supported tools cannot supply a usable initial default')
      t.check(t.findChild(header, 'headerManageProfiles').visible, 'zero tools retain direct profile setup recovery')
      entry.projectController.tools = tools
      t.done()
    })
  }
}
