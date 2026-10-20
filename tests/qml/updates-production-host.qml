// The real production host must receive state from the widget's Loader boundary.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.updates" as Updates

ShellRoot {
  id: testRoot
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
  Updates.BarWidget {
    id: widget
    // Keep only the collector inert while the widget selects its production host below.
    testStatus: ({
        updates: [
          {
            source: "system",
            name: "one"
          },
          {
            source: "flatpak",
            name: "two"
          }
        ]
      })
  }
  Component.onCompleted: t.step(0, function () {
    var loader = null, service = null
    for (var i = 0; i < widget.data.length; i++) {
      var child = widget.data[i]
      if (typeof child.setSource === "function")
        loader = child
      if (typeof child.applyStatus === "function" && typeof child.refresh === "function")
        service = child
    }
    t.check(loader !== null && service !== null, "widget exposes its real Loader and update service")
    if (!loader || !service) {
      t.done()
      return
    }
    // Detach only the collector override from the widget's test-host selector.
    service.testStatus = widget.testStatus
    service.autoStart = false
    widget.testStatus = null
    widget.bar = fakeBar
    t.waitFor(function () {
      return loader.item !== null
    }, 2000, "production update host loads", function () {
      var host = loader.item
      t.equal(widget.testStatus, null, "widget uses its default production host selection")
      t.check(host instanceof Updates.UpdatePanelHost, "loaded panel is the actual production UpdatePanelHost")
      t.equal(host.status.count, widget.status.count, "production dropdown receives both collected updates")
      t.equal(host.status.count, 2, "production dropdown shows the nonempty initial status")
      t.equal(t.findChild(host, "statusSubtitle").text, "2 updates available", "production content renders the collected count")
      service.testStatus = ({
          updates: [
            {
              source: "system",
              name: "three"
            }
          ],
          rebootRequired: true
        })
      service.checking = true
      widget.open()
      t.step(0, function () {
        t.equal(host.status.count, 1, "production status follows later service updates")
        t.equal(host.status.rebootRequired, true, "production status follows reboot changes")
        t.equal(t.findChild(host, "statusSubtitle").text, "1 update available", "production content renders later status")
        t.equal(t.findChild(host, "statusTitle").text, "Reboot required", "production content renders reboot state")
        t.equal(host.checking, true, "production refresh activity follows the service")
        t.equal(host.open, true, "production host follows widget open state")
        t.equal(t.findChild(host, "refreshPill").busy, true, "production refresh control renders busy state")
        t.findChild(host, "openUpdaterPill").clicked()
        t.equal(testRoot.lastCommand, "omarchy-launch-floating-terminal-with-presentation omarchy-update", "production updater action reaches the bar")
        service.applyStatus({
          updates: []
        })
        t.equal(host.status.count, 0, "production view follows an empty observed status")
        t.findChild(host, "refreshPill").clicked()
        t.equal(host.status.count, 0, "production refresh control refuses overlapping checks")
        service.checking = false
        t.findChild(host, "refreshPill").clicked()
        t.equal(host.status.count, 1, "production refresh control reaches the service after checking clears")
        service.applyStatus({
          updates: []
        })
        host.textKey("r")
        t.step(0, function () {
          t.equal(host.status.count, 1, "production refresh action reaches the real service")
          t.equal(host.checking, false, "production busy state clears reactively")
          host.closeRequested()
          t.equal(widget.opened, false, "production close action reaches the widget owner")
          t.equal(host.open, false, "production host follows widget close state")
          t.done()
        })
      })
    })
  })
}
