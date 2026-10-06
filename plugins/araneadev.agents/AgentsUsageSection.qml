// A token usage section of the Aranea agents dropdown: TOKENS BY DAY (one
// row per day for the last week, today in bold, label, strand and value
// on one line) or TOKENS BY MODEL (stacked: name and value over the
// strand, each scaled to the heaviest model). Every bar is an
// Aranea.FilamentBar strand. Hovering a row shows its detail (today's
// prompts and sessions, a model's input/output/cache split) in a tooltip
// and reports the hover; with a pointerGate only a real pointer move
// counts, so a row sliding under a still pointer reports nothing. Pure
// view. The Repeater runs over the row count, so a refresh that rebuilds
// the rows never recreates a delegate.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: section

  // The caption, e.g. "TOKENS BY DAY".
  property string caption: ""
  // Rows: [{key, label, fraction, value, today, detail}]; today only for
  // day rows.
  property var rows: []
  // Whether rows stack the strand under the label and value (models)
  // rather than between them (days).
  property bool stacked: false
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from a row
  // moving under a still pointer.
  property var pointerGate: null

  // Emitted when the pointer really moves onto row INDEX.
  signal rowHovered(int index)

  // The row at INDEX, or null when out of range.
  function rowAt(index) {
    return repeater.itemAt(index)
  }

  visible: (section.rows || []).length > 0
  spacing: Style.space(8)

  Text {
    textFormat: Text.PlainText
    visible: section.caption !== ""
    text: section.caption
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }

  Repeater {
    id: repeater
    model: (section.rows || []).length

    Item {
      id: usageRow
      required property int index
      // This row's data, read from the live array.
      readonly property var row: section.rows[usageRow.index] || ({
          key: "",
          label: "",
          fraction: 0,
          value: "",
          today: false,
          detail: ""
        })
      // Whether this is today's row (bold, full foreground).
      readonly property bool today: !!usageRow.row.today
      // Whether the pointer is over the row.
      readonly property alias hovered: hover.hovered
      // Whether the row's detail tooltip shows.
      readonly property bool detailShown: hover.hovered && String(usageRow.row.detail || "") !== ""
      // Label and value colour: full for today and models, muted otherwise.
      readonly property color textColor: usageRow.today || section.stacked ? Aranea.DesignTokens.foreground : Util.alpha(Aranea.DesignTokens.foreground, 0.55)

      objectName: "usageRow"
      width: section.width
      implicitHeight: section.stacked ? labelText.implicitHeight + Style.space(4) + strand.height : Math.max(labelText.implicitHeight, valueText.implicitHeight) + Style.space(2)

      Text {
        id: labelText
        textFormat: Text.PlainText
        objectName: "usageLabel"
        anchors.left: parent.left
        anchors.top: section.stacked ? parent.top : undefined
        anchors.verticalCenter: section.stacked ? undefined : parent.verticalCenter
        width: section.stacked ? parent.width - valueText.width - Style.space(8) : Style.space(52)
        text: usageRow.row.label || ""
        elide: Text.ElideRight
        color: usageRow.textColor
        font.family: Style.font.family
        font.pixelSize: section.stacked ? Style.font.body : Style.font.caption
        font.bold: usageRow.today
      }
      Text {
        id: valueText
        textFormat: Text.PlainText
        objectName: "usageValue"
        anchors.right: parent.right
        anchors.top: section.stacked ? parent.top : undefined
        anchors.verticalCenter: section.stacked ? undefined : parent.verticalCenter
        width: section.stacked ? implicitWidth : Style.space(60)
        horizontalAlignment: Text.AlignRight
        text: usageRow.row.value || ""
        color: usageRow.textColor
        font.family: Style.font.family
        font.pixelSize: section.stacked ? Style.font.body : Style.font.caption
        font.bold: usageRow.today || section.stacked
      }
      Aranea.FilamentBar {
        id: strand
        objectName: "usageBar"
        x: section.stacked ? 0 : labelText.width + Style.space(8)
        y: section.stacked ? labelText.implicitHeight + Style.space(4) : (usageRow.height - height) / 2
        width: section.stacked ? usageRow.width : usageRow.width - labelText.width - valueText.width - Style.space(18)
        value: Number(usageRow.row.fraction) || 0
      }
      HoverHandler {
        id: hover
        onHoveredChanged: if (hovered && !section.pointerGate)
          section.rowHovered(usageRow.index)
        onPointChanged: if (section.pointerGate && hover.hovered && section.pointerGate.moved(hover.parent, {
          x: hover.point.position.x,
          y: hover.point.position.y
        }))
          section.rowHovered(usageRow.index)
      }
      PanelToolTip {
        objectName: "usageTip"
        visible: usageRow.detailShown
        text: String(usageRow.row.detail || "")
      }
    }
  }
}
