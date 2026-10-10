// Shared page hierarchy for compact Settings, separate from the window brand.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: header
  // Current Settings page name.
  property string title: ''
  // Brief explanation below the title.
  property string description: ''
  spacing: Style.space(4)
  UiLabel {
    Layout.fillWidth: true
    text: header.title
    font.pixelSize: Style.font.heading
    font.bold: true
  }
  UiLabel {
    Layout.fillWidth: true
    visible: !!header.description
    text: header.description
    opacity: 0.75
  }
}
