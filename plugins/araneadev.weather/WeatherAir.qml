// The Aranea Weather dropdown's AIR & UV section: a caption with the AQI
// and UV chips on the right content edge. Each chip hides on its own when
// its value is missing. The AQI chip's tone tints it: "good" (Good, Fair)
// accent, "plain" (Moderate) muted, "bad" (Poor and worse) urgent; UV is
// always plain. The chips are read-outs, never clickable. Pure view: plain
// inputs in, nothing out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: air

  // The AQI chip: {visible, text, tone ("good", "plain" or "bad")}.
  property var aqi: ({
      visible: false
    })
  // The UV chip: {visible, text}.
  property var uv: ({
      visible: false
    })
  // Whether either chip shows.
  readonly property bool anyShown: !!air.aqi.visible || !!air.uv.visible

  // A read-only chip: a thin border and text in its tone's colour.
  component Chip: Item {
    id: chip
    // The chip's text.
    property string text: ""
    // "good", "plain" or "bad".
    property string tone: "plain"
    // The colour the tone gives the text and border.
    readonly property color toneColor: chip.tone === "good" ? Aranea.DesignTokens.accent : chip.tone === "bad" ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.foreground, 0.82)

    implicitWidth: chipText.implicitWidth + Style.space(14)
    implicitHeight: chipText.implicitHeight + Style.space(4)

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.width: 1
      border.color: chip.tone === "plain" ? Util.alpha(Aranea.DesignTokens.foreground, 0.2) : Util.alpha(chip.toneColor, 0.6)
    }
    Text {
      id: chipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.text
      color: chip.toneColor
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0
    }
  }

  implicitHeight: Math.max(title.implicitHeight, chips.implicitHeight)

  Text {
    id: title
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: "AIR & UV"
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0
  }
  Row {
    id: chips
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Chip {
      objectName: "aqiChip"
      visible: !!air.aqi.visible
      text: air.aqi.text || ""
      tone: air.aqi.tone || "plain"
    }
    Chip {
      objectName: "uvChip"
      visible: !!air.uv.visible
      text: air.uv.text || ""
      tone: "plain"
    }
  }
}
