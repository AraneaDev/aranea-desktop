// Shared visual surface adapter. It keeps Aranea panels on the host shell's
// BorderSurface implementation while centralizing the common border contract.
// qmllint disable missing-property
import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: card

  // Host surface family used to resolve the border specification.
  property string surface: "popups"
  // Border colour when no override is supplied.
  property color borderColor: Color.popups.border
  // Border opacity multiplier.
  property real borderAlpha: 1.0
  // Border width when no override is supplied.
  property int borderWidth: DesignTokens.borderWidth
  // Card fill colour.
  property color fillColor: Color.popups.background
  // Optional complete border specification.
  property var borderSpecOverride: null
  // Padding applied around card content.
  property int contentPadding: 0
  // Card corner radius.
  property real cornerRadius: DesignTokens.cornerRadius
  // Whether card content is clipped to its bounds.
  property bool clipContent: false
  // Content rendered inside the card.
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
