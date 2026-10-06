// Presentational, selectable details list for the polkit prompt.
// qmllint disable missing-property unqualified
import QtQuick
import "../araneadev.shared" as Aranea
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: details

  // Detail rows with key and value fields.
  property var rows: []
  // Font family used for both columns.
  property string fontFamily: Aranea.Typography.uiFamily
  // Main value text colour.
  property color foreground: Color.polkit.text
  // Muted key text colour.
  property color dim: Util.alpha(foreground, 0.58)
  // Selection highlight colour for copied values.
  property color accent: Color.polkit.accent
  // Letter spacing applied to keys.
  property real letterSpacing: 0.2

  // Forwards key events from selectable value fields to the owning prompt.
  signal keyPressed(var event)

  spacing: Style.space(4)

  Repeater {
    model: details.rows

    delegate: RowLayout {
      id: detailRow
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.space(10)

      Text {
        Layout.preferredWidth: Style.space(64)
        Layout.alignment: Qt.AlignTop
        textFormat: Text.PlainText
        text: detailRow.modelData.key
        color: details.dim
        font.family: details.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: details.letterSpacing
      }

      TextEdit {
        Layout.fillWidth: true
        textFormat: TextEdit.PlainText
        text: detailRow.modelData.value
        readOnly: true
        selectByMouse: true
        activeFocusOnPress: false
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        color: details.foreground
        selectionColor: Util.alpha(details.accent, 0.45)
        selectedTextColor: details.foreground
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.bodySmall
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          details.keyPressed(event)
        }
      }
    }
  }
}
