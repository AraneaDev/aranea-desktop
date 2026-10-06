// Dropdown header in the Filament style: a glyph (or an image mark, e.g.
// Agents' tool logo, falling back to the glyph until it loads) in a
// fixed-width slot,
// a bold title over an uppercase caption, and a trailing slot on the
// right content edge (audio puts its mute-all switch there).
import QtQuick
import qs.Commons

Item {
  id: header

  // Opt into proportional labels and quieter captions; legacy hosts retain their look.
  property bool refined: false
  // Overridable font for title and caption labels.
  property string labelFontFamily: refined ? Typography.uiFamily : Style.font.family

  // Leading glyph (a Nerd Font icon).
  property string glyph: ""
  // Optional image mark shown in the glyph slot instead of the glyph (an
  // SVG url); empty (the default) or an image that fails to load shows the
  // glyph as before.
  property string markSource: ""
  // Whether the image mark has loaded and replaces the glyph.
  readonly property bool markShown: header.markSource !== "" && markImage.status === Image.Ready
  // The glyph's colour; a host tints it by state (VPN's lit or failed
  // icon). The foreground leaves it as before.
  property color glyphColor: DesignTokens.foreground
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
    textFormat: Text.PlainText
    objectName: "headerGlyph"
    width: Style.space(28)
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignHCenter
    text: header.glyph
    visible: !header.markShown
    color: header.glyphColor
    font.family: Typography.iconFamily
    font.pixelSize: Style.font.display
  }
  Image {
    id: markImage
    objectName: "headerMark"
    anchors.centerIn: glyphText
    width: Style.font.display
    height: Style.font.display
    source: header.markSource
    sourceSize.width: Style.font.display * 2
    sourceSize.height: Style.font.display * 2
    fillMode: Image.PreserveAspectFit
    visible: header.markShown
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
      textFormat: Text.PlainText
      width: parent.width
      text: header.title
      elide: Text.ElideRight
      color: DesignTokens.foreground
      font.family: header.labelFontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      objectName: "headerCaption"
      text: header.refined ? header.caption : header.caption.toUpperCase()
      opacity: header.captionOpacity
      elide: Text.ElideRight
      color: Util.alpha(DesignTokens.foreground, 0.55)
      font.family: header.labelFontFamily
      font.pixelSize: Style.font.caption
      font.bold: !header.refined
      font.letterSpacing: header.refined ? 0 : 1.2
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
