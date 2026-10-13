// Small non-interactive badge inside the Audio bar button. Idle microphones
// never consume a bar slot; connected capture and source mute are separate.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Rectangle {
  id: badge
  // A live recorder stream owns the input; source running alone does not count.
  property bool captureActive: false
  // The selected microphone is muted while capture remains connected.
  property bool muted: false
  // Keep microphone activity and source mute visually distinct.
  readonly property string glyph: String.fromCodePoint(muted ? 0xF036D : 0xF036C)

  visible: captureActive
  width: Style.space(14)
  height: width
  radius: width / 2
  color: Aranea.DesignTokens.background
  Text {
    anchors.centerIn: parent
    text: badge.glyph
    color: badge.muted ? Aranea.DesignTokens.attention : Aranea.DesignTokens.accent
    font.family: Aranea.Typography.iconFamily
    font.pixelSize: Style.space(11)
  }
}
