// Dropdown header in the Filament style: a glyph in a fixed-width slot,
// a bold title over an uppercase caption, and a trailing slot on the
// right content edge (audio puts its mute-all switch there).
import QtQuick
import qs.Commons

Item {
  id: header

  // Leading glyph (a Nerd Font icon).
  property string glyph: ""
  // Title, e.g. "Audio".
  property string title: ""
  // Caption under the title, shown uppercase.
  property string caption: ""
  // Opacity of the caption alone, for a host that fades it between values
  // (Bluetooth's rotating phrases). 1 leaves it as before.
  property real captionOpacity: 1
  // Trailing content, anchored to the right edge.
  default property alias trailing: trailingSlot.data

  implicitHeight: Math.max(glyphText.implicitHeight, labels.implicitHeight, trailingSlot.childrenRect.height)

  Text {
    id: glyphText
    width: Style.space(28)
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignHCenter
    text: header.glyph
    color: DesignTokens.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.display
  }
  Column {
    id: labels
    anchors.left: glyphText.right
    anchors.leftMargin: Style.space(12)
    anchors.right: trailingSlot.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)
    Text {
      width: parent.width
      text: header.title
      elide: Text.ElideRight
      color: DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      width: parent.width
      objectName: "headerCaption"
      text: header.caption.toUpperCase()
      opacity: header.captionOpacity
      elide: Text.ElideRight
      color: Util.alpha(DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
  }
  Item {
    id: trailingSlot
    objectName: "headerTrailing"
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }
}
