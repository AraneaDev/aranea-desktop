// Plain-text UI labels use the desktop sans-serif alias; technical values retain monospace.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import "../araneadev.shared" as Aranea
import qs.Commons

Text {
  // Technical observations and values retain the desktop monospace family.
  property bool technical: false
  textFormat: Text.PlainText
  font.family: technical ? Aranea.Typography.technicalFamily : Aranea.Typography.uiFamily
  font.pixelSize: Style.font.caption
  color: Color.foreground
  wrapMode: Text.Wrap
}
