// Header of the Aranea audio dropdown: the shared DropdownHeader with a
// mute-all switch in its trailing slot. Pure view: plain inputs in,
// signals out. (glyph, title and caption come from DropdownHeader.)
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Aranea.DropdownHeader {
  id: header

  // Mood caption under the title, e.g. "Cranked up".
  property string mood: ""
  // Whether any channel is unmuted.
  property bool anyAudible: true
  // Whether the keyboard cursor is on the mute-all switch.
  property bool hasCursor: false

  // Emitted when the mute-all switch is toggled.
  signal toggleAll
  // Emitted when the pointer enters the switch.
  signal entered

  title: "Audio"
  caption: header.mood

  Row {
    spacing: Style.space(8)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "MUTE ALL"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Aranea.FilamentSwitch {
      anchors.verticalCenter: parent.verticalCenter
      checked: header.anyAudible
      hasCursor: header.hasCursor
      onToggled: header.toggleAll()
      HoverHandler {
        onHoveredChanged: if (hovered)
          header.entered()
      }
    }
  }
}
