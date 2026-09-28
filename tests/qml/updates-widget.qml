// Offscreen QML coverage for the update bar widget.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.updates" as Updates

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
    property bool centerSectionRevealHeld: false
    property var activePopout: null
    function hideTooltip(target) {
    }
    function showTooltip(target, text) {
    }
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

  Updates.BarWidget {
    id: widget
    bar: fakeBar
    testStatus: ({
        updates: [
          {
            source: "system",
            name: "omarchy 4.0.4"
          },
          {
            source: "flatpak",
            name: "org.gimp.GIMP"
          }
        ],
        rebootRequired: true
      })
  }

  Updates.BarWidget {
    id: inactiveWidget
    bar: fakeBar
    testStatus: ({
        updates: []
      })
  }

  Component.onCompleted: {
    t.check(widget.status.count === 2, "update count is exposed")
    t.equal(widget.status.groups.length, 2, "sources are grouped")
    t.check(widget.display.visible, "available updates are visible")
    t.equal(widget.display.countText, "2", "count is rendered compactly")
    t.equal(widget.display.severity, "warning", "reboot state is a warning")
    t.check(!widget.iconDimmed, "active update icon is not dimmed")
    t.equal(widget.iconTooltip, "Updates available · reboot required", "active update icon has warning tooltip")
    t.check(!inactiveWidget.iconVisible, "inactive update icon is hidden before center hover")
    fakeBar.centerSectionRevealHeld = true
    t.check(inactiveWidget.hoverRevealed, "inactive update widget sees center hover")
    t.check(inactiveWidget.iconVisible, "inactive update widget should show on center hover")
    t.check(inactiveWidget.iconDimmed, "inactive update icon is dimmed")
    t.equal(inactiveWidget.iconTooltip, "No updates available", "inactive update icon has empty-state tooltip")
    t.step(0, function () {
      t.equal(inactiveWidget.iconVisible, true, "inactive update icon is revealed while center bar is hovered")
      inactiveWidget.panelOpen = true
      fakeBar.centerSectionRevealHeld = false
      t.check(inactiveWidget.iconVisible, "inactive update icon keeps its slot while panel is open")
      inactiveWidget.panelOpen = false
      t.check(!inactiveWidget.iconVisible, "inactive update icon hides after center hover")
      widget.openUpdater()
      t.equal(testRoot.lastCommand, "omarchy-launch-floating-terminal-with-presentation omarchy-update", "updater action delegates to Omarchy")
      t.done()
    })
  }
}
