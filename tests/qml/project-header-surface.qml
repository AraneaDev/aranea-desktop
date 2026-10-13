// Header role saves cross the real registry client; short-window menus escape clipping.
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
      t.check(header.agentChoice === surface.agentChoice, 'surface supplies its shared suggestion to header')
      var page = t.findChild(surface, 'projectsPage'), agents = t.findChild(surface, 'projectAgents')
      t.check(page.agentChoice === surface.agentChoice && page.details.agentChoice === surface.agentChoice, 'surface and page pass one shared choice to Details')
      t.check(!!agents && agents.agentChoice === surface.agentChoice, 'surface passes same choice to Agents')
      header.choose('role:terminal')
      t.equal(host.calls.length, 1, 'default toggle dispatches exactly one configure helper')
      t.equal(JSON.parse(host.calls[0].payload), {
        action: 'configure',
        args: {
          projectId: 'p-one',
          openRoles: ['editor', 'terminal', 'agent']
        },
        expectedRevision: 5
      }, 'autosave encodes canonical roles through real registry transport')
      t.check(entry.projectController.pending && header.pending, 'held configure disables header immediately')
      header.choose('role:editor')
      t.equal(host.calls.length, 1, 'rapid second toggle cannot overwrite pending selection')
      t.equal(header.openRoles, ['editor', 'agent'], 'pending save retains authoritative roles until readback')
      var saved = Object.assign({}, entry.projectController.state, {
        revision: 6,
        projects: [Object.assign({}, entry.projectController.state.projects[0], {
            openRoles: ['editor', 'terminal', 'agent']
          })]
      })
      host.calls[0].done(0, JSON.stringify({
        ok: true,
        state: saved
      }), '')
      t.equal(header.openRoles, ['editor', 'terminal', 'agent'], 'authoritative configure readback updates header checks')
      t.check(!header.pending && !t.findChild(surface, 'projectsPage').details.dirty, 'autosave unlocks controls without creating a preference draft')
      header.choose('role:editor')
      t.equal(JSON.parse(host.calls[1].payload).args.openRoles, ['terminal', 'agent'], 'next toggle derives from completed readback rather than stale roles')
      host.calls[1].done(1, JSON.stringify({
        ok: false,
        error: {
          message: 'Save refused'
        }
      }), '')
      t.equal(header.openRoles, ['editor', 'terminal', 'agent'], 'failed autosave preserves saved selection and unlocks retry')
      var split = t.findChild(surface, 'projectPrimaryOpen'), toggle = t.findChild(split, 'splitToggle')
      toggle.forceActiveFocus()
      input.keyClick(Qt.Key_Down)
      t.step(80, function () {
        var menu = t.findChild(surface, 'splitMenu')
        t.check(menu.opened && menu.activeFocus, 'actual surface dropdown opens with keyboard focus')
        t.check(menu.parent === surface && menu.z > 0, 'menu uses unclipped surface overlay above siblings')
        var p = menu.mapToItem(surface, 0, 0)
        t.check(p.x >= 0 && p.y >= 0 && p.x + menu.width <= surface.width && p.y + menu.height <= surface.height, 'short narrow menu fits actual host bounds')
        t.check(menu.height < menu.implicitHeight, 'tall menu becomes scrollable rather than overflowing window')
        input.keyClick(Qt.Key_End)
        for (var i = 0; i < 12; i++)
          input.keyClick(Qt.Key_Down)
        var rows = t.findChildren(menu, 'menuRow'), cursorRow = rows[menu.cursor], pos = cursorRow.mapToItem(menu, 0, 0)
        t.check(pos.y >= 0 && pos.y + cursorRow.height <= menu.height, 'keyboard navigation reveals lower menu rows in bounded popup')
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
        input.mouseClick(cursorRow)
        t.equal(JSON.parse(host.ipcCalls[host.ipcCalls.length - 1].slice(-1)[0]), {
          projectId: 'p-one',
          checkoutId: 'c-main',
          roles: ['editor']
        }, 'overlay pointer row reaches real owner request route with one-off role only')
        t.check(!menu.opened, 'overlay action pointer closes the menu')
        toggle.forceActiveFocus()
        input.keyClick(Qt.Key_Down)
        input.keyClick(Qt.Key_Escape)
        t.check(!menu.opened && toggle.activeFocus, 'Esc restores focus to surface dropdown')
        input.keyClick(Qt.Key_Down)
        header.visible = false
        t.check(!menu.opened, 'hiding the header closes its reparented overlay menu')
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
          t.equal([op.checkoutId, op.selectionRevision, op.agentId, op.roles, op.newWindowRole], ['c-main', 6, 'codex', ['agent'], 'agent'], 'owner resolves saved checkout through revision-bound lease and preserves agent request')
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
