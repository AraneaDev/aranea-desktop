// Native tooltip scaling, peek hover and fullscreen click-through acceptance.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "bar-host"
import "plugins/araneadev.bar" as Bar

ShellRoot {
  id: test
  QmlTest {
    id: t
  }
  // Actual native pointer releases received by the underlying window.
  property int clicks: 0
  // The real production layer-shell bar surface.
  property var panel: null
  // The real production tooltip popup.
  property var tooltip: null
  // Latch a visible bubble observed before its output scale arrives.
  property bool badFirstFrame: false
  // Initial stable bar surface width.
  property real initialWidth: 0
  // Initial stable bar surface height.
  property real initialHeight: 0
  Bar.Bar {
    id: bar
    motionEnabled: false
    barConfig: ({
        transparent: false,
        centerAnchor: "native-clock",
        layout: {
          left: [],
          center: [
            {
              id: "native-clock",
              source: Quickshell.env("ARANEA_NATIVE_CAPTURE") + "/cfg/NativeClock.qml"
            }
          ],
          right: []
        }
      })
  }
  FloatingWindow {
    id: sink
    title: "Aranea native click sink"
    visible: true
    implicitWidth: 800
    implicitHeight: 600
    color: "#101010"
    MouseArea {
      anchors.fill: parent
      onClicked: {
        test.clicks++
        console.log("NATIVE SINK CLICK", mouseX, mouseY)
      }
    }
  }
  Item {
    id: hoverTarget
    width: 20
    height: 20
    property bool tooltipHovered: true
  }
  Connections {
    target: test.tooltip
    function onVisibleChanged() {
      test.inspectFrame()
    }
    function onDevicePixelRatioChanged() {
      test.inspectFrame()
    }
  }
  // Observe exposure without changing production tooltip state.
  function inspectFrame() {
    if (!tooltip || !tooltip.visible)
      return
    var bubble = tooltip.nativeBubble
    if (bubble.opacity > 0 && Math.round(tooltip.devicePixelRatio * 120) !== Math.round(panel.devicePixelRatio * 120))
      badFirstFrame = true
  }
  Timer {
    interval: 1
    repeat: true
    running: true
    onTriggered: test.inspectFrame()
  }
  IpcHandler {
    target: "native.fixture"
    function state(): string {
      return JSON.stringify({
        clicks: test.clicks,
        peek: bar.centerSectionRevealHeld
      })
    }
    function checkPeek(expected: bool): void {
      t.equal(bar.centerSectionRevealHeld, expected, expected ? "leading bar region reveals peek" : "entering past the clock keeps peek closed")
    }
    function fullscreen(value: bool): void {
      Hyprland.fullscreen = value
    }
    function finish(): void {
      t.equal(test.clicks, 1, "fullscreen edge click reaches underlying native window")
      t.check(!bar.centerSectionRevealHeld, "clock and trailing area do not reveal the peek")
      t.check(!test.badFirstFrame, "first painted tooltip frame uses output scale")
      t.check(test.tooltip.nativeBubble.opacity > 0, "scaled tooltip is actually painted")
      t.check(test.panel.devicePixelRatio > 1, "tooltip acceptance uses a scaled output")
      t.equal([test.panel.width, test.panel.height], [test.initialWidth, test.initialHeight], "fullscreen input change preserves surface geometry")
      t.check(test.panel.contentItem.GraphicsInfo.api === GraphicsInfo.OpenGL, "bar acceptance uses the real OpenGL scenegraph")
      test.tooltip.nativeBubble.grabToImage(function (result) {
        t.check(result.saveToFile(Quickshell.env("ARANEA_NATIVE_CAPTURE") + "/tooltip.png"), "visible tooltip renders to a native capture")
        t.done()
      })
    }
  }
  Component.onCompleted: t.waitFor(function () {
    return bar.nativeWindows.length > 0
  }, 3000, "native bar maps", function () {
    panel = bar.nativeWindows[0]
    initialWidth = panel.width
    initialHeight = panel.height
    tooltip = panel.nativeTooltip
    hoverTarget.parent = panel.contentItem
    bar.showTooltip(hoverTarget, "Scaled tooltip")
    t.waitFor(function () {
      return tooltip.visible
    }, 2000, "tooltip maps", function () {
      console.log("NATIVE READY")
    })
  })
}
