// Capture both production tray renderers with a real Qt RHI scenegraph.
import QtQuick
import Quickshell
import "lib"
import "tray-host"
import "plugins/araneadev.tray" as Tray
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  id: test
  QmlTest {
    id: t
  }
  QtObject {
    id: bar
    property string fontFamily: "sans-serif"
    property color barForeground: foreground
    property color urgent: foreground
    property bool foregroundAnimationEnabled: false
    property bool vertical: false
    property int barSize: 31
    property color foreground: "#44ddaa"
    property string position: "top"
    property var activePopout: null
    property var layoutConfig: ({})
    function registerClickTarget(target) {
    }
    function unregisterClickTarget(target) {
    }
    function showTooltip(target, text) {
    }
    function hideTooltip(target) {
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 800
    implicitHeight: 600
    color: "#101010"
    Rectangle {
      id: scene
      anchors.fill: parent
      color: "#101010"
      Tray.Tray {
        id: tray
        x: 20
        y: 20
        bar: bar
        settings: ({
            pinned: ["dark-symbolic", "light-symbolic", "color"]
          })
      }
      Tray.TrayManageView {
        id: manage
        x: 20
        y: 80
        width: 500
        view: ({
            rows: SystemTray.items.values.map(function (item) {
              return {
                key: item.id,
                name: item.title,
                icon: item.icon,
                pinned: true,
                hidden: false,
                pending: false
              }
            }),
            empty: false
          })
      }
    }
  }
  // Locate production icon image centers for independent pixel assertions.
  function collect(parent, expected, label) {
    var found = []
    function visit(item) {
      if (item.source !== undefined && String(item.source).indexOf(Quickshell.env("ARANEA_NATIVE_CAPTURE")) >= 0) {
        var point = item.mapToItem(scene, item.width / 2, item.height / 2)
        var margin = item.mapToItem(scene, 0, 0)
        found.push({
          name: label + ":" + String(item.source).split("/").pop(),
          x: point.x,
          y: point.y,
          marginX: margin.x,
          marginY: margin.y,
          color: String(item.source).endsWith("color") ? "#ed3960" : expected
        })
        t.check(item.status === Image.Ready, label + " source is decoded")
        t.check(Number.isInteger(item.parent.x) && Number.isInteger(item.parent.y), label + " icon is pixel aligned")
      }
      t.childrenOf(item).forEach(visit)
    }
    if (parent === tray)
      tray.trayItemViews.forEach(visit)
    else
      visit(parent)
    t.equal(found.length, 3, label + " renders all three real icons")
    return found
  }
  Component.onCompleted: t.step(500, function () {
    // Odd slot dimensions exercise pixel rounding independently of theme size.
    tray.trayItemViews.forEach(function (item) {
      item.width = 31
      item.height = 31
    })
    t.findChildren(manage, "rowIcon").forEach(function (item) {
      item.parent.parent.height = 35
    })
    t.step(400, function () {
      t.check(scene.GraphicsInfo.api !== GraphicsInfo.Software && scene.GraphicsInfo.api !== GraphicsInfo.Unknown, "real shader-capable Qt Quick backend")
      console.log("NATIVE GRAPHICS API", scene.GraphicsInfo.api)
      var points = collect(tray, "#44ddaa", "tray").concat(collect(manage, Aranea.DesignTokens.foreground.toString(), "manage"))
      scene.grabToImage(function (result) {
        t.check(result.saveToFile(Quickshell.env("ARANEA_NATIVE_CAPTURE") + "/tray.png"), "real tray scene capture saved")
        console.log("NATIVE PIXELS " + JSON.stringify({
          width: scene.width,
          points: points
        }))
        console.log("NATIVE READY")
        t.done()
      })
    })
  })
}
