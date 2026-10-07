// Aranea filament slider: a hairline strand whose lit part runs mint to
// violet, a glowing node as the handle, and an optional live-signal glow
// along the lit part. Left-drag or click sets the value; right-click emits
// rightClicked (audio mutes with it). The node stays inside the item, so
// the strand's right edge is the item's right edge. moved reports every
// step (a drag previews with it); committed reports where a drag or click
// was let go, or a wheel step landed. A busy slider (a change in flight)
// breathes its node; a clickGate refuses a press aimed before a layout
// shift, as FilamentSwitch's does. Opt-in (gateWheel), the wheel is refused
// the same way, and while wheelHeld (e.g. during a text-size reflow).
// The pointer over it draws the hover fill (HoverTint), only after a real
// move.
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
  // Whether a change is in flight: the node breathes until it settles.
  property bool busy: false
  // Opacity the busy animation drives, 0.45..1.
  property real pulseOpacity: 1
  // Optional item whose clickSettled() a left press must pass; a refused
  // press neither moves nor commits. null (default) never refuses one.
  // The wheel stays unguarded unless gateWheel; wheelBy() always does.
  property var clickGate: null
  // Opt-in, off by default: when true, a wheel step must also pass
  // clickGate's clickSettled() and is ignored while wheelHeld.
  property bool gateWheel: false
  // With gateWheel, ignore wheel steps while true (e.g. while the host's
  // layout is reflowing under the pointer).
  property bool wheelHeld: false
  // Optional host PointerMoveGate (qs.Ui) carrying layoutChangedAt: a
  // layout shift drops the hover fill.
  property var pointerGate: null
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
  // Emitted with the final value when a drag or click is let go, and after
  // a wheel step.
  signal committed(real value)

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
    committed(next)
  }

  // Whether a real wheel step may move the slider: always without
  // gateWheel; with it, never while wheelHeld or before clickGate settles.
  function wheelAllowed() {
    if (!gateWheel)
      return true
    if (wheelHeld)
      return false
    return !clickGate || clickGate.clickSettled()
  }

  onValueChanged: if (!dragging)
    liveValue = value
  implicitWidth: Style.space(200)
  implicitHeight: Style.space(20)

  HoverTint {
    active: slider.interactive
    pointerGate: slider.pointerGate
  }
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
    opacity: slider.busy ? (DesignTokens.motionEnabled ? slider.pulseOpacity : 0.7) : 1
    Behavior on x {
      enabled: !slider.dragging && DesignTokens.motionEnabled
      NumberAnimation {
        duration: DesignTokens.feedbackDuration
        easing.type: Easing.OutCubic
      }
    }
  }

  // Breathing while busy; static at 0.7 when motion is disabled.
  SequentialAnimation {
    objectName: "busyPulse"
    loops: Animation.Infinite
    running: slider.busy && DesignTokens.motionEnabled
    NumberAnimation {
      target: slider
      property: "pulseOpacity"
      to: 0.45
      duration: 1200
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: slider
      property: "pulseOpacity"
      to: 1
      duration: 1200
      easing.type: Easing.InOutSine
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
      if (slider.clickGate && !slider.clickGate.clickSettled())
        return
      slider.dragging = true
      slider.setFromX(mouse.x)
    }
    onPositionChanged: function (mouse) {
      if (slider.dragging)
        slider.setFromX(mouse.x)
    }
    onReleased: function (mouse) {
      if (mouse.button !== Qt.LeftButton || !slider.dragging)
        return
      var landed = slider.liveValue
      slider.dragging = false
      slider.liveValue = slider.value
      slider.committed(landed)
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
      if (slider.wheelAllowed())
        slider.wheelBy(wheel.angleDelta.y)
      wheel.accepted = true
    }
  }
}
