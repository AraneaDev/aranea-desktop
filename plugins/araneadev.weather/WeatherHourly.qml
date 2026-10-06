// The Aranea Weather dropdown's NEXT 24 H section: a caption with the
// "now → min → max" summary on the right, the temperature trace with its
// rain-chance bars (WeatherTrace), and the hour labels spread under it,
// the first on the left edge and the last on the right. Pure view: plain
// inputs in, nothing out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: hourly

  // The summary on the right of the caption, e.g. "17° → 11° → 19°".
  property string caption: ""
  // The hour labels under the trace, e.g. ["now", "03", "09"].
  property var labels: []
  // WeatherLogic.hourlyPoints's result, or null.
  property var points: null

  spacing: Style.space(4)

  Item {
    width: hourly.width
    implicitHeight: Math.max(title.implicitHeight, summary.implicitHeight)

    Text {
      id: title
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "NEXT 24 H"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0
    }
    Text {
      id: summary
      objectName: "hourlyCaption"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: hourly.caption
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
  WeatherTrace {
    width: hourly.width
    points: hourly.points
  }
  Item {
    id: hourRow
    width: hourly.width
    implicitHeight: Style.font.caption + Style.space(4)

    Repeater {
      model: hourly.labels
      Text {
        id: hourLabel
        required property var modelData
        required property int index
        objectName: "hourLabel"
        x: hourly.labels.length > 1 ? (hourRow.width - hourLabel.width) * hourLabel.index / (hourly.labels.length - 1) : 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String(hourLabel.modelData)
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
