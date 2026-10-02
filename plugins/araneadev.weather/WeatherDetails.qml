// The Aranea Weather dropdown's details grid: the view's detail cells two
// to a row, each a muted label on the left and its value on the cell's
// right edge, so the second column ends on the content edge. The wind
// cell adds an arrow turned to where the wind blows (its rotation applied
// as given, even past 360) and its compass label; the pressure cell adds
// its trend arrow. Read-only. Pure view: plain inputs in, nothing out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: details

  // Detail cells: [{key, label, value, arrow? (degrees), dir?, trend?}].
  property var cells: []
  // The gap between the two columns, in px.
  readonly property real gap: Style.space(12)
  // Each cell's width: the row split in two around the gap.
  readonly property real cellWidth: (details.width - details.gap) / 2

  spacing: Style.space(4)

  Repeater {
    model: Math.ceil(details.cells.length / 2)
    Row {
      id: pair
      required property int index
      spacing: details.gap

      Repeater {
        model: Math.min(2, details.cells.length - pair.index * 2)
        Item {
          id: cell
          required property int index
          // This cell's detail.
          readonly property var detail: details.cells[pair.index * 2 + cell.index] || ({})
          objectName: "detailCell"
          width: details.cellWidth
          implicitHeight: Math.max(label.implicitHeight, value.implicitHeight)

          Text {
            id: label
            objectName: "detailLabel"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: cell.detail.label || ""
            color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Row {
            id: value
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              objectName: "detailValue"
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: cell.detail.value || ""
              color: Aranea.DesignTokens.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              objectName: "windArrow"
              anchors.verticalCenter: parent.verticalCenter
              visible: typeof cell.detail.arrow === "number" && isFinite(cell.detail.arrow)
              text: "↑"
              rotation: visible ? cell.detail.arrow : 0
              color: Aranea.DesignTokens.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              objectName: "windDir"
              anchors.verticalCenter: parent.verticalCenter
              visible: !!cell.detail.dir
              textFormat: Text.PlainText
              text: cell.detail.dir || ""
              color: Aranea.DesignTokens.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              objectName: "detailTrend"
              anchors.verticalCenter: parent.verticalCenter
              visible: !!cell.detail.trend
              textFormat: Text.PlainText
              text: cell.detail.trend || ""
              color: Aranea.DesignTokens.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
