// Aranea filament bar: a read-only strand bar for a level (Health's memory
// and disk usage, the OSD later). A hairline track whose lit part runs mint
// to violet, as FilamentSlider's lit strand does, with no node and no
// pointer input. Pure view: a value in, nothing out.
import QtQuick
import qs.Commons

Item {
  id: bar

  // The level, 0..1; anything outside is clamped.
  property real value: 0
  // The lit fraction of the track, value clamped to 0..1 (0 for NaN).
  readonly property real fraction: isFinite(bar.value) ? Math.max(0, Math.min(1, bar.value)) : 0
  // Colour of the unlit track.
  readonly property color trackColor: Util.alpha(DesignTokens.foreground, 0.15)
  // Thickness of the track and the lit part.
  readonly property real strandHeight: Math.max(2, Style.space(3))

  implicitWidth: Style.space(200)
  implicitHeight: bar.strandHeight

  Rectangle {
    id: track
    objectName: "filamentBarTrack"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: bar.strandHeight
    color: bar.trackColor
  }

  Rectangle {
    id: lit
    objectName: "filamentBarFill"
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: bar.width * bar.fraction
    height: bar.strandHeight
    visible: width > 0
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: DesignTokens.accent
      }
      GradientStop {
        position: 1
        color: DesignTokens.strandEnd
      }
    }
  }
}
