// Instrument material and traveling light, paused when hidden or motion is off.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import qs.Commons

Item {
  id: frame
  // Keep the corner marks clear of the host's rounded border.
  property real cornerRadius: DesignTokens.cornerRadius
  // Accent colors follow the existing Aranea palette.
  property color accent: DesignTokens.accent
  // Violet end of the traveling edge highlight.
  property color secondary: DesignTokens.strandEnd
  // Branding can use the instrument bezel without a panel material layer.
  property bool material: true
  // Shared motion preference, overridable by deterministic captures.
  property bool motionEnabled: MotionState.motionEnabled
  // Animate only while a visible window can display the frame.
  readonly property bool ambientRunning: motionEnabled && visible && frame.Window.window !== null && frame.Window.window.visible && width > 0 && height > 0
  // Progress of the repeating edge-light sweep.
  property real energyPhase: 0
  // Keep edge marks clear of the host border and corner radius.
  readonly property real inset: Math.max(Style.space(7), cornerRadius)
  // Scale short traces to the available frame dimensions.
  readonly property real traceLength: Math.min(Style.space(28), width / 8, height / 8)

  NumberAnimation {
    target: frame
    property: "energyPhase"
    from: 0
    to: 1
    duration: 5200
    loops: Animation.Infinite
    running: frame.ambientRunning
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 2
    radius: frame.cornerRadius
    visible: frame.material
    gradient: Gradient {
      GradientStop {
        position: 0
        color: Util.alpha(frame.accent, 0.09)
      }
      GradientStop {
        position: 0.3
        color: Util.alpha(DesignTokens.background, 0)
      }
      GradientStop {
        position: 1
        color: Util.alpha(frame.secondary, 0.055)
      }
    }
  }

  Rectangle {
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.margins: 2
    width: Style.space(4)
    visible: frame.material
    gradient: Gradient {
      GradientStop {
        position: 0
        color: Util.alpha(frame.accent, 0.65)
      }
      GradientStop {
        position: 0.45
        color: Util.alpha(frame.accent, 0.06)
      }
      GradientStop {
        position: 1
        color: Util.alpha(frame.secondary, 0.4)
      }
    }
  }

  Item {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 2
    height: Style.space(4)
    clip: true
    visible: frame.ambientRunning
    Rectangle {
      width: Math.min(Style.space(110), frame.width / 3)
      height: parent.height
      x: (frame.width + width) * frame.energyPhase - width
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
          position: 0
          color: "transparent"
        }
        GradientStop {
          position: 0.5
          color: Util.alpha(frame.accent, 0.9)
        }
        GradientStop {
          position: 1
          color: "transparent"
        }
      }
    }
  }

  Repeater {
    model: 4
    delegate: Item {
      required property int index
      x: index % 2 === 0 ? frame.inset : frame.width - frame.inset - width
      y: index < 2 ? frame.inset : frame.height - frame.inset - height
      width: frame.traceLength
      height: frame.traceLength
      opacity: 0.62
      Rectangle {
        width: parent.width
        height: 1
        y: parent.index < 2 ? 0 : parent.height - height
        color: parent.index % 2 === 0 ? frame.accent : frame.secondary
      }
      Rectangle {
        width: 1
        height: parent.height
        x: parent.index % 2 === 0 ? 0 : parent.width - width
        color: parent.index % 2 === 0 ? frame.accent : frame.secondary
      }
    }
  }

  Rectangle {
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: 1
    width: Math.min(Style.space(180), parent.width * 0.4)
    height: 1
    opacity: 0.65
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: "transparent"
      }
      GradientStop {
        position: 0.3
        color: frame.accent
      }
      GradientStop {
        position: 0.7
        color: frame.secondary
      }
      GradientStop {
        position: 1
        color: "transparent"
      }
    }
  }
}
