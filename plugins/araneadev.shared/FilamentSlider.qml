// Aranea filament slider: a hairline strand whose lit part runs mint to
// violet, a glowing node as the handle, and an optional live-signal glow
// along the lit part. Left-drag or click sets the value; right-click emits
// rightClicked (audio mutes with it). The node stays inside the item, so
// the strand's right edge is the item's right edge.
import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: slider

  // Current value, between minimum and maximum.
  property real value: 0
  // Lowest value.
  property real minimum: 0
  // Highest value (audio streams use 1.5).
  property real maximum: 1
  // Live signal level, 0..1, drawn as a glow along the lit part.
  property real level: 0
  // Whether the channel is muted: strand and node turn grey.
  property bool muted: false
  // How far one mouse-wheel notch moves the value (stock PanelSlider's step).
  property real step: 0.05
  // Whether the slider takes pointer input.
  property bool interactive: true
  // Value shown while dragging; follows value otherwise.
  property real liveValue: value
  // Whether a drag is in progress.
  property bool dragging: false
  // Lit fraction of the strand, 0..1.
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / Math.max(0.0001, maximum - minimum)))
  // Colour of the lit strand and the node when muted.
  readonly property color quietColor: Util.alpha(DesignTokens.foreground, 0.22)
  // Colour of the unlit strand.
  readonly property color strandColor: Util.alpha(DesignTokens.foreground, 0.15)
  // Thickness of the strand, lit and unlit.
  readonly property real strandHeight: Math.max(2, Style.space(2))

  // Emitted with the new value while dragging or on click.
  signal moved(real value)
  // Emitted on right-click anywhere on the slider.
  signal rightClicked

  // Sets the value from an x position in the item, as a click would.
  function setFromX(x) {
    var span = Math.max(1, width - node.width)
    var fraction = Math.max(0, Math.min(1, (x - node.width / 2) / span))
    var next = minimum + fraction * (maximum - minimum)
    liveValue = next
    moved(next)
  }

  // Steps the value one notch up or down by a wheel ANGLE (angleDelta.y),
  // clamped, as stock's PanelSlider does; a zero angle does nothing.
  function wheelBy(angle) {
    if (angle === 0)
      return
    var next = Math.max(minimum, Math.min(maximum, liveValue + (angle > 0 ? step : -step)))
    liveValue = next
    moved(next)
  }

  onValueChanged: if (!dragging)
    liveValue = value
  implicitWidth: Style.space(200)
  implicitHeight: Style.space(20)

  Rectangle {
    id: strand
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: slider.strandHeight
    color: slider.strandColor
  }

  // The live signal: a soft mint glow fading in from the left, as long as
  // the level along the lit strand. Two stacked bands stand in for a blur.
  Item {
    id: glow
    objectName: "filamentGlow"
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: lit.width * Math.max(0, Math.min(1, slider.level))
    height: Style.space(6)
    visible: !slider.muted && width > 0
    Rectangle {
      anchors.fill: parent
      radius: height / 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
          position: 0
          color: "transparent"
        }
        GradientStop {
          position: 1
          color: Util.alpha(DesignTokens.accent, 0.25)
        }
      }
    }
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height / 2
      radius: height / 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
          position: 0
          color: "transparent"
        }
        GradientStop {
          position: 1
          color: Util.alpha(DesignTokens.accent, 0.55)
        }
      }
    }
  }

  Rectangle {
    id: lit
    objectName: "filamentLit"
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: node.x + node.width / 2
    height: slider.strandHeight
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: slider.muted ? slider.quietColor : DesignTokens.accent
      }
      GradientStop {
        position: 1
        color: slider.muted ? slider.quietColor : DesignTokens.strandEnd
      }
    }
  }

  // The node's soft mint glow; none when muted.
  RectangularShadow {
    x: node.x
    y: node.y
    width: node.width
    height: node.height
    radius: node.radius
    blur: Style.space(10)
    color: Util.alpha(DesignTokens.accent, 0.8)
    visible: !slider.muted
  }

  Rectangle {
    id: node
    objectName: "filamentNode"
    width: Style.space(12)
    height: width
    radius: width / 2
    anchors.verticalCenter: parent.verticalCenter
    x: Math.max(0, Math.min(slider.width - width, (slider.width - width) * slider.progress))
    color: Color.background
    border.width: Math.max(1, Style.space(2))
    border.color: slider.muted ? slider.quietColor : DesignTokens.accent
    Behavior on x {
      enabled: !slider.dragging && DesignTokens.motionEnabled
      NumberAnimation {
        duration: 140
        easing.type: Easing.OutCubic
      }
    }
  }

  MouseArea {
    objectName: "filamentMouse"
    anchors.fill: parent
    enabled: slider.interactive
    // Keep a drag that drifts vertically from turning into a flick of the
    // scrolling dropdown around the slider.
    preventStealing: true
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: function (mouse) {
      if (mouse.button !== Qt.LeftButton)
        return
      slider.dragging = true
      slider.setFromX(mouse.x)
    }
    onPositionChanged: function (mouse) {
      if (slider.dragging)
        slider.setFromX(mouse.x)
    }
    onReleased: function (mouse) {
      if (mouse.button !== Qt.LeftButton)
        return
      slider.dragging = false
      slider.liveValue = slider.value
    }
    onCanceled: {
      slider.dragging = false
      slider.liveValue = slider.value
    }
    onClicked: function (mouse) {
      if (mouse.button === Qt.RightButton)
        slider.rightClicked()
    }
    onWheel: function (wheel) {
      slider.wheelBy(wheel.angleDelta.y)
      wheel.accepted = true
    }
  }
}
