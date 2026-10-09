// Real IPC composition, owner, client and views; only desktop/provider actions are inert.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.activity" as Activity
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.agents" as Agents

ShellRoot {
  id: host
  // The accepted launch count is independent of transport observation.
  property int launches: 0
  // Snapshot generation synchronization for the public test endpoint.
  property int publishedRevision: -1
  Projects.ProjectRuntime {
    id: helpers
    captureActive: true
  }
  Activity.ActivityRuntime {
    id: storeRuntime
    scriptsPath: Quickshell.env('ARANEA_FLOW_ROOT') + '/scripts'
    engine.captureActive: true
    processRunner: helpers.processRunner
  }
  Activity.Activity {
    id: endpoint
    captureActive: true
  }
  Activity.ActivityClient {
    id: client
    pollInterval: 60000
    runner: function (argv, done) {
      helpers.processRunner(argv, '', done)
    }
  }
  QmlTest {
    id: t
  }
  FloatingWindow {
    visible: true
    implicitWidth: 500
    implicitHeight: 600
    Agents.AgentTasks {
      id: view
      width: 460
      maxHeight: 540
      snapshot: client.snapshot
      captureActive: true
      projectSnapshot: host.projects
    }
  }
  // Actual registered project store snapshot, obtained by a real helper.
  property var projects: ({
      projects: []
    })
  // Fixed desktop/provider substitute retains real store and IPC consumers.
  property var boundary: ({
      sessionId: 'fixture-desktop',
      readStore: storeRuntime.readStore,
      dismiss: storeRuntime.dismiss,
      readNotificationPolicy: function (done) {
        done({
          available: true,
          suppressed: true
        })
      },
      focusSession: function (task, session, done) {
        done({
          ok: false,
          code: 'OWNERSHIP_UNCONFIRMED',
          message: 'Fixture has no native desktop.'
        })
      },
      prepare: function (task, workspaceOnly, done) {
        var project = host.projects.projects.filter(function (p) {
          return p.id === task.association.projectId
        })[0]
        var checkout = project && project.checkouts.filter(function (c) {
          return c.id === task.association.checkoutId && c.path === task.association.cwd
        })[0]
        done(checkout ? {
          ok: true,
          projectId: project.id,
          checkoutId: checkout.id,
          cwd: checkout.path,
          workspaceId: 2
        } : {
          ok: false,
          code: 'CHECKOUT_INVALID'
        })
      },
      launch: function (task, preparation, done) {
        host.launches++
        done({
          ok: true,
          identity: {
            pid: 55,
            startTime: '1'
          },
          spec: {},
          baseline: {
            windows: []
          }
        })
      },
      observeTerminal: function (op, done) {
        done({
          status: 'observed',
          binding: {
            address: '0xa'
          }
        })
      },
      observeResume: function (op, done) {
        done({
          terminal: {
            status: 'observed',
            binding: {
              address: '0xa'
            }
          },
          native: null
        })
      },
      validateReobserve: function (op, done) {
        done(true)
      }
    })
  Connections {
    target: endpoint.owner
    function onSnapshotChanged() {
      host.publishedRevision = endpoint.owner.snapshot().revision
      client.refresh()
    }
  }
  IpcHandler {
    target: 'fixture'
    function refresh(): string {
      endpoint.owner.refresh()
      return 'refreshing'
    }
    function snapshot(): string {
      return JSON.stringify({
        owner: endpoint.owner.snapshot(),
        client: client.snapshot,
        rows: view.taskRows,
        launches: host.launches
      })
    }
    function inspect(taskId: string): string {
      view.openDetails(taskId)
      return JSON.stringify({
        selected: view.selectedRow,
        detailId: view.selectedId,
        resultText: t.findChild(view, "reportedResult").text
      })
    }
    function finish(): string {
      t.equal(client.snapshot.revision, endpoint.owner.snapshot().revision, 'real client observes current real owner revision')
      t.equal(view.taskRows.length, client.snapshot.tasks.length, 'production Tasks displays all actual client records')
      t.done()
      return 'done'
    }
  }
  Component.onCompleted: {
    helpers.processRunner([Quickshell.env('ARANEA_FLOW_ROOT') + '/scripts/aranea-project-store', 'snapshot'], '', function (code, output) {
      host.projects = JSON.parse(output).state
      endpoint.owner.runtime = host.boundary
      endpoint.owner.pollInterval = 60000
      endpoint.owner.operationTimeout = 80
      endpoint.captureActive = false
      endpoint.owner.refresh()
    })
  }
}
