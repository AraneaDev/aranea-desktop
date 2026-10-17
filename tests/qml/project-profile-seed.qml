// Opening a project without profiles asks the backend once; blocked starts explain themselves.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held registry transport records each request payload.
  property var requests: []
  // Callbacks answer held requests with controlled store replies.
  property var callbacks: []
  // Profile starts emitted by the header.
  property var starts: []
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
  // Probe with only VS Code available.
  readonly property var codeOnly: ({
      defaults: {},
      editors: [
        {
          id: 'code',
          label: 'VS Code',
          available: true,
          supported: true
        }
      ],
      terminals: [],
      agents: []
    })
  // Tool probe the next Refresh returns.
  property var probe: codeOnly
  // Probe with nothing installed.
  readonly property var emptyTools: ({
      defaults: {},
      editors: [],
      terminals: [],
      agents: []
    })
  // Build one project record for the held registry state.
  function project(id, profiles, lastProfileId) {
    return {
      id: id,
      name: id,
      tools: {},
      profiles: profiles,
      lastProfileId: lastProfileId || null,
      lastCheckoutId: 'c-' + id,
      checkouts: [
        {
          id: 'c-' + id,
          path: '/fixture/' + id
        }
      ]
    }
  }
  // Saved editor profile for the fallback cases.
  function editor(id, name, editorId) {
    return {
      id: id,
      name: name,
      roles: ['editor'],
      tools: {
        editorId: editorId,
        terminalId: null,
        agentId: null
      },
      revision: 1
    }
  }
  // Publish a registry state and select one project.
  function show(projects, id, revision) {
    entry.projectController.state = {
      revision: revision,
      projects: projects,
      roots: [],
      ignored: []
    }
    entry.projectId = id
  }
  // Requests of one action, in order.
  function only(action) {
    return host.requests.filter(function (r) {
      return r.action === action
    })
  }
  Component.onCompleted: t.step(80, function () {
    entry.projectController.runner = function (argv, input, done) {
      // Refresh reads: registry snapshot and tool probe answer immediately.
      if (argv[1] === 'snapshot') {
        Qt.callLater(function () {
          done(0, JSON.stringify({
            ok: true,
            state: entry.projectController.state
          }), '')
        })
        return
      }
      if (argv[1] === '--json') {
        Qt.callLater(function () {
          done(0, JSON.stringify(host.probe), '')
        })
        return
      }
      var request = JSON.parse(input)
      host.requests.push(request)
      // Visit metadata is acknowledged at once; only seeds are held.
      if (request.action === 'navigation-set')
        Qt.callLater(function () {
          done(0, JSON.stringify({
            ok: true,
            state: entry.projectController.state
          }), '')
        })
      else
        host.callbacks.push(done)
    }
    entry.projectClient.runner = function () {}
    entry.gitClient.runner = function () {}
    entry.actionClient.runner = function () {}
    entry.projectClient.available = true
    entry.projectClient.snapshot = {
      availability: {
        compositor: true
      }
    }
    entry.projectController.tools = host.codeOnly
    entry.view = surface
    var header = t.findChild(surface, 'projectHeader')
    var start = t.findChild(header, 'projectPrimaryStart')
    header.startProfile.connect(function (id, revision) {
      host.starts.push([id, revision])
    })
    // Capture inert: no seed request while captured.
    entry.captureActive = true
    host.show([host.project('p-empty', [])], 'p-empty', 1)
    t.step(60, function () {
      t.equal(host.only('profiles-seed').length, 0, 'capture never seeds')
      entry.captureActive = false
      // Seed once: leaving capture and publishing state seeds the project.
      host.show([host.project('p-empty', [])], 'p-empty', 2)
      t.waitFor(function () {
        return host.only('profiles-seed').length === 1
      }, 3000, 'one seed request', function () {
        t.equal(host.only('profiles-seed')[0].args, {
          projectId: 'p-empty'
        }, 'seed carries only the project id')
        var summary = t.findChild(header, 'projectProfileSummary')
        t.check(summary.text.indexOf('Preparing a default profile') >= 0, 'header reports seeding')
        t.check(!start.enabled, 'Start working is disabled while seeding')
        host.callbacks.shift()(0, JSON.stringify({
          ok: true,
          state: {
            revision: 3,
            projects: [host.project('p-empty', [])],
            roots: [],
            ignored: []
          }
        }), '')
        t.step(80, function () {
          t.equal(host.only('profiles-seed').length, 1, 'a seeded project is not requested again')
          t.equal(t.findChild(header, 'projectBlockedReason').text, 'No default profile could be made. Add a profile to start.', 'a seed that made nothing says why')
          t.check(!t.findChild(header, 'projectRefreshTools').visible, 'no Refresh for a seed that made nothing')
          failure()
        })
      })
    })
  })
  // A failed seed offers one explicit retry.
  function failure() {
    host.show([host.project('p-fail', [])], 'p-fail', 4)
    t.waitFor(function () {
      return host.only('profiles-seed').length === 2
    }, 3000, 'second project seeds', function () {
      host.callbacks.shift()(1, JSON.stringify({
        ok: false,
        error: {
          code: 'INTERNAL',
          message: 'seed boom'
        }
      }), '')
      var header = t.findChild(surface, 'projectHeader')
      t.waitFor(function () {
        return t.findChild(header, 'projectRetrySeed').visible
      }, 3000, 'retry offered', function () {
        t.check(!t.findChild(header, 'projectPrimaryStart').enabled, 'Start stays disabled after a failed seed')
        t.equal(t.findChild(header, 'projectSeedError').text, "Couldn't prepare a default profile.", 'a failed seed says so plainly')
        t.equal(t.findChild(header, 'projectRetrySeed').text, 'Retry', 'a failed seed offers Retry')
        t.findChild(header, 'projectRetrySeed').clicked()
        t.waitFor(function () {
          return host.only('profiles-seed').length === 3
        }, 3000, 'retry sends one more request', function () {
          // A probe that could not run is not the same as "no tools installed".
          host.callbacks.shift()(1, JSON.stringify({
            ok: false,
            error: {
              code: 'PROBE_FAILED',
              message: 'Could not check which tools are installed.',
              recovery: 'Check again.'
            }
          }), '')
          t.waitFor(function () {
            return t.findChild(header, 'projectRetrySeed').visible
          }, 3000, 'retry offered again', function () {
            t.equal(t.findChild(header, 'projectSeedError').text, 'Could not check which tools are installed.', 'a failed probe says so plainly')
            t.equal(t.findChild(header, 'projectRetrySeed').text, 'Check again', 'a failed probe offers Check again')
            t.equal(t.findChild(header, 'projectBlockedReason').text, '', 'no install hint after a failed probe')
            var problem = t.findChild(surface, 'projectsPageProblem')
            t.check(!!problem && problem.problem && problem.problem.body === 'Could not check which tools are installed.', 'the page problem keeps the plain message')
            fallback()
          })
        })
      })
    })
  }
  // A usable saved profile replaces an unusable remembered one with a note.
  function fallback() {
    var header = t.findChild(surface, 'projectHeader')
    var start = t.findChild(header, 'projectPrimaryStart')
    host.show([host.project('p-fb', [host.editor('f-a', 'Neovim', 'nvim'), host.editor('f-b', 'VS Code', 'code')], 'f-a')], 'p-fb', 5)
    t.waitFor(function () {
      return start.enabled
    }, 3000, 'fallback profile starts', function () {
      t.equal(t.findChild(header, 'projectFallbackNote').text, "Neovim isn't available, using VS Code.", 'fallback is explained')
      start.clicked()
      t.equal(host.starts, [['f-b', 1]], 'Start uses the fallback profile')
      host.starts = []
      noTools()
    })
  }
  // With nothing installed Start is blocked and Refresh is offered.
  function noTools() {
    var header = t.findChild(surface, 'projectHeader')
    entry.projectController.tools = host.emptyTools
    t.waitFor(function () {
      return !t.findChild(header, 'projectPrimaryStart').enabled
    }, 3000, 'Start disabled without tools', function () {
      t.check(t.findChild(header, 'projectBlockedReason').text.indexOf('Install a supported editor or terminal') >= 0, 'blocked reason asks for tools')
      t.check(t.findChild(header, 'projectRefreshTools').visible, 'Refresh is offered')
      unusable()
    })
  }
  // Profiles that cannot start explain themselves and cannot be chosen.
  function unusable() {
    var header = t.findChild(surface, 'projectHeader')
    entry.projectController.tools = host.codeOnly
    host.show([host.project('p-un', [host.editor('f-a', 'Neovim', 'nvim')], 'f-a')], 'p-un', 6)
    t.waitFor(function () {
      return t.findChild(header, 'projectBlockedReason').visible
    }, 3000, 'blocked reason shown', function () {
      t.check(!t.findChild(header, 'projectPrimaryStart').enabled, 'Start disabled for unusable profiles')
      t.equal(t.findChild(header, 'projectBlockedReason').text.indexOf("None of this project's profiles can start:"), 0, 'reason names the problem')
      t.check(t.findChild(header, 'headerManageProfiles').visible, 'management stays reachable')
      header.chooseProfile('f-a')
      t.equal(host.starts.length, 0, 'unusable profile cannot be chosen')
      t.equal(t.findChild(header, 'projectBlockedReason').text.length > 0 && t.findChild(header, 'headerManageProfiles').text, 'Set up a profile', 'no usable profile offers setup')
      t.equal(t.findChild(header, 'profilePicker').rows[0].path.indexOf('Not available · '), 0, 'picker rows mark unusable profiles')
      queuedNavigation()
    })
  }
  // A navigation queued during a seed cannot hide the seed outcome; errors are per project.
  function queuedNavigation() {
    var header = t.findChild(surface, 'projectHeader')
    var before = host.only('profiles-seed').length
    host.show([host.project('p-nav', []), host.project('p-other', [host.editor('f-o', 'VS Code', 'code')])], 'p-nav', 7)
    t.waitFor(function () {
      return host.only('profiles-seed').length === before + 1 && surface.seedingProjectId === 'p-nav'
    }, 3000, 'nav project seeds', function () {
      host.show([host.project('p-nav', []), host.project('p-other', [host.editor('f-o', 'VS Code', 'code')])], 'p-nav', 7)
      entry.projectId = 'p-other'
      entry.projectId = 'p-nav'
      t.step(60, function () {
        t.equal(host.only('profiles-seed').length, before + 1, 're-selecting during a seed sends no duplicate')
        entry.projectId = 'p-other'
        host.callbacks.shift()(1, JSON.stringify({
          ok: false,
          error: {
            code: 'INTERNAL',
            message: 'nav boom'
          }
        }), '')
        t.waitFor(function () {
          return surface.seedingProjectId === '' && !!surface.seedFailures['p-nav']
        }, 3000, 'seed outcome survives queued navigation', function () {
          t.check(!t.findChild(header, 'projectRetrySeed').visible, 'another project shows no Retry')
          entry.projectId = 'p-nav'
          t.waitFor(function () {
            return t.findChild(header, 'projectRetrySeed').visible
          }, 3000, 'failed project keeps its Retry', refreshReseeds)
        })
      })
    })
  }
  // A seed that made a profile the user later removed gives no "could not be made" reason.
  function removedAfterSeed() {
    var header = t.findChild(surface, 'projectHeader')
    entry.projectController.tools = host.codeOnly
    host.show([host.project('p-rm', [])], 'p-rm', 11)
    t.waitFor(function () {
      return surface.seedingProjectId === 'p-rm'
    }, 3000, 'removal project seeds', function () {
      host.callbacks.shift()(0, JSON.stringify({
        ok: true,
        state: {
          revision: 12,
          projects: [host.project('p-rm', [host.editor('f-rm', 'VS Code', 'code')])],
          roots: [],
          ignored: []
        }
      }), '')
      t.waitFor(function () {
        return surface.seedingProjectId === '' && !!projectsPageProject('p-rm') && (projectsPageProject('p-rm').profiles || []).length === 1
      }, 3000, 'seed made a profile', function () {
        // The user removes every profile afterwards.
        host.show([host.project('p-rm', [])], 'p-rm', 13)
        t.step(60, function () {
          t.equal(t.findChild(header, 'projectBlockedReason').text, '', 'no "could not be made" reason after removing a seeded profile')
          t.done()
        })
      })
    })
  }
  // The registry's current record of one project.
  function projectsPageProject(id) {
    return (entry.projectController.state.projects || []).find(function (p) {
      return p.id === id
    })
  }
  // Refresh in the no-tools state seeds again once tools appear.
  function refreshReseeds() {
    var header = t.findChild(surface, 'projectHeader')
    entry.projectController.tools = host.emptyTools
    host.show([host.project('p-nt', [])], 'p-nt', 8)
    t.waitFor(function () {
      return surface.seedingProjectId === 'p-nt'
    }, 3000, 'no-tools project seeds', function () {
      var before = host.only('profiles-seed').length
      host.callbacks.shift()(0, JSON.stringify({
        ok: true,
        state: {
          revision: 9,
          projects: [host.project('p-nt', [])],
          roots: [],
          ignored: []
        }
      }), '')
      t.waitFor(function () {
        return t.findChild(header, 'projectRefreshTools').visible && surface.seedingProjectId === ''
      }, 3000, 'no-tools hint shown', function () {
        host.probe = host.codeOnly
        t.findChild(header, 'projectRefreshTools').clicked()
        t.waitFor(function () {
          return host.only('profiles-seed').length === before + 1
        }, 3000, 'Refresh seeds again', function () {
          host.callbacks.shift()(0, JSON.stringify({
            ok: true,
            state: {
              revision: 10,
              projects: [host.project('p-nt', [host.editor('f-nt', 'VS Code', 'code')])],
              roots: [],
              ignored: []
            }
          }), '')
          removedAfterSeed()
        })
      })
    })
  }
}
