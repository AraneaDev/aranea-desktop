// The Aranea Weather dropdown's forecast days: one equal-width bordered
// cell per day (stock's 4-day forecast), keyed by date, each with its day
// label, condition glyph, and the high beside the muted low. Read-only.
// Pure view: plain inputs in, nothing out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Row {
  id: days

  // Day cells: [{key (the date), label, glyph, hi, lo}].
  property var rows: []
  // Each cell's width: the row split evenly.
  readonly property real cellWidth: (days.width - days.spacing * (Math.max(1, days.rows.length) - 1)) / Math.max(1, days.rows.length)

  spacing: Style.space(6)

  Repeater {
    model: days.rows
    Item {
      id: cell
      required property var modelData
      // The day's date key.
      readonly property string key: cell.modelData.key || ""
      objectName: "dayCell"
      width: days.cellWidth
      implicitHeight: content.implicitHeight + Style.space(12)

      Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
      }
      Column {
        id: content
        anchors.centerIn: parent
        spacing: Style.space(2)

        Text {
          objectName: "dayLabel"
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: cell.modelData.label || ""
          color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
          font.family: Aranea.Typography.uiFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          objectName: "dayGlyph"
          anchors.horizontalCenter: parent.horizontalCenter
          text: cell.modelData.glyph || ""
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.82)
          font.family: Aranea.Typography.iconFamily
          font.pixelSize: Style.font.display
        }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(4)

          Text {
            objectName: "dayHi"
            textFormat: Text.PlainText
            text: cell.modelData.hi || ""
            color: Aranea.DesignTokens.foreground
            font.family: Aranea.Typography.technicalFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            objectName: "dayLo"
            textFormat: Text.PlainText
            text: cell.modelData.lo || ""
            color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
            font.family: Aranea.Typography.technicalFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
