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

  Component.onCompleted: {
    t.check(widget.status.count === 2, "update count is exposed")
    t.equal(widget.status.groups.length, 2, "sources are grouped")
    t.check(widget.display.visible, "available updates are visible")
    t.equal(widget.display.countText, "2", "count is rendered compactly")
    t.equal(widget.display.severity, "warning", "reboot state is a warning")
    widget.openUpdater()
    t.equal(testRoot.lastCommand, "omarchy-launch-floating-terminal-with-presentation omarchy-update", "updater action delegates to Omarchy")
    t.done()
  }
}
