// A section caption in the Aranea Displays dropdown: an uppercase muted
// title on the left and optional muted text on the right content edge
// (e.g. "BRIGHTNESS" with "72% · Bright").
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: caption

  // The caption, e.g. "BRIGHTNESS".
  property string title: ""
  // The trailing text, e.g. "72% · Bright".
  property string trailing: ""
  // The trailing text's objectName, for tests.
  property string trailingName: ""

  implicitHeight: Math.max(captionTitle.implicitHeight, captionTrailing.implicitHeight)

  Text {
    id: captionTitle
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: caption.title
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0
  }
  Text {
    id: captionTrailing
    objectName: caption.trailingName
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: caption.trailing
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Aranea.Typography.technicalFamily
    font.pixelSize: Style.font.caption
  }
}
