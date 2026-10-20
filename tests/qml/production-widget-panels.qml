// Exercise each widget's real panel source and its injected live properties.
// The runner adapts only SpringPanel's native window; no test panel host is used.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.workspaces" as Workspace
import "plugins/araneadev.clock" as Clock
import "plugins/araneadev.weather" as Weather

ShellRoot {
  id: testRoot
  property var rows: [
    {
      id: 1,
      windows: 1
    },
    {
      id: 3,
      windows: 2
    }
  ]
  property string lastCommand: ""
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
    property var activePopout: null
    function requestPopout(owner) {
      activePopout = owner
    }
    function releasePopout(owner) {
      if (activePopout === owner)
        activePopout = null
    }
    function hideTooltip(owner) {
    }
    function run(command) {
      testRoot.lastCommand = command
    }
    function setCenterHoverRevealSuppressed(value) {
    }
    function moduleWidgets(name) {
      return []
    }
  }
  Workspace.BarWidget {
    id: workspaces
    bar: fakeBar
    captureActive: true
    testFocusedWorkspace: 1
    function liveWorkspaceRows() {
      return testRoot.rows
    }
  }
  Clock.BarWidget {
    id: clock
    bar: fakeBar
    settings: ({
        format: "HH:mm",
        fixtureRevision: 1
      })
  }
  Weather.BarWidget {
    id: weather
    bar: fakeBar
    settings: ({
        fixtureRevision: 1
      })
  }
  Component.onCompleted: t.step(0, function () {
    var panel = t.findChild(workspaces, "workspacePanel")
    t.check(workspaces.testWorkspaces === null, "workspaces uses its production Loader source")
    t.check(panel !== null, "the production WorkspacePanelHost creates its view")
    if (!panel) {
      t.done()
      return
    }
    t.check(workspaces.visibleStates.length >= 2, "workspace input is nonempty")
    t.equal(panel.workspaceStates, workspaces.visibleStates, "production workspace view receives normalized rows")
    testRoot.rows = [
      {
        id: 1,
        windows: 1
      },
      {
        id: 7,
        windows: 3
      }
    ]
    t.equal(panel.workspaceStates, workspaces.visibleStates, "production workspace rows remain bound after a change")
    workspaces.projectClient.runner = function (argv, done) {}
    workspaces.captureActive = false
    workspaces.projectClient.available = true
    workspaces.projectClient.snapshot = {
      sessionId: "fixture",
      projects: [],
      bindings: []
    }
    t.equal(panel.projectSnapshot, workspaces.projectSnapshot, "production workspace project snapshot is bound")
    workspaces.projectClient.snapshot = {
      sessionId: "updated",
      projects: [],
      bindings: []
    }
    t.equal(panel.projectSnapshot.sessionId, "updated", "production workspace snapshot follows replacements")
    var host = panel.parent
    while (host && !(host as Workspace.WorkspacePanelHost))
      host = host.parent
    t.check(host !== null, "workspace view belongs to the actual production host type")
    workspaces.open()
    t.check(host && host.open, "production workspace host follows the widget open state")
    panel.focusWorkspace(7)
    t.check(testRoot.lastCommand.indexOf('7') >= 0, "production workspace activation reaches the bar transport")
    t.check(!workspaces.opened, "production workspace activation closes the widget")
    t.check(host && !host.open, "production workspace host follows the widget close state")
    checkPanel(clock, clock.clockPanel, "clock")
    checkPanel(weather, weather.weatherPanel, "weather")
    clock.settings = {
      format: "HH:mm",
      fixtureRevision: 2
    }
    weather.settings = {
      fixtureRevision: 2
    }
    t.equal(clock.clockPanel.settings.fixtureRevision, 2, "production clock settings update reaches its panel")
    t.equal(weather.weatherPanel.settings.fixtureRevision, 2, "production weather settings update reaches its panel")
    t.done()
  })
  function checkPanel(widget, panel, name) {
    t.check(panel !== null, name + " loads its real Panel.qml")
    if (!panel)
      return
    t.check(panel.bar === fakeBar, name + " injects the production bar")
    t.check(panel.hostWidget === widget && panel.barIdentity === widget, name + " injects the production owner identity")
    t.check(panel.anchorItem !== null, name + " injects the bar anchor")
    t.equal(panel.settings.fixtureRevision, 1, name + " injects initial settings")
    widget.open()
    t.check(widget.opened && panel.opened, name + " opens its production panel")
    widget.close()
    t.check(!widget.opened && !panel.opened, name + " closes its production panel")
  }
}
