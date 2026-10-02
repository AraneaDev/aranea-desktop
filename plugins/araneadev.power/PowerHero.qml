// The Aranea Power dropdown's hero: a battery cell drawn in QML (an
// outline with a nub, filled to the charge with an accent to strandEnd
// gradient and a soft glow), "Battery" over the status line, and the big
// percentage on the right content edge. Pure view: plain inputs, no
// signals.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: hero

  // The charge, 0..1; clamped for the fill.
  property real fraction: 0
  // The status line, e.g. "Sipping juice".
  property string status: ""
  // Opacity of the status line alone, for the host's phrase fade.
  property real statusOpacity: 1
  // The percentage as text, e.g. "62"; empty hides the big number.
  property string percent: ""

  objectName: "powerHero"
  implicitHeight: Math.max(cell.height, labels.implicitHeight, percentBlock.implicitHeight)

  Item {
    id: cell
    // The cell body's size; the nub sits past its right edge.
    width: Style.space(46)
    height: Style.space(22)
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter

    Rectangle {
      objectName: "batteryOutline"
      anchors.fill: parent
      color: "transparent"
      radius: Style.space(3)
      border.width: Math.max(1, Style.space(1.5))
      border.color: Util.alpha(Aranea.DesignTokens.foreground, 0.8)
    }
    Rectangle {
      objectName: "batteryNub"
      x: cell.width + Style.space(1)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(3)
      height: Style.space(8)
      radius: Style.space(1)
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.8)
    }
    Item {
      id: track
      objectName: "batteryTrack"
      anchors.fill: parent
      anchors.margins: Style.space(3)

      // The glow under the fill.
      Rectangle {
        objectName: "batteryGlow"
        x: -Style.space(2)
        y: -Style.space(2)
        width: fill.width + Style.space(4)
        height: track.height + Style.space(4)
        radius: Style.space(3)
        visible: fill.width > 0
        color: Util.alpha(Aranea.DesignTokens.accent, 0.22)
      }
      Rectangle {
        id: fill
        objectName: "batteryFill"
        width: track.width * Math.max(0, Math.min(1, hero.fraction))
        height: track.height
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop {
            position: 0
            color: Aranea.DesignTokens.accent
          }
          GradientStop {
            position: 1
            color: Aranea.DesignTokens.strandEnd
          }
        }
      }
    }
  }
  Column {
    id: labels
    anchors.left: cell.right
    anchors.leftMargin: Style.space(16)
    anchors.right: percentBlock.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      objectName: "heroTitle"
      width: parent.width
      text: "Battery"
      elide: Text.ElideRight
      color: Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      objectName: "heroStatus"
      width: parent.width
      text: hero.status
      opacity: hero.statusOpacity
      elide: Text.ElideRight
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 1.2
    }
  }
  Row {
    id: percentBlock
    objectName: "heroPercentBlock"
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: hero.percent !== ""

    Text {
      id: percentText
      objectName: "heroPercent"
      text: hero.percent
      color: Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.displayLarge
      font.bold: true
    }
    Text {
      anchors.baseline: percentText.baseline
      text: "%"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }
  }
}
