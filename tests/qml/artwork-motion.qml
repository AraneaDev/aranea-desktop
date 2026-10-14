// Real menu and workspace presentation: hidden/reduced motion never keeps moving.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu
import "plugins/araneadev.workspaces" as Workspace

ShellRoot {
  QmlTest {
    id: t
  }
  QtObject {
    id: bar
    property bool vertical: false
    property bool barHidden: false
    property int barSize: 32
    property color foreground: "white"
    property color barForeground: "white"
    property color urgent: "#c090d0"
    property string fontFamily: "monospace"
    property bool foregroundAnimationEnabled: false
    function hideTooltip(owner) {
    }
    function showTooltip(owner, text) {
    }
  }
  FloatingWindow {
    id: hostWindow
    visible: true
    implicitWidth: 600
    implicitHeight: 300
    Menu.MenuCardChrome {
      id: menu
      width: 560
      height: 280
      fullRootHeader: true
      motionEnabled: true
    }
    Workspace.BarWidget {
      id: widget
      bar: bar
      width: implicitWidth
      height: implicitHeight
      testWorkspaces: [
        {
          id: 1,
          windows: []
        },
        {
          id: 2,
          windows: []
        },
        {
          id: 3,
          windows: []
        }
      ]
      testFocusedWorkspace: 1
    }
  }
  Component.onCompleted: t.step(30, function () {
    var halo = t.findChild(menu, "menuOrbitalHalo")
    var marker = t.findChild(widget, "workspaceActiveIndicator")
    t.check(!!halo, "menu has layered halo")
    t.check(!!marker, "workspace has sliding active indicator")
    if (!halo || !marker) {
      t.done()
      return
    }
    widget.motionEnabled = true
    t.check(halo.running, "presented root halo moves")
    var spider = t.findChild(menu, "menuBrandEmblem")
    t.equal(spider.rotation, 0, "spider remains fixed independently of halo")
    var spiderSize = spider.width
    menu.presented = false
    t.equal(halo.running, false, "closed menu stops halo")
    menu.presented = true
    menu.motionEnabled = false
    t.equal(halo.running, false, "reduced motion stops halo")
    menu.fullRootHeader = false
    t.equal(halo.visible, false, "compact search header hides halo")
    t.check(spider.width < spiderSize, "compact header preserves emblem sizing transition")
    menu.fullRootHeader = true
    menu.motionEnabled = true
    hostWindow.visible = false
    t.equal(halo.running, false, "hidden native menu window stops decorative loops")
    hostWindow.visible = true
    var start = marker.x
    widget.testFocusedWorkspace = 3
    t.step(70, function () {
      t.check(marker.x > start && marker.x < marker.destination, "indicator slides between fixed workspace slots")
      var current = marker.x
      widget.testFocusedWorkspace = 1
      t.check(Math.abs(marker.x - current) < 0.01, "rapid switch reverses from current presentation")
      widget.motionEnabled = false
      t.equal(marker.x, marker.destination, "reduced motion snaps to active slot")
      t.equal(marker.running, false, "reduced motion stops spatial animation")
      widget.testFocusedWorkspace = 99
      t.equal(marker.visible, false, "absent active workspace hides indicator")
      widget.testFocusedWorkspace = 2
      bar.vertical = true
      t.step(30, function () {
        t.equal(marker.y, marker.destination, "vertical bar indicator follows vertical slots")
        t.check(marker.height > marker.width, "vertical bar uses a vertical filament")
        widget.motionEnabled = true
        widget.testFocusedWorkspace = 3
        widget.visible = false
        t.equal(marker.running, false, "hidden workspace widget stops motion")
        t.equal(marker.y, marker.destination, "hidden workspace widget snaps latest state")
        widget.visible = true
        widget.testFocusedWorkspace = 2
        bar.barHidden = true
        t.equal(marker.running, false, "parked bar stops indicator motion")
        bar.barHidden = false
        widget.testFocusedWorkspace = 1
        hostWindow.visible = false
        t.equal(marker.running, false, "hidden native bar window stops indicator motion")
        hostWindow.visible = true
        t.waitFor(function () {
          return !marker.running
        }, 3000, "visible marker settles", function () {
          t.equal(marker.y, marker.destination, "reopened widget presents latest active workspace")
          t.done()
        })
      })
    })
  })
}
