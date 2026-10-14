// Daily saved profile starts cross the real client; searchable short-window pickers escape clipping.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held helper callbacks expose serialization and authoritative publication.
  property var calls: []
  // Visit writes have their own acknowledged transport, separate from held role saves.
  property var navigationCalls: []
  // Real one-off owner transport requests intercepted at the IPC boundary.
  property var ipcCalls: []
  // Real owner requests exercise omitted-checkout leases at the IPC boundary.
  property var agentRequests: []
  // Count owner transport responses before and after readiness acceptance.
  property var agentResponses: []
  // Accepted failures and uncertain observations cross the actual owner/client route.
  property bool missingProvider: true
  Projects.ProjectsController {
    id: routeOwner
    captureActive: true
    runtime: ({
        sessionId: 'agent-route-session',
        snapshot: function () {
          return {
            available: true,
            currentWorkspaceId: 1,
            workspaces: [],
            windows: []
          }
        },
        validateBindings: function (bindings, done) {
          Qt.callLater(function () {
            done({
              bindings: [],
              missing: []
            })
          })
        },
        focusWorkspace: function (id, done) {
          Qt.callLater(function () {
            done({
              ok: true,
              status: 'observed'
            })
          })
        },
        launch: function (spec, done) {
          Qt.callLater(function () {
            done({
              ok: true,
              status: 'accepted',
              identity: {
                pid: 321,
                startTime: '1'
              }
            })
          })
        },
        observe: function (spec, baseline, done) {
          Qt.callLater(function () {
            done({
              status: 'unconfirmed',
              code: 'OBSERVATION_TIMEOUT'
            })
          })
        }
      })
    storeRunner: function (argv, done, input) {
      Qt.callLater(function () {
        done({
          ok: true,
          state: entry.projectController.state
        })
      })
    }
    metadataRunner: function (argv, done) {
      Qt.callLater(function () {
        done({
          ok: true,
          metadata: {
            path: argv[2],
            commonDir: '/repo/.git'
          }
        })
      })
    }
    toolsRunner: function (argv, done) {
      Qt.callLater(function () {
        done({
          defaults: {},
          editors: [],
          terminals: [
            {
              id: 'kitty',
              available: true,
              supported: true
            }
          ],
          agents: host.missingProvider ? [
            {
              id: 'claude',
              available: true,
              supported: true
            }
          ] : [
            {
              id: 'codex',
              available: true,
              supported: true
            }
          ]
        })
      })
    }
  }
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    when: false
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    visible: true
    implicitWidth: 420
    implicitHeight: 240
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Component.onCompleted: t.step(80, function () {
    entry.gitClient.captureActive = true
    entry.actionClient.captureActive = true
    entry.opened = true
    entry.activityClient.captureActive = true
    entry.discoveryClient.captureActive = true
    entry.projectClient.captureActive = true
    entry.projectController.runner = function (argv, payload, done) {
      var request = JSON.parse(payload)
      if (request.action === 'navigation-set') {
        host.navigationCalls.push(request)
        var state = Object.assign({}, entry.projectController.state, {
          revision: entry.projectController.state.revision + 1,
          navigation: {
            lastProjectId: request.args.projectId,
            pinnedProjectIds: [],
            visitedAt: {
              'p-one': Date.now()
            }
          }
        })
        done(0, JSON.stringify({
          ok: true,
          state: state
        }), '')
        return
      }
      host.calls.push({
        argv: argv,
        payload: payload,
        done: done
      })
    }
    entry.projectController.state = {
      revision: 4,
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-one',
          name: 'Repo',
          commonDir: '/repo/.git',
          associations: [],
          tools: {
            editorId: 'code',
            terminalId: 'kitty',
            agentId: 'codex'
          },
          openRoles: ['editor', 'agent'],
          lastProfileId: 'f-code',
          profiles: [
            {
              id: 'f-code',
              revision: 3,
              name: 'VS Code',
              roles: ['editor'],
              tools: {
                editorId: 'code'
              }
            },
            {
              id: 'f-term',
              revision: 2,
              name: 'Terminal',
              roles: ['terminal'],
              tools: {
                terminalId: 'kitty'
              }
            }
          ],
          lastCheckoutId: 'c-main',
          checkouts: [
            {
              id: 'c-main',
              path: '/repo',
              branch: 'main'
            }
          ]
        }
      ]
    }
    entry.projectController.tools = {
      defaults: {},
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
      ]
    }
    entry.projectClient.snapshot = {
      sessionId: 'agent-route-session',
      availability: {
        compositor: true
      },
      bindings: [],
      operations: [],
      agents: {
        tools: [
          {
            id: 'claude',
            label: 'Claude Code',
            available: true
          },
          {
            id: 'codex',
            label: 'Codex',
            available: true
          }
        ],
        usage: {}
      }
    }
    entry.projectClient.available = true
    surface.navigate('p-one')
    t.step(80, function () {
      t.equal(host.navigationCalls, [
        {
          action: 'navigation-set',
          args: {
            projectId: 'p-one',
            visit: true
          },
          expectedRevision: 4
        }
      ], 'inspection saves exact visit metadata independently of configure')
      var header = t.findChild(surface, 'projectHeader')
      var page = t.findChild(surface, 'projectsPage'), agents = t.findChild(surface, 'projectAgents')
      t.check(page.agentChoice === surface.agentChoice && page.details.agentChoice === surface.agentChoice, 'optional agent destinations retain the shared provider suggestion')
      t.check(agents.agentChoice === surface.agentChoice, 'Agents retains the shared suggestion')
      entry.projectClient.identityRunner = function (done) {
        done('00000000-0000-4000-8000-000000000041')
      }
      entry.projectClient.runner = function (argv, done) {
        host.ipcCalls.push(argv)
        done(0, JSON.stringify({
          ok: false,
          error: {
            code: 'FIXTURE',
            message: 'Inert request captured'
          }
        }), '')
      }
      entry.projectClient.captureActive = false
      t.findChild(header, 'projectPrimaryStart').activate()
      t.equal(JSON.parse(host.ipcCalls[0][3]), {
        projectId: 'p-one',
        checkoutId: 'c-main',
        profileId: 'f-code',
        profileRevision: 3,
        activationId: 'a-00000000-0000-4000-8000-000000000041'
      }, 'primary uses exact remembered profile revision and selected checkout')
      t.equal(host.calls.length, 0, 'daily starts never rewrite saved role defaults')
      var choose = t.findChild(header, 'headerChooseProfile')
      choose.forceActiveFocus()
      input.keyClick(Qt.Key_Return)
      t.step(80, function () {
        var menu = t.findChild(surface, 'profilePicker')
        t.check(menu.opened && t.findChild(menu, 'projectSearch').activeFocus, 'real profile popup opens with searchable keyboard focus')
        t.check(menu.parent === surface, 'profile picker uses unclipped surface overlay')
        t.check(menu.x >= 0 && menu.y >= 0 && menu.x + menu.width <= surface.width && menu.y + menu.height <= surface.height, 'short narrow picker fits host bounds')
        menu.query = 'Terminal'
        var list = t.findChild(menu, 'pickerList')
        t.equal(list.filteredProjects.length, 1, 'profile query filters real popup rows')
        var row = t.findChild(menu, 'selectProject:f-term')
        row.forceActiveFocus()
        input.keyClick(Qt.Key_Return)
        t.equal(JSON.parse(host.ipcCalls[1][3]).profileId, 'f-term', 'keyboard selection immediately starts exact chosen profile')
        t.check(!menu.opened, 'profile activation closes chooser')
        t.equal(entry.projectController.state.projects[0].openRoles, ['editor', 'agent'], 'chooser never changes legacy saved defaults')
        choose.forceActiveFocus()
        input.keyClick(Qt.Key_Return)
        input.keyClick(Qt.Key_Escape)
        t.check(!menu.opened, 'Escape closes chooser without a start')
        t.equal(host.ipcCalls.length, 2, 'Escape never submits a profile')
        choose.activate()
        header.visible = false
        t.check(!menu.opened, 'hiding header closes reparented profile popup')
        header.visible = true
        entry.projectClient.captureActive = true
        entry.projectClient.runner = function (argv, done) {
          var method = argv[2], response
          if (method === 'request') {
            var payload = JSON.parse(argv[3])
            host.agentRequests.push(payload)
            response = routeOwner.request(payload)
            host.agentResponses.push(response)
          } else if (method === 'operation')
            response = routeOwner.operation(argv[3])
          else if (method === 'snapshot')
            response = Object.assign({}, routeOwner.snapshot(), {
              agents: entry.projectClient.snapshot.agents
            })
          done(0, JSON.stringify(response), '')
        }
        routeOwner.registry = entry.projectController.state
        routeOwner.registryReady = true
        routeOwner.captureActive = false
        entry.projectClient.captureActive = false
        entry.projectClient.available = true
        surface.chooseSection('agents')
        var startHere = t.findChild(agents, 'startAgentHere')
        t.check(!!startHere && startHere.visible && startHere.enabled, 'actual empty Agents surface exposes available Start control')
        startHere.activate()
        t.equal(surface.section, 'overview', 'empty Agents Start routes to Overview before submission')
        t.check(entry.projectClient.preparing && page.details.pending && !startHere.enabled, 'ordinary route disables Start during rejected owner readiness')
        t.equal(host.agentResponses[0].error.code, 'OWNER_NOT_READY', 'omitted-checkout Start acquires real owner selection lease')
        t.waitFor(function () {
          return host.agentResponses.length === 2 && !entry.projectClient.pending
        }, 2000, 'agent start retries readiness and observes one accepted operation', function () {
          t.equal(host.agentRequests, [
            {
              projectId: 'p-one',
              roles: ['agent'],
              newWindowRole: 'agent',
              agentId: 'codex'
            },
            {
              projectId: 'p-one',
              roles: ['agent'],
              newWindowRole: 'agent',
              agentId: 'codex'
            }
          ], 'retry preserves exact provider-only payload without selecting checkout in UI')
          t.check(host.agentResponses[1].ok && routeOwner.operations.length === 1, 'readiness retry creates exactly one owner operation')
          var op = routeOwner.operations[0]
          t.equal([op.checkoutId, op.selectionRevision, op.agentId, op.roles, op.newWindowRole], ['c-main', 5, 'codex', ['agent'], 'agent'], 'owner resolves saved checkout through revision-bound lease and preserves agent request')
          t.check(!routeOwner.defaultSelections['p-one'], 'accepted Start consumes selection lease')
          t.equal(op.error.code, 'AGENT_MISSING', 'actual accepted start fails for missing selected provider')
          var explanation = t.findChild(page.details, 'projectOperationError'), alternative = t.findChild(page.details, 'startAlternativeAgent')
          t.check(page.details.visible && explanation.visible && explanation.text.indexOf('Codex') >= 0 && explanation.text.indexOf('installed') >= 0, 'accepted start failure explanation is visible in real surface')
          t.check(alternative.visible && alternative.enabled && alternative.text === 'Start Claude', 'failed Start exposes installed alternative recovery')
          host.missingProvider = false
          surface.chooseSection('agents')
          t.check(startHere.visible && startHere.enabled, 'empty Agents offers another explicit Start after settled failure')
          startHere.activate()
          t.waitFor(function () {
            return host.agentResponses.length >= 3 && !entry.projectClient.pending
          }, 2000, 'second surface start observes accepted unconfirmed outcome', function () {
            t.equal(routeOwner.operations.length, 2, 'readiness retries accept exactly one operation per explicit Start')
            var uncertain = routeOwner.operations[1], message = t.findChild(page.details, 'agentUnconfirmed'), checkAgain = t.findChild(page.details, 'reobserveRole:agent')
            t.equal(uncertain.outcome, 'partial', 'real owner retains unconfirmed accepted launch')
            t.check(surface.section === 'overview' && page.details.visible && message.visible && message.text === "Couldn't confirm the agent window opened.", 'unconfirmed Start explanation is visible in real surface')
            t.check(checkAgain.visible && checkAgain.enabled, 'unconfirmed Start exposes applicable Check agent again recovery')
            routeOwner.captureActive = true
            entry.projectClient.captureActive = true
            t.done()
          })
        })
      })
    })
  })
}
