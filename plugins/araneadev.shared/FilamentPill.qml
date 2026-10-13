// Choice pill in the Filament style (the network dropdown's band and DNS
// rows): a quiet inset bezel, or, when selected, a tinted surface,
// full text and a short illuminated underline
// (selectedColor swaps the accent for another token, e.g. the tray's violet
// Hidden pill). The keyboard cursor draws the same corner reticle as
// NodeDeviceRow; pointer hover never draws one, only the hover fill, and
// only after a real pointer move (pointerGate, else the pill's own gate).
// A busy pill breathes like a busy NodeDeviceRow marker. A pill sitting on
// a row a Repeater can rebuild under a still pointer takes that row as
// clickGate, as FilamentSwitch does. Without one, a pill with a
// pointerGate ignores a click within settleMs of its dropdown's layout
// shifting (pointerGate.layoutChangedAt) unless the gate accepted a real
// move onto it since. Labels are plain text, never markup.
// Host font tokens are dynamic QObject properties.
// qmllint disable missing-property
import QtQuick
import qs.Commons
import qs.Ui
import "ClickSettle.js" as ClickSettle

Item {
  id: pill

  // The label, e.g. "Cloudflare".
  property string text: ""
  // Optional icon kept independent from configurable label typography.
  property string glyph: ""
  // Whether this is the chosen option.
  property bool selected: false
  // The border and underline colour when selected (DesignTokens only).
  property color selectedColor: DesignTokens.accent
  // Whether the keyboard cursor is on this pill.
  property bool hasCursor: false
  // Keep focus inside clipped hosts when requested.
  property real cursorOutlineMargin: -Style.space(3)
  // Draw the persistent outline; Settings quiet rows opt out.
  property bool borderVisible: true
  // Draw the selected underline; Settings navigation uses a side marker.
  property bool underlineVisible: true
  // Extra separation shared between the label and its inset indicator.
  property real underlineTextGap: Style.space(3)
  // Show the centered label; Settings navigation supplies an icon-label row.
  property bool labelVisible: true
  // Label colour, preserving the shared selected and muted defaults.
  property color labelColor: selected ? DesignTokens.foreground : Util.alpha(DesignTokens.foreground, refined ? DesignTokens.secondaryOpacity : 0.55)
  // Label font family, with Settings opting into the host menu font.
  property string labelFontFamily: refined ? Typography.uiFamily : Style.font.family
  // Opt into proportional choice labels; interaction remains host-owned.
  property bool refined: false
  // Tracking applied to the label, separately overridable for glyph-only actions.
  property real labelLetterSpacing: refined ? 0 : 0.6
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
  // Whether the pointer really moved onto the pill (gated) and is still
  // over it, with the layout unchanged since: draws the hover fill.
  property bool pointerHovered: false
  // The gate the hover fill uses: the dropdown's, else the pill's own.
  readonly property var hoverGate: pointerGate || ownGate
  // The dropdown's last layout shift; a change drops the hover fill.
  readonly property real layoutStamp: pointerGate ? Number(pointerGate.layoutChangedAt) || 0 : 0

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
  implicitWidth: label.implicitWidth + (glyphLabel.visible ? glyphLabel.implicitWidth + Style.space(4) : 0) + Style.space(16)
  implicitHeight: label.implicitHeight + Style.space(8)
  onLayoutStampChanged: pill.pointerHovered = false

  // The pill's own gate when the dropdown passes none, measuring in
  // window coordinates so content moving under a still pointer is no move.
  PointerMoveGate {
    id: ownGate
    referenceItem: pill.Window.contentItem
  }
  Rectangle {
    // The selected fill (the chosen option).
    id: selectedSurface
    objectName: "selectedFill"
    anchors.fill: parent
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: Util.alpha(pill.selectedColor, 0.16)
      }
      GradientStop {
        position: 1
        color: Util.alpha(DesignTokens.strandEnd, 0.07)
      }
    }
    opacity: pill.selected ? 1 : 0
    visible: pill.selected || opacity > 0
    Behavior on opacity {
      enabled: DesignTokens.motionEnabled
      NumberAnimation {
        duration: DesignTokens.motionEnabled ? DesignTokens.feedbackDuration : 0
      }
    }
  }
  Rectangle {
    // The hover fill.
    objectName: "hoverFill"
    anchors.fill: parent
    color: DesignTokens.hoverFill
    visible: pill.pointerHovered && pill.enabled
  }
  FocusFrame {
    objectName: "cursorOutline"
    anchors.fill: parent
    anchors.margins: pill.cursorOutlineMargin
    focused: pill.hasCursor
  }
  Rectangle {
    id: bezel
    objectName: "pillBorder"
    visible: pill.borderVisible
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: Util.alpha(DesignTokens.foreground, pill.selected ? 0.18 : 0.10)
    Behavior on border.color {
      enabled: DesignTokens.motionEnabled
      ColorAnimation {
        duration: DesignTokens.motionEnabled ? DesignTokens.feedbackDuration : 0
      }
    }
    opacity: pill.busy ? (DesignTokens.motionEnabled ? pill.pulseOpacity : 0.7) : 1
  }
  Rectangle {
    id: underline
    objectName: "pillUnderline"
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(2) - pill.underlineTextGap / 2
    width: pill.selected ? Math.max(Style.space(12), pill.width - Style.space(24)) : 0
    height: 2
    radius: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: pill.selectedColor
      }
      GradientStop {
        position: 1
        color: DesignTokens.strandEnd
      }
    }
    visible: pill.underlineVisible && (pill.selected || width > 0)
    Behavior on width {
      enabled: DesignTokens.motionEnabled
      NumberAnimation {
        duration: DesignTokens.motionEnabled ? DesignTokens.settleDuration : 0
        easing.type: Easing.OutCubic
      }
    }
    opacity: pill.busy ? (DesignTokens.motionEnabled ? pill.pulseOpacity : 0.7) : 1
  }
  Connections {
    target: MotionState
    function onMotionEnabledChanged() {
      if (MotionState.motionEnabled)
        return
      selectedSurface.opacity = Qt.binding(function () {
        return pill.selected ? 1 : 0
      })
      bezel.border.color = Qt.binding(function () {
        return Util.alpha(DesignTokens.foreground, pill.selected ? 0.18 : 0.10)
      })
      underline.width = Qt.binding(function () {
        return pill.selected ? Math.max(Style.space(12), pill.width - Style.space(24)) : 0
      })
    }
  }
  Item {
    id: labelRow
    visible: pill.labelVisible
    anchors.centerIn: parent
    anchors.verticalCenterOffset: pill.underlineVisible ? -pill.underlineTextGap / 2 : 0
    readonly property real glyphSpace: glyphLabel.visible ? glyphLabel.implicitWidth + Style.space(4) : 0
    implicitWidth: label.implicitWidth + glyphSpace
    implicitHeight: Math.max(label.implicitHeight, glyphLabel.implicitHeight)
    width: Math.min(implicitWidth, Math.max(0, pill.width - Style.space(8)))
    Text {
      id: glyphLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      visible: pill.glyph !== ""
      textFormat: Text.PlainText
      text: pill.glyph
      color: pill.labelColor
      font.family: Typography.iconFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      id: label
      anchors.left: parent.left
      anchors.leftMargin: labelRow.glyphSpace
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      width: Math.max(0, Math.min(implicitWidth, labelRow.width - labelRow.glyphSpace))
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: pill.text
      color: pill.labelColor
      font.family: pill.labelFontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: pill.labelLetterSpacing
    }
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
    onHoveredChanged: {
      if (!hovered) {
        pill.pointerHovered = false
        ownGate.reset()
      } else if (!pill.pointerGate)
        pill.hoveredMoved()
    }
    onPointChanged: {
      if (!hover.hovered || !pill.hoverGate.moved(hover.parent, {
        x: hover.point.position.x,
        y: hover.point.position.y
      }))
        return
      pill.pointerHovered = true
      if (pill.pointerGate) {
        pill.pointerMovedAt = Date.now()
        pill.hoveredMoved()
      }
    }
  }
  PanelToolTip {
    fontFamily: Typography.uiFamily
    objectName: "pillTip"
    visible: hover.hovered && pill.tooltipText !== ""
    text: pill.tooltipText
  }
}
