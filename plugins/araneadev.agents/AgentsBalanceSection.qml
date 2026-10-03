// The BALANCE section of the Aranea agents dropdown, for prepaid agents:
// the remaining credit, a fuel-gauge Aranea.FilamentBar showing what is
// left of the funded amount (a prepaid account drains toward empty rather
// than filling toward a cap), and the funded-versus-spent detail. A low
// balance tints the remaining amount, as a near-full limit tints its
// percent. Pure view.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section

  // The balance: {remaining, fraction, detail, tone}, or null for none.
  // fraction is what is left (0..1), -1 with no funded amount; tone is
  // "plain" or "urgent" (the last 10% of the funded credits).
  property var balance: null

  objectName: "balanceSection"
  visible: !!section.balance
  spacing: Style.space(6)

  Text {
    text: "BALANCE"
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }
  Item {
    width: parent.width
    implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)
    Text {
      id: balanceLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "Prepaid credits"
      color: Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      id: balanceValue
      objectName: "balanceRemaining"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: section.balance ? String(section.balance.remaining || "") : ""
      color: section.balance && section.balance.tone === "urgent" ? Aranea.DesignTokens.urgent : Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
  Aranea.FilamentBar {
    objectName: "balanceBar"
    width: parent.width
    visible: !!section.balance && Number(section.balance.fraction) >= 0
    value: section.balance ? Number(section.balance.fraction) || 0 : 0
  }
  Text {
    objectName: "balanceDetail"
    width: parent.width
    visible: text !== ""
    text: section.balance ? String(section.balance.detail || "") : ""
    elide: Text.ElideRight
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
