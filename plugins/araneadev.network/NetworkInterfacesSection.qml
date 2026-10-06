// The Interfaces section of the Aranea Network dropdown: an "INTERFACES"
// caption with the count, and one read-only NodeDeviceRow per real link
// (its node lit while connected). Shown only with two or more links. Pure
// view: rows in, nothing out (not in the keyboard chain, no actions).
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section

  // Interface rows from NetworkLogic.interfaceRows:
  // [{key, glyph, label, detail, active}].
  property var rows: []

  objectName: "interfacesSection"
  visible: section.rows.length >= 2
  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: captionText.implicitHeight
    Text {
      id: captionText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "INTERFACES"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0
    }
    Text {
      objectName: "interfacesCount"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: String(section.rows.length)
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: Style.font.body
    }
  }
  Repeater {
    model: section.rows
    Aranea.NodeDeviceRow {
      refined: true
      required property var modelData
      objectName: "interfaceRow"
      width: section.width
      glyph: modelData.glyph
      label: modelData.label
      detail: modelData.detail
      labelFontFamily: Aranea.Typography.technicalFamily
      detailFontFamily: Aranea.Typography.technicalFamily
      active: !!modelData.active
      available: true
      // Informational: no hover fill, no pointing cursor.
      interactive: false
      hasCursor: false
    }
  }
}
