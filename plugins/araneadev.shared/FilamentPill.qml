// Choice pill in the Filament style (the network dropdown's band and DNS
// rows): a thin muted border and muted text, or, when selected, an accent
// border, full text and a 2 px accent underline. The keyboard cursor draws
// the same mint outline as NodeDeviceRow; pointer hover never draws one.
// A busy pill breathes like a busy NodeDeviceRow marker. A pill sitting on
// a row a Repeater can rebuild under a still pointer takes that row as
// clickGate, as FilamentSwitch does.
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: pill

  // The label, e.g. "Cloudflare".
  property string text: ""
  // Whether this is the chosen option.
  property bool selected: false
  // Whether the keyboard cursor is on this pill.
  property bool hasCursor: false
  // Whether a change to this option is in progress (a pending band).
  property bool busy: false
  // Hover tooltip; empty shows none.
  property string tooltipText: ""
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from the pill
  // moving under a still pointer. With a gate set, hoveredMoved fires only
  // on a real pointer move; without one it fires on entering.
  property var pointerGate: null
  // Opacity the busy animation drives, 0.45..1.
  property real pulseOpacity: 1
  // Optional item whose clickSettled() a pointer click must pass, e.g. the
  // NodeDeviceRow hosting the pill; null (default) never ignores a click.
  // activate() stays unguarded for the keyboard and tests.
  property var clickGate: null

  // Emitted when the pill is clicked or activated.
  signal clicked
  // Emitted when the pointer moves onto the pill (see pointerGate).
  signal hoveredMoved

  // Chooses the pill, as a click does.
  function activate() {
    clicked()
  }

  objectName: "pill"
  implicitWidth: label.implicitWidth + Style.space(16)
  implicitHeight: label.implicitHeight + Style.space(8)

  Rectangle {
    // The keyboard cursor outline.
    objectName: "cursorOutline"
    anchors.fill: parent
    anchors.margins: -Style.space(3)
    color: pill.hasCursor ? Util.alpha(DesignTokens.accent, 0.08) : "transparent"
    border.width: pill.hasCursor ? 1 : 0
    border.color: DesignTokens.accent
  }
  Rectangle {
    objectName: "pillBorder"
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: pill.selected ? DesignTokens.accent : Util.alpha(DesignTokens.foreground, 0.2)
    opacity: pill.busy ? (DesignTokens.motionEnabled ? pill.pulseOpacity : 0.7) : 1
  }
  Rectangle {
    objectName: "pillUnderline"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 2
    color: DesignTokens.accent
    visible: pill.selected
    opacity: pill.busy ? (DesignTokens.motionEnabled ? pill.pulseOpacity : 0.7) : 1
  }
  Text {
    id: label
    anchors.centerIn: parent
    width: Math.min(implicitWidth, pill.width - Style.space(8))
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    text: pill.text
    color: pill.selected ? DesignTokens.foreground : Util.alpha(DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 0.6
  }
  // Breathing while busy; static at 0.7 when motion is disabled.
  SequentialAnimation {
    objectName: "busyPulse"
    loops: Animation.Infinite
    running: pill.busy && DesignTokens.motionEnabled
    NumberAnimation {
      target: pill
      property: "pulseOpacity"
      to: 0.45
      duration: 1200
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: pill
      property: "pulseOpacity"
      to: 1
      duration: 1200
      easing.type: Easing.InOutSine
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: if (!pill.clickGate || pill.clickGate.clickSettled())
      pill.activate()
  }
  HoverHandler {
    id: hover
    onHoveredChanged: if (hovered && !pill.pointerGate)
      pill.hoveredMoved()
    onPointChanged: if (pill.pointerGate && hover.hovered && pill.pointerGate.moved(hover.parent, {
      x: hover.point.position.x,
      y: hover.point.position.y
    }))
      pill.hoveredMoved()
  }
  PanelToolTip {
    objectName: "pillTip"
    visible: hover.hovered && pill.tooltipText !== ""
    text: pill.tooltipText
  }
}
