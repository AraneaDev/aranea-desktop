// Compact activity rows keep commands explicit and full history one step deeper.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: summary
  // Readable section heading.
  property string title: ''
  // Descriptive section destination remains useful when no rows exist.
  property string detailsLabel: 'Details'
  // Single-line guidance for an empty section.
  property string emptyHint: ''
  // Compact rows with immutable action targets.
  property var rows: []
  // Capture boundary refuses every external action.
  property bool displayOnly: false
  // An unresolved operation prevents another submission.
  property bool pending: false
  // Native command availability gates Run and Start.
  property bool executionAvailable: true
  // Local expansion reveals optional history or file paths.
  property bool expanded: false
  // Pointer identity survives delegate replacement during background refresh.
  property var pressedTarget: null
  // Shared pointer settlement gate for moving content.
  property var pointerGate: null
  // Explicit row effect carrying its immutable target.
  signal requested(string method, var target)
  // Open deeper information without executing saved commands.
  signal detailsRequested(var target)
  spacing: Style.space(8)
  RowLayout {
    Layout.fillWidth: true
    Aranea.UiLabel {
      text: summary.title
      font.bold: true
      font.pixelSize: Style.font.body
      Layout.fillWidth: true
    }
    Aranea.ActionButton {
      text: summary.detailsLabel
      variant: 'quiet'
      pointerGate: summary.pointerGate
      onClicked: summary.detailsRequested({})
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: summary.rows.length === 0
    text: summary.emptyHint
    opacity: 0.65
  }
  Repeater {
    model: summary.expanded ? summary.rows : summary.rows.slice(0, 3)
    ColumnLayout {
      id: row
      required property var modelData
      Layout.fillWidth: true
      Aranea.UiLabel {
        Layout.fillWidth: true
        text: row.modelData.title + ' · ' + row.modelData.status
        color: row.modelData.attention ? Aranea.DesignTokens.urgent : Commons.Color.foreground
      }
      Aranea.UiLabel {
        Layout.fillWidth: true
        text: row.modelData.detail
        opacity: 0.6
        font.pixelSize: Style.font.caption
        ToolTip.visible: detailHover.hovered && !!row.modelData.tooltip
        ToolTip.text: row.modelData.tooltip || ''
        HoverHandler {
          id: detailHover
        }
      }
      Flow {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Repeater {
          model: row.modelData.controls
          Aranea.ActionButton {
            id: control
            required property var modelData
            text: modelData.label
            enabled: !summary.displayOnly && !summary.pending && (modelData.method !== 'start' || summary.executionAvailable)
            pointerGate: summary.pointerGate
            onPressed: summary.pressedTarget = JSON.stringify([modelData.method, row.modelData.target])
            onPressCanceled: summary.pressedTarget = null
            onClicked: {
              var old = summary.pressedTarget
              summary.pressedTarget = null
              if (old === null || old === JSON.stringify([modelData.method, row.modelData.target]))
                summary.requested(modelData.method, row.modelData.target)
            }
          }
        }
        Aranea.ActionButton {
          text: 'Details'
          variant: 'quiet'
          pointerGate: summary.pointerGate
          onClicked: summary.detailsRequested(row.modelData.target)
        }
      }
    }
  }
  Aranea.ActionButton {
    visible: summary.rows.length > 3
    text: summary.expanded ? 'Show less' : 'Show all (' + summary.rows.length + ')'
    pointerGate: summary.pointerGate
    onClicked: summary.expanded = !summary.expanded
  }
}
