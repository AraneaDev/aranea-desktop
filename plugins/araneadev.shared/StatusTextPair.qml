// Shared title/subtitle stack for compact status rows.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: pair
  // Primary row title.
  property string title: ""
  // Secondary row subtitle.
  property string subtitle: ""
  // Title colour.
  property color titleColor: Color.popups.text
  // Subtitle colour.
  property color subtitleColor: Color.popups.text
  // Subtitle opacity.
  property real subtitleOpacity: 0.55
  // Whether the title uses a bold weight.
  property bool titleBold: true
  // Title font size.
  property int titleSize: Style.font.subtitle
  // Subtitle font size.
  property int subtitleSize: Style.font.body
  // Subtitle elision mode.
  property int subtitleElide: Text.ElideNone
  // Font family for both labels.
  property string fontFamily: Style.font.family
  spacing: 0

  Text {
    text: pair.title
    color: pair.titleColor
    font.bold: pair.titleBold
    font.pixelSize: pair.titleSize
    font.family: pair.fontFamily
    Layout.fillWidth: true
  }

  Text {
    text: pair.subtitle
    color: pair.subtitleColor
    opacity: pair.subtitleOpacity
    font.pixelSize: pair.subtitleSize
    font.family: pair.fontFamily
    elide: pair.subtitleElide
    Layout.fillWidth: true
  }
}
