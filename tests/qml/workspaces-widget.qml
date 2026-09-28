// Offscreen QML coverage for the workspace bar widget.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.workspaces" as Workspace

ShellRoot {
  id: testRoot

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
    function run(command) {
      testRoot.lastCommand = command
    }
  }

  // Last command sent through the fake bar.
  property string lastCommand: ""

  Workspace.BarWidget {
    id: widget
    bar: fakeBar
    testWorkspaces: [
      {
        id: 1,
        windows: [
          {
            address: "a"
          }
        ]
      },
      {
        id: 2,
        windows: []
      },
      {
        id: 3,
        windows: [
          {
            title: "Editor",
            appId: "nvim"
          }
        ],
        urgent: true
      }
    ]
    testFocusedWorkspace: 1
  }

  Component.onCompleted: {
    t.check(widget.activeWorkspaceId === 1, "active workspace is exposed")
    t.equal(widget.indicatorDots.length, 3, "all normal workspaces are dotted")
    t.check(widget.indicatorDots[2].urgent, "urgent workspace is marked")
    t.equal(widget.visibleStates[1].windowLabels, ["Editor"], "window label is available")
    widget.focusPanelWorkspace(3)
    t.check(testRoot.lastCommand.indexOf('workspace = "3"') >= 0, "popover workspace focus dispatches")
    t.check(widget.implicitWidth > 0 && widget.implicitHeight > 0, "widget has bar geometry")
    fakeBar.vertical = true
    t.check(widget.implicitHeight > 0, "vertical bar geometry remains valid")
    t.done()
  }
}
