// A pointer-only text control in the Aranea Clock dropdown (the month
// chevrons, the W heading, Back to today, the week start label): muted
// text that takes the accent while the pointer is really on it (through
// the gate), an optional tooltip, and a settled click. Never takes
// keyboard focus and never draws an outline, as in stock.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

ClockTarget {
  id: link

  // The label or glyph.
  property string text: ""
  // Glyph-only controls can override the configurable UI label font.
  property string fontFamily: Aranea.Typography.uiFamily
  // The text colour at rest.
  property color restColor: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
  // The text size in px.
  property real pixelSize: Style.font.caption
  // Whether the text is bold.
  property bool bold: false
  // Letter spacing in px.
  property real letterSpacing: 0
  // Hover tooltip; empty shows none.
  property string tooltipText: ""
  // The text's horizontal alignment inside a wider link.
  property int horizontalAlignment: Text.AlignHCenter

  // Emitted on a settled pointer click.
  signal clicked

  implicitWidth: label.implicitWidth
  implicitHeight: label.implicitHeight

  Text {
    id: label
    anchors.fill: parent
    horizontalAlignment: link.horizontalAlignment
    verticalAlignment: Text.AlignVCenter
    text: link.text
    color: link.hot ? Aranea.DesignTokens.accent : link.restColor
    font.family: link.fontFamily
    font.pixelSize: link.pixelSize
    font.bold: link.bold
    font.letterSpacing: link.letterSpacing
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: if (link.clickSettled())
      link.clicked()
  }
  PanelToolTip {
    fontFamily: Aranea.Typography.uiFamily
    visible: link.hot && link.tooltipText !== ""
    text: link.tooltipText
  }
}
