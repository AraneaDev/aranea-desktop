// Shared visual surface adapter. It keeps Aranea panels on the host shell's
// BorderSurface implementation while centralizing the common border contract.
import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: card

  property string surface: "popups"
  property color borderColor: Color.popups.border
  property real borderAlpha: 1.0
  property int borderWidth: Style.normalBorderWidth
  property color fillColor: Color.popups.background
  property var borderSpecOverride: null
  property int contentPadding: 0
  property real cornerRadius: Style.cornerRadius
  property bool clipContent: false
  default property alias content: body.data

  color: card.fillColor
  radius: card.cornerRadius
  padding: card.contentPadding
  clip: card.clipContent
  borderSpec: card.borderSpecOverride !== null ? card.borderSpecOverride : Border.surfaceSpec(card.surface, "border", card.borderColor, Math.max(0, card.borderWidth), "border-alpha")

  Item {
    id: body
    anchors.fill: parent
  }
}
