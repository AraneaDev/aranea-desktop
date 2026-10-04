// Aranea filament bar: a read-only strand bar for a level (Health's memory
// and disk usage, the OSD later). A hairline track whose lit part runs mint
// to violet, as FilamentSlider's lit strand does, with no node and no
// pointer input. An optional pace tick (Agents' limit windows: how far
// through the window the clock is) marks a point on the track; hidden by
// default. Pure view: a value in, nothing out.
import QtQuick
import qs.Commons

Item {
  id: bar

  // The level, 0..1; anything outside is clamped.
  property real value: 0
  // The lit fraction of the track, value clamped to 0..1 (0 for NaN).
  readonly property real fraction: isFinite(bar.value) ? Math.max(0, Math.min(1, bar.value)) : 0
  // Where the pace tick sits, 0..1 (clamped); negative or NaN hides it
  // (the default), so a bar without a pace looks as before.
  property real pace: -1
  // Whether the pace tick shows.
  readonly property bool paceShown: isFinite(bar.pace) && bar.pace >= 0
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

  Rectangle {
    id: paceTick
    objectName: "filamentBarPace"
    visible: bar.paceShown
    width: Math.max(1, Style.space(2))
    height: bar.strandHeight * 3
    x: Math.max(0, Math.min(bar.width - paceTick.width, bar.width * Math.min(1, bar.pace) - paceTick.width / 2))
    anchors.verticalCenter: parent.verticalCenter
    color: Util.alpha(DesignTokens.foreground, 0.8)
  }
}
