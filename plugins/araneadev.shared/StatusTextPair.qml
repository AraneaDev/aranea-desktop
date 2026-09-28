// Shared title/subtitle stack for compact status rows.
import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: pair
  property string title: ""
  property string subtitle: ""
  property color titleColor: Color.popups.text
  property color subtitleColor: Color.popups.text
  property real subtitleOpacity: 0.55
  property bool titleBold: true
  property int titleSize: Style.font.subtitle
  property int subtitleSize: Style.font.body
  property int subtitleElide: Text.ElideNone
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
