// Real Menu search and project client; only the owner IPC boundary is replaced.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host
  // Authoritative owner projection with independently identified duplicate names.
  property var snapshot: ({
      sessionId: "agent-search",
      availability: {
        compositor: true
      },
      bindings: [],
      operations: [],
      agents: {
        tools: [
          {
            id: "claude",
            available: true
          },
          {
            id: "codex",
            available: true
          }
        ],
        usage: {
          claude: {
            limits: [
              {
                percent: 92
              }
            ]
          },
          codex: {
            limits: [
              {
                percent: 10
              }
            ]
          }
        }
      },
      projects: [
        {
          id: "p-1",
          name: "Duplicate",
          lastCheckoutId: "c-1",
          tools: {
            agentId: "claude"
          },
          openRoles: ["editor", "terminal"],
          checkouts: [
            {
              id: "c-1",
              path: "/tmp/one"
            }
          ]
        },
        {
          id: "p-2",
          name: "Duplicate",
          lastCheckoutId: "c-2",
          tools: {},
          checkouts: [
            {
              id: "c-2",
              path: "/tmp/two"
            }
          ]
        }
      ]
    })
  // Only request payloads cross the fixture boundary.
  property var requests: []
  // Captured public navigation argv stays separate from agent requests.
  property var details: []
  QmlTest {
    id: t
  }
  Menu.Menu {
    id: menu
    windowEnabled: false
    defaultMenuPath: Qt.resolvedUrl("fixtures/omarchy-menu.jsonc").toString().replace("file://", "")
    run: function (command) {
      t.check(false, "search never runs shell commands")
    }
  }
  // Read a ranked row independently of display identity.
  function row(index) {
    return menu.displayModel.count > index ? menu.displayModel.get(index) : null
  }
  // Sandbox transport keeps production normalization/request code in the path.
  function transport(argv, done) {
    if (argv[2] === "snapshot")
      done(0, JSON.stringify(host.snapshot), "")
    else if (argv[2] === "request") {
      host.requests = host.requests.concat([JSON.parse(argv[3])])
      done(0, JSON.stringify({
        ok: true,
        operationId: "agent-op"
      }), "")
    } else if (argv[2] !== "operation")
      t.check(false, "unknown IPC rejected")
  }
  Component.onCompleted: {
    var client = menu.projectClient
    client.runner = host.transport
    client.pollInterval = 10000
    client.snapshot = host.snapshot
    client.captureActive = false
    menu.desktopSearch.compositor = null
    menu.desktopSearch.runner = function (argv) {
      host.details = host.details.concat([argv])
      return true
    }
    menu.openRoute("root")
    t.waitFor(function () {
      return menu.rowsLoaded && menu.opened
    }, 10000, "menu opens", function () {
      menu.setFilter("agent duplicate")
      menu.desktopSearch.refreshNow()
      t.equal(menu.displayModel.count, 4, "duplicate projects retain both installed providers")
      t.equal(row(0) ? row(0).desktopKey : "", "project-agent:p-1:codex", "suggested Codex ranks first despite alphabet and last used Claude")
      t.check(row(0) && row(0).detail.indexOf("Suggested") >= 0 && row(0).icon.length > 0, "agent row shows suggestion and icon")
      t.equal(menu.recoveryLabel, "Project details", "agent rows expose project details")
      menu.recoverSelected()
      t.equal(host.details, [["aranea", "projects", "details", "p-1"]], "agent details resolves opaque project")
      t.equal(host.requests.length, 0, "details never starts an agent")
      menu.openRoute("root")
      menu.setFilter("claude duplicate")
      menu.desktopSearch.refreshNow()
      t.equal(menu.displayModel.count, 2, "explicit provider excludes other provider")
      t.equal(row(0).desktopKey, "project-agent:p-1:claude", "explicit Claude retains provider identity")
      var cached = row(0).desktopKey
      // Mutate in place to exercise freshness without source publication.
      client.snapshot.agents.tools[0].available = false
      t.check(!menu.desktopSearch.activate(cached), "removed installed provider refuses cached activation")
      t.equal(host.requests.length, 0, "removed provider emits no request")
      client.snapshot.agents.tools[0].available = true
      client.snapshot.projects[0].lastCheckoutId = "c-other"
      t.check(!menu.desktopSearch.activate(cached), "changed selected checkout refuses cached activation")
      t.equal(host.requests.length, 0, "changed checkout emits no request")
      client.snapshot.projects[0].lastCheckoutId = "c-1"
      menu.setFilter("agent duplicate")
      menu.desktopSearch.refreshNow()
      t.check(menu.desktopSearch.activate("project-agent:p-1:codex"), "agent activation uses project owner")
      t.equal(host.requests, [
        {
          projectId: "p-1",
          checkoutId: "c-1",
          roles: ["agent"],
          newWindowRole: "agent",
          agentId: "codex"
        }
      ], "owner receives exact provider and agent-only new window roles")
      t.equal(row(0).actionStatus, "pending", "agent launch publishes pending feedback")
      t.equal(row(0).actionMessage, "Starting agent…", "pending feedback describes agent launch")
      t.check(menu.opened, "agent launch keeps menu open")
      t.equal(client.snapshot.projects[0].openRoles, ["editor", "terminal"], "agent activation leaves saved Open roles intact")
      t.done()
    })
  }
}
