// A text control in the Aranea Weather dropdown (the place label, the
// updated label, the clear button): text that takes the accent while the
// pointer is really on it (through the dropdown's PointerMoveGate), the
// keyboard cursor outline (only while the host's cursor is on it, never on
// hover), a busy pulse (the place label while a new place saves) and a
// settled click: a click within 300 ms of the control being built, or of
// the dropdown's layout shifting (pointerGate.layoutChangedAt), is refused
// unless the pointer has really moved onto it since. The outline, busy
// pulse, settled click and gated hover block follow FilamentPill's
// (araneadev.shared), adapted to plain text.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Item {
  id: link

  // The label or glyph.
  property string text: ""
  // Optional trailing action glyph stays on the dedicated icon font.
  property string glyph: ""
  // The text colour at rest.
  property color restColor: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
  // The text size in px.
  property real pixelSize: Style.font.caption
  // Whether the text is bold.
  property bool bold: false
  // Letter spacing in px.
  property real letterSpacing: 0
  // The text's horizontal alignment inside a wider link.
  property int horizontalAlignment: Text.AlignRight
  // Hover tooltip; empty shows none.
  property string tooltipText: ""
  // Whether the keyboard cursor is on this control.
  property bool hasCursor: false
  // Whether a change it started is still being applied: the text breathes.
  property bool busy: false
  // Opacity the busy animation drives, 0.45..1.
  property real pulseOpacity: 1
  // The dropdown's PointerMoveGate (qs.Ui), carrying layoutChangedAt; null
  // never lights and settles only on the control's age.
  property var pointerGate: null
  // When the control was built (Date.now()).
  property real createdAt: 0
  // When the gate last accepted a real pointer move onto the control
  // (Date.now()), 0 for never.
  property real pointerMovedAt: 0
  // Whether the pointer really moved onto the control and is still on it.
  property bool hot: false

  // Emitted on a settled pointer click.
  signal clicked
  // Emitted when the pointer really moves onto the control (through the
  // gate).
  signal hoveredMoved

  // Whether a pointer click may act on this control
  // (ClickSettle.clickSettled over its age, the dropdown's last layout
  // shift and the last real pointer move).
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: link.createdAt,
      movedAt: link.pointerMovedAt,
      layoutChangedAt: link.pointerGate ? Number(link.pointerGate.layoutChangedAt) || 0 : 0
    })
  }

  implicitWidth: label.implicitWidth + (glyphLabel.visible ? glyphLabel.implicitWidth + Style.space(4) : 0)
  implicitHeight: label.implicitHeight
  Component.onCompleted: link.createdAt = Date.now()
  onBusyChanged: if (!link.busy)
    link.pulseOpacity = 1

  Rectangle {
    // The keyboard cursor outline.
    objectName: "cursorOutline"
    anchors.fill: parent
    anchors.margins: -Style.space(3)
    color: link.hasCursor ? Util.alpha(Aranea.DesignTokens.accent, 0.08) : "transparent"
    border.width: link.hasCursor ? 1 : 0
    border.color: Aranea.DesignTokens.accent
  }
  Text {
    id: label
    anchors.fill: parent
    anchors.rightMargin: glyphLabel.visible ? glyphLabel.implicitWidth + Style.space(4) : 0
    horizontalAlignment: link.horizontalAlignment
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    text: link.text
    color: link.hot || link.hasCursor ? Aranea.DesignTokens.accent : link.restColor
    opacity: link.busy ? (Aranea.DesignTokens.motionEnabled ? link.pulseOpacity : 0.7) : 1
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: link.pixelSize
    font.bold: link.bold
    font.letterSpacing: link.letterSpacing
  }
  Text {
    id: glyphLabel
    visible: link.glyph !== ""
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: link.glyph
    color: label.color
    opacity: label.opacity
    font.family: Aranea.Typography.iconFamily
    font.pixelSize: link.pixelSize
  }
  // Breathing while busy; static at 0.7 when motion is disabled.
  SequentialAnimation {
    objectName: "busyPulse"
    loops: Animation.Infinite
    running: link.busy && Aranea.DesignTokens.motionEnabled
    NumberAnimation {
      target: link
      property: "pulseOpacity"
      to: 0.45
      duration: 1200
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: link
      property: "pulseOpacity"
      to: 1
      duration: 1200
      easing.type: Easing.InOutSine
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: if (link.clickSettled())
      link.clicked()
  }
  HoverHandler {
    id: hover
    onHoveredChanged: if (!hover.hovered)
      link.hot = false
    onPointChanged: if (link.pointerGate && hover.hovered && link.pointerGate.moved(link, {
      x: hover.point.position.x,
      y: hover.point.position.y
    })) {
      link.pointerMovedAt = Date.now()
      link.hot = true
      link.hoveredMoved()
    }
  }
  PanelToolTip {
    fontFamily: Aranea.Typography.uiFamily
    visible: link.hot && link.tooltipText !== ""
    text: link.tooltipText
  }
}
