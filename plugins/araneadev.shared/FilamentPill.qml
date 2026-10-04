// Choice pill in the Filament style (the network dropdown's band and DNS
// rows): a thin muted border and muted text, or, when selected, an accent
// border, full text and a 2 px accent underline (selectedColor swaps the
// accent for another token, e.g. the tray's violet Hidden pill). The
// keyboard cursor draws the same mint outline as NodeDeviceRow; pointer
// hover never draws one.
// A busy pill breathes like a busy NodeDeviceRow marker. A pill sitting on
// a row a Repeater can rebuild under a still pointer takes that row as
// clickGate, as FilamentSwitch does. Without one, a pill with a
// pointerGate ignores a click within settleMs of its dropdown's layout
// shifting (pointerGate.layoutChangedAt) unless the gate accepted a real
// move onto it since. Labels are plain text, never markup.
import QtQuick
import qs.Commons
import qs.Ui
import "ClickSettle.js" as ClickSettle

Item {
  id: pill

  // The label, e.g. "Cloudflare".
  property string text: ""
  // Whether this is the chosen option.
  property bool selected: false
  // The border and underline colour when selected (DesignTokens only).
  property color selectedColor: DesignTokens.accent
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
  // How long after a layout shift a click is ignored, in ms, without a
  // clickGate (see pointerGate).
  property int settleMs: 300
  // When the gate last accepted a real pointer move onto the pill
  // (Date.now()), 0 for never.
  property real pointerMovedAt: 0

  // Emitted when the pill is clicked or activated.
  signal clicked
  // Emitted when the pointer moves onto the pill (see pointerGate).
  signal hoveredMoved
  // Emitted when a pointer press lands on the pill, so a host can remember
  // what the pill stood for when pressed and refuse a changed release.
  signal pressed
  // Emitted when a pointer press ends without choosing the pill: released
  // outside it, canceled (a Flickable stole it), or refused by the settle,
  // so a host can forget what it remembered on pressed.
  signal pressCanceled

  // Chooses the pill, as a click does.
  function activate() {
    clicked()
  }

  // Whether a pointer click may choose the pill: clickGate's verdict, else
  // settled since the dropdown's last layout shift or moved onto since
  // (ClickSettle.clickSettled; no gate never ignores a click).
  function clickSettled() {
    if (pill.clickGate)
      return pill.clickGate.clickSettled()
    return ClickSettle.clickSettled({
      now: Date.now(),
      movedAt: pill.pointerMovedAt,
      layoutChangedAt: pill.pointerGate ? Number(pill.pointerGate.layoutChangedAt) || 0 : 0,
      settleMs: pill.settleMs
    })
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
    border.color: pill.selected ? pill.selectedColor : Util.alpha(DesignTokens.foreground, 0.2)
    opacity: pill.busy ? (DesignTokens.motionEnabled ? pill.pulseOpacity : 0.7) : 1
  }
  Rectangle {
    objectName: "pillUnderline"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 2
    color: pill.selectedColor
    visible: pill.selected
    opacity: pill.busy ? (DesignTokens.motionEnabled ? pill.pulseOpacity : 0.7) : 1
  }
  Text {
    id: label
    textFormat: Text.PlainText
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
    onPressed: pill.pressed()
    onReleased: if (!containsMouse)
      pill.pressCanceled()
    onCanceled: pill.pressCanceled()
    onClicked: {
      if (pill.clickSettled())
        pill.activate()
      else
        pill.pressCanceled()
    }
  }
  HoverHandler {
    id: hover
    onHoveredChanged: if (hovered && !pill.pointerGate)
      pill.hoveredMoved()
    onPointChanged: if (pill.pointerGate && hover.hovered && pill.pointerGate.moved(hover.parent, {
      x: hover.point.position.x,
      y: hover.point.position.y
    })) {
      pill.pointerMovedAt = Date.now()
      pill.hoveredMoved()
    }
  }
  PanelToolTip {
    objectName: "pillTip"
    visible: hover.hovered && pill.tooltipText !== ""
    text: pill.tooltipText
  }
}
