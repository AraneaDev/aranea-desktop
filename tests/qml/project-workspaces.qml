// Isolated overview integration: the real ProjectClient reads only fake IPC,
// project labels retain cursor/focus identity, and capture is inert.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.workspaces" as Workspace

ShellRoot {
  id: testRoot
  // Snapshot argv observed at the fake IPC boundary.
  property var calls: []
  // Delayed transport completions for freshness and visibility tests.
  property var replies: []
  // Compositor command observed through the fake bar boundary.
  property string lastCommand: ""
  // Complete owner projection with distinct dedicated worktree associations.
  property var snapshot: ({
      sessionId: "session-new",
      observedAt: 123,
      availability: {
        compositor: true
      },
      projects: [
        {
          id: "p-app",
          name: "App",
          lastCheckoutId: "c-main",
          workspaceMode: "dedicated",
          checkouts: [
            {
              id: "c-main",
              path: "/projects/app",
              branch: "main",
              primary: true
            },
            {
              id: "c-fix",
              path: "/a/very/long/path/to/projects/app-fix",
              branch: "fix",
              primary: false
            }
          ],
          associations: [
            {
              checkoutId: "c-main",
              mode: "dedicated",
              workspaceId: 2,
              separate: false
            },
            {
              checkoutId: "c-fix",
              mode: "dedicated",
              workspaceId: 7,
              separate: true
            }
          ]
        }
      ],
      bindings: [],
      operations: []
    })
  QmlTest {
    id: t
  }
  QtObject {
    id: fakeBar
    property string position: "top"
    property bool vertical: false
    property int barSize: 26
    property color foreground: "white"
    property color barForeground: "white"
    property color background: "#17151f"
    property string fontFamily: "monospace"
    property bool foregroundAnimationEnabled: false
    property color urgent: "#ff6688"
    function run(command) {
      testRoot.lastCommand = command
    }
    function hideTooltip(owner) {
    }
    function showTooltip(owner, text) {
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 500
    implicitHeight: 32
    Workspace.BarWidget {
      id: widget
      bar: fakeBar
      testWorkspaces: [
        {
          id: 2,
          windows: 1
        },
        {
          id: 7,
          windows: 1
        }
      ]
      testFocusedWorkspace: 2
    }
  }
  Component.onCompleted: {
    var client = widget.projectClient
    t.check(!!client, "overview composes a ProjectClient")
    if (!client) {
      t.done()
      return
    }
    client.runner = function (argv, done) {
      testRoot.calls = testRoot.calls.concat([argv])
      testRoot.replies = testRoot.replies.concat([done])
    }
    t.check(widget.captureActive && client.captureActive, "preview begins inert before reads")
    widget.open()
    widget.focusWorkspace(7)
    t.equal(testRoot.calls.length, 0, "capture opening never reads IPC")
    t.equal(testRoot.lastCommand, "", "capture refuses compositor focus")
    var host = t.findChild(widget, "testPanelHost")
    var panel = t.findChild(host, "workspacePanel")
    t.check(!!panel, "production panel is composed into test host")
    widget.captureActive = false
    t.equal(testRoot.calls.length, 1, "leaving capture in an open overview refreshes once")
    t.equal(testRoot.calls[0], ["omarchy-shell", "aranea.projects", "snapshot"], "overview only reads the owner snapshot")
    testRoot.replies[0](0, JSON.stringify(testRoot.snapshot), "")
    t.equal(panel.rowAt(0).label, "Workspace 2", "saved assignment alone does not label unrelated windows")
    t.equal(panel.rowAt(1).label, "Workspace 7", "unconfirmed worktree falls back to its workspace label")
    testRoot.snapshot.bindings = [
      {
        projectId: "p-app",
        checkoutId: "c-main",
        workspaceId: 2,
        sessionId: "session-new",
        role: "editor",
        pid: 41,
        address: "0xab",
        evidence: {
          processVerified: true,
          mode: "process-only"
        }
      },
      {
        projectId: "p-app",
        checkoutId: "c-fix",
        workspaceId: 7,
        sessionId: "session-new",
        role: "terminal",
        pid: 42,
        address: "0xac",
        evidence: {
          processVerified: true,
          mode: "process-only"
        }
      }
    ]
    client.snapshot = JSON.parse(JSON.stringify(testRoot.snapshot))
    t.equal(panel.rowAt(0).label, "App · main", "dedicated association decorates main checkout")
    t.equal(panel.rowAt(1).label, "App · fix", "separate association selects exact worktree")
    var path = t.findChildren(panel, "workspaceProjectPath")[1]
    t.check(path.visible && path.text === "/a/very/long/path/to/projects/app-fix", "exact checkout path is visible")
    t.check(path.elide === Text.ElideLeft && path.width <= panel.width, "long checkout paths stay elided within the row")
    var row = panel.rowAt(1)
    host.cursorKey = "7"
    host.keyboardCursor = true
    var changed = JSON.parse(JSON.stringify(testRoot.snapshot))
    changed.projects[0].name = "Renamed"
    client.snapshot = changed
    t.equal(panel.rowAt(1).label, "Renamed · fix", "fresh project labels update the existing row")
    t.check(panel.rowAt(1) === row && host.cursorKey === "7" && host.cursorRow === 1, "labels retain row and cursor identities")
    changed = JSON.parse(JSON.stringify(changed))
    changed.environments = [
      {
        id: 'e-old',
        projectId: 'p-app',
        checkoutId: 'c-main',
        workspaceId: 7,
        sessionId: 'old-creation',
        profileSnapshot: {
          name: 'Original terminal'
        },
        checkoutSnapshot: {
          branch: 'launch-branch',
          path: '/saved/path'
        }
      }
    ]
    changed.bindings = [
      {
        environmentId: 'e-old',
        projectId: 'p-app',
        checkoutId: 'c-main',
        workspaceId: 7,
        sessionId: 'session-new',
        role: 'terminal',
        pid: 42,
        address: '0xaa',
        evidence: {
          processVerified: true,
          mode: 'process-only'
        }
      }
    ]
    client.snapshot = changed
    t.equal(panel.rowAt(1).label, 'Renamed · Original terminal', 'workspace uses immutable environment profile name')
    t.check(t.findChildren(panel, 'workspaceProjectPath')[1].text.indexOf('terminal observed') >= 0, 'fresh current-session recovery proves old saved environment')
    changed = JSON.parse(JSON.stringify(changed))
    changed.bindings[0].sessionId = 'stale'
    client.snapshot = changed
    t.check(t.findChildren(panel, 'workspaceProjectPath')[1].text.indexOf('unconfirmed') >= 0, 'stale binding never claims saved environment live')
    panel.activateRow(1, "7")
    t.check(testRoot.lastCommand.indexOf('workspace = "7"') >= 0, "row activation keeps the original workspace focus target")
    t.equal(testRoot.calls.length, 1, "focus never submits a project request")
    widget.close()
    t.check(!client.captureActive, "visible bar keeps project context after closing the overview")
    widget.refreshProjects()
    t.equal(testRoot.calls.length, 2, "visible bar can refresh while the overview is closed")
    testRoot.replies[1](1, "", "Owner unavailable")
    t.equal(panel.rowAt(0).label, "Workspace 2", "unavailable owner restores ordinary labels despite cached projects")
    t.check(!t.findChildren(panel, "workspaceProjectPath")[0].visible, "unavailable owner hides project path")
    widget.visible = false
    t.check(client.captureActive, "hidden bar invalidates snapshot reads")
    var count = testRoot.calls.length
    widget.refreshProjects()
    t.equal(testRoot.calls.length, count, "hidden bar refuses explicit reads")
    widget.visible = true
    widget.open()
    testRoot.replies[count](0, JSON.stringify(testRoot.snapshot), "")
    var beforePoll = testRoot.calls.length
    t.step(5100, function () {
      t.equal(testRoot.calls.length, beforePoll + 1, "visible bar refreshes periodically")
      t.equal(testRoot.calls[beforePoll], ["omarchy-shell", "aranea.projects", "snapshot"], "periodic refresh stays read-only")
      panel.maxContentHeight = 110
      t.step(30, function () {
        t.check(panel.implicitHeight <= 110, "project path rows respect the capped panel height")
        widget.close()
        count = testRoot.calls.length
        widget.refreshProjects()
        t.equal(testRoot.calls.length, count, "periodic polling serializes a held owner read")
        widget.visible = false
        testRoot.replies[beforePoll](0, JSON.stringify(testRoot.snapshot), "")
        t.equal(panel.rowAt(0).label, "Workspace 2", "late hidden response cannot restore project context")
        t.step(100, function () {
          t.equal(testRoot.calls.length, count, "hidden bar does not poll owner")
          widget.visible = true
          widget.open()
          t.equal(testRoot.calls.length, count + 1, "showing the bar reads again")
          widget.captureActive = true
          testRoot.replies[count](0, JSON.stringify(testRoot.snapshot), "")
          t.equal(panel.rowAt(0).label, "Workspace 2", "late capture response cannot restore project context")
          testRoot.lastCommand = ""
          widget.open()
          widget.focusPanelWorkspace(7)
          t.equal(testRoot.calls.length, count + 1, "capture remains inert across reopening")
          t.equal(testRoot.lastCommand, "", "capture panel activation cannot focus workspace")
          t.done()
        })
      })
    })
  }
}
