// Quiet bounded group of related Settings controls; height follows its content.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "../araneadev.shared" as Aranea

Item {
  id: section
  // Optional heading for the setting group.
  property string title: ''
  // Controls laid out inside the section.
  default property alias content: body.data
  implicitHeight: body.implicitHeight + Style.space(24)
  implicitWidth: body.implicitWidth + Style.space(24)
  Rectangle {
    anchors.fill: parent
    radius: Style.space(4)
    color: Util.alpha(Commons.Color.foreground, 0.025)
    border.width: 1
    border.color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
    Rectangle {
      x: Style.space(12)
      width: Style.space(28)
      height: 1
      color: Aranea.DesignTokens.accent
      opacity: 0.55
    }
  }
  ColumnLayout {
    id: body
    x: Style.space(12)
    y: Style.space(12)
    width: Math.max(0, section.width - Style.space(24))
    spacing: Style.space(8)
    SettingsLabel {
      Layout.fillWidth: true
      visible: !!section.title
      text: section.title
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }
}
