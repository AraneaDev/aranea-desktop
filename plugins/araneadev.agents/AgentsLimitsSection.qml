// The LIMITS section of the Aranea agents dropdown: one row per limit
// window (session, weekly, a model's weekly), each with its title, the
// percent used, an Aranea.FilamentBar strand with the pace tick, and the
// "Resets in …" countdown. Warning levels tint the percent text, as
// Health tints its values: amber near the cap, urgent at it. Pure view.
// The Repeater runs over the row count, so a refresh that rebuilds the
// rows never recreates a delegate.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section

  // Limit rows: [{key, label, fraction, percent, tone, pace, resets}],
  // tone "plain", "attention" or "urgent", pace 0..1 or -1 for none.
  property var rows: []

  // The percent text's colour for TONE.
  function toneColor(tone: string): color {
    return tone === "urgent" ? Aranea.DesignTokens.urgent : (tone === "attention" ? Aranea.DesignTokens.attention : Aranea.DesignTokens.foreground)
  }

  objectName: "limitsSection"
  visible: (section.rows || []).length > 0
  spacing: Style.space(8)

  Text {
    textFormat: Text.PlainText
    text: "LIMITS"
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0
  }

  Repeater {
    model: (section.rows || []).length

    Column {
      id: limitRow
      required property int index
      // This row's window, read from the live array.
      readonly property var limit: section.rows[limitRow.index] || ({
          key: "",
          label: "",
          fraction: 0,
          percent: "",
          tone: "plain",
          pace: -1,
          resets: ""
        })

      objectName: "limitRow"
      width: section.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: Math.max(limitLabel.implicitHeight, limitPercent.implicitHeight)
        Text {
          id: limitLabel
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: limitPercent.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          // A model-scoped window is titled after its model, and those
          // names run long, so the title gives way first.
          text: limitRow.limit.label || ""
          elide: Text.ElideRight
          color: Aranea.DesignTokens.foreground
          font.family: Aranea.Typography.uiFamily
          font.pixelSize: Style.font.body
        }
        Text {
          id: limitPercent
          textFormat: Text.PlainText
          objectName: "limitPercent"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: limitRow.limit.percent || ""
          color: section.toneColor(String(limitRow.limit.tone || ""))
          font.family: Aranea.Typography.technicalFamily
          // The host exposes font tokens as a dynamic QObject.
          // qmllint disable missing-property
          font.pixelSize: Style.font.subtitle
          // qmllint enable missing-property
          font.bold: true
        }
      }
      Aranea.FilamentBar {
        objectName: "limitBar"
        width: parent.width
        value: Number(limitRow.limit.fraction) || 0
        pace: typeof limitRow.limit.pace === "number" ? limitRow.limit.pace : -1
      }
      Text {
        textFormat: Text.PlainText
        objectName: "limitResets"
        width: parent.width
        visible: text !== ""
        text: limitRow.limit.resets || ""
        elide: Text.ElideRight
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
