// Plain-text settings typography using the existing host menu font.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import qs.Commons

Text {
  textFormat: Text.PlainText
  font.family: Style.font.menuFamily
  font.pixelSize: Style.font.body
  color: Color.foreground
  wrapMode: Text.Wrap
}
