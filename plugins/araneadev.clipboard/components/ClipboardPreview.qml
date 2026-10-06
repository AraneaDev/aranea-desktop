// Presentational preview of the currently selected clipboard entry.
// qmllint disable missing-property
import QtQuick
import "../../araneadev.shared" as Aranea
import qs.Commons

Item {
  id: preview

  // True while a secret remains hidden.
  property bool masked: false
  // Guidance shown below the masked secret placeholder.
  property string secretHint: "SPACE TO REVEAL"
  // Optional remaining secret lifetime label.
  property string secretExpiry: ""
  // Text/code/link content to show when unmasked.
  property string textValue: ""
  // Image URL to show when the entry is an image.
  property string imageSource: ""
  // Human-readable colour value.
  property string colourText: ""
  // Parsed colour swatch value.
  property string swatch: ""
  // True when textValue should use the monospace code style.
  property bool isCode: false
  // Padding from the containing picker card.
  property int contentMargin: Style.spacing.panelPadding
  // Font family supplied by the clipboard window.
  property string fontFamily: Aranea.Typography.uiFamily
  // Main preview text colour.
  property color foreground: Color.menu.text
  // Preview border colour.
  property color borderColor: Color.menu.border
  // Corner radius for the swatch.
  property real cornerRadius: Style.cornerRadius
  // Cap top the preview's first line aligns to.
  property real firstLineTop: 0

  // Ink metrics of the preview text's own font.
  TextMetrics {
    id: previewInk
    font: previewText.font
    text: "H"
  }

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.normalBorderWidth
    color: Util.alpha(preview.borderColor, 0.28)
  }

  Column {
    visible: preview.masked
    anchors.left: parent.left
    anchors.leftMargin: preview.contentMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: "•••••••••••••••• · secret"
      color: preview.foreground
      font.family: preview.fontFamily
      font.pixelSize: Style.font.title
    }
    Text {
      textFormat: Text.PlainText
      text: preview.secretHint + (preview.secretExpiry ? "  ·  " + preview.secretExpiry.toUpperCase() : "")
      color: Util.alpha(preview.foreground, 0.5)
      font.family: preview.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.20
    }
  }

  Column {
    visible: !preview.masked && preview.colourText.length > 0
    anchors.left: parent.left
    anchors.leftMargin: preview.contentMargin
    anchors.top: parent.top
    anchors.topMargin: preview.firstLineTop
    spacing: Style.space(10)

    Rectangle {
      visible: preview.swatch.length > 0
      width: Style.space(120)
      height: Style.space(80)
      radius: preview.cornerRadius
      color: preview.swatch.length > 0 ? preview.swatch : "transparent"
      border.width: 1
      border.color: Util.alpha(preview.foreground, 0.25)
    }
    Text {
      textFormat: Text.PlainText
      text: preview.colourText
      color: preview.foreground
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: Style.font.title
    }
  }

  Text {
    id: previewText
    visible: !preview.masked && !preview.imageSource && preview.colourText.length === 0
    anchors.fill: parent
    anchors.leftMargin: preview.contentMargin
    anchors.topMargin: Math.max(0, preview.firstLineTop - (previewText.baselineOffset + previewInk.tightBoundingRect.y))
    textFormat: Text.PlainText
    text: preview.textValue
    color: preview.foreground
    font.family: preview.isCode ? Aranea.Typography.technicalFamily : preview.fontFamily
    font.pixelSize: preview.isCode ? Style.font.body : Style.font.title
    wrapMode: Text.WrapAnywhere
    elide: Text.ElideRight
    verticalAlignment: Text.AlignTop
  }

  Image {
    visible: !preview.masked && preview.imageSource.length > 0
    anchors.fill: parent
    anchors.leftMargin: preview.contentMargin
    anchors.topMargin: preview.firstLineTop
    source: preview.imageSource
    fillMode: Image.PreserveAspectFit
    verticalAlignment: Image.AlignTop
    asynchronous: true
    smooth: true
  }
}
