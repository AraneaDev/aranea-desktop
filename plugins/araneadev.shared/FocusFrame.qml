// Keyboard target reticle; decorative only, with no input ownership.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Item {
  id: frame
  // Host-owned keyboard target state, distinct from persistent selection.
  property bool focused: false
  // Fade and settle only when the theme permits motion.
  readonly property int duration: DesignTokens.motionEnabled ? DesignTokens.feedbackDuration : 0
  // Corner segments stay proportional even on compact icon controls.
  readonly property real segment: Math.min(Style.space(10), width / 4, height / 3)
  opacity: focused ? 1 : 0
  scale: focused ? 1 : 0.98
  visible: focused || opacity > 0
  Behavior on opacity {
    enabled: DesignTokens.motionEnabled
    NumberAnimation {
      duration: frame.duration
    }
  }
  Behavior on scale {
    enabled: DesignTokens.motionEnabled
    NumberAnimation {
      duration: frame.duration
      easing.type: Easing.OutCubic
    }
  }
  Connections {
    target: MotionState
    function onMotionEnabledChanged() {
      if (MotionState.motionEnabled)
        return
      frame.opacity = Qt.binding(function () {
        return frame.focused ? 1 : 0
      })
      frame.scale = Qt.binding(function () {
        return frame.focused ? 1 : 0.98
      })
    }
  }
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: Util.alpha(DesignTokens.accent, 0.13)
      }
      GradientStop {
        position: 0.6
        color: Util.alpha(DesignTokens.accent, 0.035)
      }
      GradientStop {
        position: 1
        color: Util.alpha(DesignTokens.strandEnd, 0.10)
      }
    }
  }
  Repeater {
    model: 4
    Item {
      id: corner
      required property int index
      readonly property bool atRight: index % 2 === 1
      readonly property bool atBottom: index >= 2
      readonly property color ink: atRight ? DesignTokens.strandEnd : DesignTokens.accent
      x: atRight ? frame.width - width : 0
      y: atBottom ? frame.height - height : 0
      width: frame.segment
      height: frame.segment
      Rectangle {
        width: parent.width
        height: Math.max(1, Style.space(1))
        y: corner.atBottom ? parent.height - height : 0
        color: corner.ink
      }
      Rectangle {
        height: parent.height
        width: Math.max(1, Style.space(1))
        x: corner.atRight ? parent.width - width : 0
        color: corner.ink
      }
    }
  }
  Rectangle {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(2, Style.space(2))
    height: Math.min(Style.space(12), parent.height / 3)
    color: DesignTokens.accent
  }
}
