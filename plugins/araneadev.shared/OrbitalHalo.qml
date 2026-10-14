// Layered orbital artwork; the host paints its fixed emblem above the halo.
import QtQuick
import QtQuick.Shapes
import QtQuick.Window

Item {
  id: halo
  // Logical presentation, independent of entrance/exit opacity.
  property bool presented: true
  // Shared preference, overridable by inert preview hosts.
  property bool motionEnabled: MotionState.motionEnabled
  // The two accent strands used by the owning surface.
  property color primary: DesignTokens.accentSecondary
  // Color of the counter-rotating inner strand.
  property color secondary: DesignTokens.strandEnd
  // Native window visibility is independent of the Item visibility chain.
  readonly property var hostWindow: Window.window
  // A hidden host never runs a decorative loop.
  readonly property bool running: presented && visible && motionEnabled && (!hostWindow || hostWindow.visible)

  Rectangle {
    anchors.fill: parent
    anchors.margins: parent.width * 0.13
    radius: width / 2
    color: Qt.alpha(halo.primary, 0.045)
    border.width: 1
    border.color: Qt.alpha(halo.primary, 0.18)
  }
  Shape {
    id: outer
    anchors.fill: parent
    ShapePath {
      strokeWidth: 1.5
      strokeColor: Qt.alpha(halo.primary, 0.65)
      fillColor: "transparent"
      startX: outer.width * 0.5
      startY: outer.height * 0.025
      PathArc {
        x: outer.width * 0.975
        y: outer.height * 0.5
        radiusX: outer.width * 0.475
        radiusY: outer.height * 0.475
      }
    }
    ShapePath {
      strokeWidth: 1
      strokeColor: Qt.alpha(halo.secondary, 0.5)
      fillColor: "transparent"
      startX: outer.width * 0.5
      startY: outer.height * 0.975
      PathArc {
        x: outer.width * 0.025
        y: outer.height * 0.5
        radiusX: outer.width * 0.475
        radiusY: outer.height * 0.475
      }
    }
    Rectangle {
      x: parent.width * 0.5 - width / 2
      y: parent.height * 0.025 - height / 2
      width: Math.max(2, parent.width * 0.035)
      height: width
      radius: width / 2
      color: halo.primary
    }
    RotationAnimator on rotation {
      from: 0
      to: 360
      duration: 36000
      loops: Animation.Infinite
      running: halo.running
    }
  }
  Shape {
    id: inner
    anchors.fill: parent
    anchors.margins: parent.width * 0.085
    rotation: 35
    ShapePath {
      strokeWidth: 1
      strokeColor: Qt.alpha(halo.secondary, 0.45)
      fillColor: "transparent"
      startX: inner.width * 0.5
      startY: 1
      PathArc {
        x: inner.width - 1
        y: inner.height * 0.5
        radiusX: inner.width * 0.5 - 1
        radiusY: inner.height * 0.5 - 1
      }
      PathArc {
        x: inner.width * 0.5
        y: inner.height - 1
        radiusX: inner.width * 0.5 - 1
        radiusY: inner.height * 0.5 - 1
      }
    }
    RotationAnimator on rotation {
      from: 35
      to: -325
      duration: 48000
      loops: Animation.Infinite
      running: halo.running
    }
  }
}
