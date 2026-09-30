// Aranea filament slider: a hairline strand whose lit part runs mint to
// violet, a glowing node as the handle, and an optional live-signal glow
// along the lit part. Left-drag or click sets the value; right-click emits
// rightClicked (audio mutes with it). The node stays inside the item, so
// the strand's right edge is the item's right edge.
import QtQuick
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
  // Whether the slider takes pointer input.
  property bool interactive: true
  // Value shown while dragging; follows value otherwise.
  property real liveValue: value
  // Whether a drag is in progress.
  property bool dragging: false
  // Lit fraction of the strand, 0..1.
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / Math.max(0.0001, maximum - minimum)))
  // Colour of the unlit strand and of everything when muted.
  readonly property color quietColor: Util.alpha(DesignTokens.foreground, 0.28)

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

  onValueChanged: if (!dragging)
    liveValue = value
  implicitWidth: Style.space(200)
  implicitHeight: Style.space(20)

  Rectangle {
    id: strand
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(1, Style.spacing.hairline)
    color: slider.quietColor
  }

  Rectangle {
    id: glow
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: lit.width * Math.max(0, Math.min(1, slider.level))
    height: Style.space(6)
    radius: height / 2
    color: Util.alpha(DesignTokens.accent, 0.35)
    visible: !slider.muted && slider.level > 0
  }

  Rectangle {
    id: lit
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: node.x + node.width / 2
    height: Math.max(2, Style.space(2))
    radius: height / 2
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: slider.muted ? slider.quietColor : DesignTokens.accent
      }
      GradientStop {
        position: 1
        color: slider.muted ? slider.quietColor : DesignTokens.accentSecondary
      }
    }
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
    anchors.fill: parent
    enabled: slider.interactive
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
    onClicked: function (mouse) {
      if (mouse.button === Qt.RightButton)
        slider.rightClicked()
    }
  }
}
