// Aranea filament pulse: a hairline strand that lights while a background
// operation (pairing, connecting) is running. A soft light travels along
// it when motion is enabled; otherwise the strand simply lights up.
// Hidden entirely when not running.
import QtQuick
import qs.Commons

Item {
  id: pulse

  // Whether a background operation is in progress.
  property bool running: false

  implicitHeight: Style.space(6)
  visible: pulse.running

  Rectangle {
    id: strand
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(2, Style.space(2))
    color: Util.alpha(DesignTokens.foreground, 0.15)
  }

  // Static lit strand when motion is disabled.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: strand.height
    color: Util.alpha(DesignTokens.accent, 0.5)
    visible: pulse.running && !DesignTokens.motionEnabled
  }

  // The travelling light, while motion is enabled.
  Item {
    id: light
    objectName: "pulseLight"
    width: Style.space(90)
    height: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    visible: pulse.running && DesignTokens.motionEnabled
    clip: false

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
          position: 0
          color: "transparent"
        }
        GradientStop {
          position: 0.35
          color: DesignTokens.accent
        }
        GradientStop {
          position: 0.7
          color: DesignTokens.strandEnd
        }
        GradientStop {
          position: 1
          color: "transparent"
        }
      }
    }

    NumberAnimation on x {
      running: light.visible
      loops: Animation.Infinite
      from: -light.width
      to: pulse.width
      duration: 2400
    }
  }
}
