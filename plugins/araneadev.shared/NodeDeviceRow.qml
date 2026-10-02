// Device row in the Filament style: a web node (lit when the device is
// the active one, breathing while busy, glowing by signal strength), a
// glyph in a fixed-width slot so labels line up across dropdowns, the
// label, a trailing detail, and an optional trailing action slot flush
// with the row's right edge. Unavailable devices are dimmed and never
// chosen. The row spans the item's full width. A pointer click within
// settleMs of the row being created, or of its dropdown's layout shifting
// (the dropdown stamps pointerGate.layoutChangedAt), is ignored unless the
// pointer has really moved over it since (through pointerGate): a Repeater
// rebuild or a section growing can put this row under a pointer that was
// aimed at another.
import QtQuick
import QtQuick.Effects
import qs.Commons
import "ClickSettle.js" as ClickSettle

Item {
  id: row

  // Device glyph (a Nerd Font icon).
  property string glyph: ""
  // Device name.
  property string label: ""
  // Trailing detail, e.g. "unplugged".
  property string detail: ""
  // The detail's colour; a host passes DesignTokens.urgent for a failure.
  property color detailColor: Util.alpha(DesignTokens.foreground, 0.55)
  // Whether this is the active device.
  property bool active: false
  // Whether the device can be chosen.
  property bool available: true
  // Whether the keyboard cursor is on this row.
  property bool hasCursor: false
  // Whether a background operation (pairing, connecting) is in progress:
  // the marker breathes while true.
  property bool busy: false
  // Live signal strength: -1 unused (audio), 0..3 for a marker glow.
  property int signal: -1
  // Trailing content, flush with the row's right edge (e.g. a forget
  // button). When it has children, the detail text sits left of it.
  default property alias trailing: trailingSlot.data
  // Opacity the busy marker's breathing animation drives, 0.45..1.
  property real pulseOpacity: 1
  // Whether the pointer is over the row, for a trailing action a host
  // dropdown shows only on hover (e.g. a forget button).
  readonly property alias hovered: rowMouse.containsMouse
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover churn from
  // this row moving under a still pointer. null (default) keeps the old
  // behaviour: entered on containsMouse becoming true.
  property var pointerGate: null
  // How long after creation or a layout shift a pointer click is ignored,
  // in ms, unless the gate has accepted a real move over the row since.
  property int settleMs: 300
  // When the row was created (Date.now()), for settleMs.
  property real createdAt: 0
  // When the gate last accepted a real pointer move over this row
  // (Date.now()), 0 for never.
  property real pointerMovedAt: 0

  // Emitted when an available row is clicked or activated.
  signal chosen
  // Emitted when the pointer enters the row.
  signal entered

  // Whether a pointer click may choose the row: it has been on screen, and
  // the dropdown's layout has held still, for settleMs, or the pointer has
  // really moved over it since (ClickSettle.clickSettled).
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: row.createdAt,
      movedAt: row.pointerMovedAt,
      layoutChangedAt: row.pointerGate ? Number(row.pointerGate.layoutChangedAt) || 0 : 0,
      settleMs: row.settleMs
    })
  }

  // Chooses the device, unless it is unavailable.
  function activate() {
    if (available)
      chosen()
  }

  implicitHeight: Style.space(30)
  opacity: available ? 1 : 0.45
  Component.onCompleted: createdAt = Date.now()

  Rectangle {
    // The keyboard cursor outline.
    objectName: "cursorOutline"
    anchors.fill: parent
    color: row.hasCursor ? Util.alpha(DesignTokens.accent, 0.08) : "transparent"
    border.width: row.hasCursor ? 1 : 0
    border.color: DesignTokens.accent
  }
  // The active device's node glows.
  RectangularShadow {
    x: marker.x
    y: marker.y
    width: marker.width
    height: marker.height
    rotation: marker.rotation
    blur: Style.space(8)
    color: Util.alpha(DesignTokens.accent, 0.8)
    visible: row.active
  }
  // The marker's live-signal glow; unused (-1) or 0 shows none.
  RectangularShadow {
    objectName: "signalGlow"
    x: marker.x
    y: marker.y
    width: marker.width
    height: marker.height
    rotation: marker.rotation
    blur: Style.space(8)
    color: Util.alpha(DesignTokens.accent, row.signal === 3 ? 0.9 : row.signal === 2 ? 0.6 : row.signal === 1 ? 0.35 : 0)
    visible: row.signal > 0
  }
  Rectangle {
    id: marker
    width: Style.space(8)
    height: width
    rotation: 45
    x: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    color: row.active ? DesignTokens.accent : "transparent"
    border.width: 1
    border.color: row.active ? DesignTokens.accent : Util.alpha(DesignTokens.foreground, 0.22)
    opacity: row.busy ? (DesignTokens.motionEnabled ? row.pulseOpacity : 0.7) : 1
  }
  // Breathing animation for a busy marker; the marker sits static at 0.7
  // opacity instead when motion is disabled (see marker.opacity above).
  SequentialAnimation {
    objectName: "busyPulse"
    loops: Animation.Infinite
    running: row.busy && DesignTokens.motionEnabled
    NumberAnimation {
      target: row
      property: "pulseOpacity"
      to: 0.45
      duration: 1200
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: row
      property: "pulseOpacity"
      to: 1
      duration: 1200
      easing.type: Easing.InOutSine
    }
  }
  Text {
    id: glyphText
    x: marker.x + marker.width + Style.space(10)
    width: Style.space(18)
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignHCenter
    text: row.glyph
    color: Util.alpha(DesignTokens.foreground, 0.82)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
  Text {
    anchors.left: glyphText.right
    anchors.leftMargin: Style.space(10)
    anchors.right: detailText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: row.label
    elide: Text.ElideRight
    color: DesignTokens.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
  Text {
    id: detailText
    objectName: "detailText"
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8) + (trailingSlot.width > 0 ? trailingSlot.width + Style.space(8) : 0)
    anchors.verticalCenter: parent.verticalCenter
    text: row.detail
    color: row.detailColor
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  // Trailing action slot, flush with the row's right edge so a forget/
  // delete button reaches the same clickable edge as the row itself.
  Item {
    id: trailingSlot
    objectName: "rowTrailing"
    z: 1
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }
  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: row.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onContainsMouseChanged: if (containsMouse && !row.pointerGate)
      row.entered()
    onPositionChanged: function (mouse) {
      if (row.pointerGate && row.pointerGate.moved(rowMouse, mouse)) {
        row.pointerMovedAt = Date.now()
        row.entered()
      }
    }
    onClicked: if (row.clickSettled())
      row.activate()
  }
}
