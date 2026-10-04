// Aranea on-screen display (the araneadev.osd plugin's "panel" entry point,
// replacing the stock Omarchy OSD): a bottom-centre card with an icon, a
// filament progress strand (OsdStrand.qml) and a value or message. Driven
// through the "osd" IPC target (show/close/state/ping); display rules live
// in OsdModel.js.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "../araneadev.shared" as Aranea
import "OsdModel.js" as OsdModel

Item {
  id: root

  // Whether the card is shown; cleared by the hide timer or close().
  property bool opened: false
  // Glyph shown in the icon column.
  property string icon: String.fromCodePoint(0xf028)
  // Value text (progress) or message text.
  property string message: ""
  // Progress value, 0..maxValue.
  property int value: 0
  // Progress maximum.
  property int maxValue: 100
  // Show a progress strand and value; false shows a short strand and message.
  property bool hasProgress: true
  // Ms before the card hides; 0 keeps it open.
  property int duration: 1200
  // Animate the card unless Aranea motion is off (shared Aranea.MotionState).
  property bool motionEnabled: Aranea.MotionState.motionEnabled
  // Filled part of the strand, 0..1.
  readonly property real fraction: OsdModel.progressFraction({
    hasProgress: root.hasProgress,
    value: root.value,
    maxValue: root.maxValue
  })
  // Padding between the card border and its content.
  readonly property int pad: Style.space(14)
  // Spacing between the icon, strand and text.
  readonly property int gap: Style.space(12)
  // Strand width: long with progress, short without.
  readonly property int strandWidth: root.hasProgress ? Style.space(180) : Style.space(80)
  // Icon column: fixed to the widest ink of every glyph the OSD can show
  // (OsdModel.allIconGlyphs), so the card never resizes when the icon
  // changes. Recomputed at startup and whenever the icon font's family or
  // size changes (see the Connections below): Style.font is not fixed for
  // a running shell; `omarchy display text size` and the applyTheme IPC
  // both rewrite ~/.config/omarchy/shell.toml, which Color.qml's
  // userShellFile FileView watches and reloads live, without a restart.
  // Left-aligned ink (Aranea.InkText) then starts `pad` from the inner
  // border for every icon.
  readonly property alias iconWidth: root._iconWidth
  // Private backing store for iconWidth (kept writable so
  // maxIconInkWidth's result can be assigned from Component.onCompleted
  // and the Style.font Connections below); read iconWidth, not this.
  property real _iconWidth: 0
  // Value column: the wider of the "100%" floor and the current value's own
  // ink (OsdModel.valueColumnWidth), so the card never resizes across
  // 0-100% and only widens for an out-of-range value ("1000%" from
  // `omarchy osd -p 1000`; /usr/bin/omarchy-osd builds progress_text from
  // the raw, unclamped argument). Left-aligned ink (Aranea.InkText) then
  // starts `gap` after the strand for every value.
  readonly property real valueWidth: OsdModel.valueColumnWidth(valueFloorInk.tightBoundingRect.width, valueInk.tightBoundingRect.width)
  // Message column width: the message's width, capped.
  readonly property int messageWidth: Math.min(Style.space(220), messageMetrics.advanceWidth)
  // Width of the card content between the paddings.
  readonly property real contentWidth: root.iconWidth + root.gap + root.strandWidth + (root.hasProgress ? root.gap + root.valueWidth : (root.message.length > 0 ? root.gap + root.messageWidth : 0))

  // Widest ink among OsdModel.allIconGlyphs() at the icon font:
  // OsdModel.maxInkWidth (pure, unit-tested against a fake measure
  // callback) driven by iconProbeMetrics (one TextMetrics, its text set
  // per glyph in turn, read back synchronously) rather than one
  // TextMetrics per glyph.
  function maxIconInkWidth() {
    return OsdModel.maxInkWidth(OsdModel.allIconGlyphs(), function (glyph) {
      iconProbeMetrics.text = glyph
      return iconProbeMetrics.tightBoundingRect.width
    })
  }

  // Style.font.title/family can change live (see iconWidth above);
  // recompute iconWidth whenever either does. A direct binding on
  // iconWidth cannot do this without mutating iconProbeMetrics inside
  // its own dependency chain (a binding loop), so this recomputes
  // imperatively instead.
  Connections {
    target: Style.font
    function onTitleChanged() {
      root._iconWidth = root.maxIconInkWidth()
    }
    function onFamilyChanged() {
      root._iconWidth = root.maxIconInkWidth()
    }
  }

  Component.onCompleted: {
    root._iconWidth = root.maxIconInkWidth()
  }

  // Applies a request (OsdModel.stateForShow), opens the card and
  // (re)starts the hide timer, or stops it for duration 0.
  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration)
    root.icon = next.icon
    root.message = next.message
    root.value = next.value
    root.maxValue = next.maxValue
    root.hasProgress = next.hasProgress
    root.duration = next.duration
    root.opened = true
    if (root.duration > 0)
      hideTimer.restart()
    else
      hideTimer.stop()
  }

  // Parses a JSON payload {icon, message, value, max, progressText,
  // duration} and shows it; invalid JSON is ignored.
  function open(payloadJson: string): void {
    try {
      var payload = JSON.parse(payloadJson || "{}")
      root.show(payload.icon || "", payload.message || "", payload.value === undefined ? "" : String(payload.value), payload.max === undefined ? "100" : String(payload.max), payload.progressText || "", payload.duration === undefined ? "1200" : String(payload.duration))
    } catch (error) {}
  }

  // Hides the card.
  function close(): void {
    root.opened = false
  }

  Timer {
    id: hideTimer
    interval: root.duration
    repeat: false
    onTriggered: root.opened = false
  }

  TextMetrics {
    id: messageMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    text: root.message
  }

  // "100%" at the value font: the value column's floor width (valueWidth).
  TextMetrics {
    id: valueFloorInk
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    text: "100%"
  }

  // The current value text's ink at the value font: widens valueWidth past
  // the "100%" floor for an out-of-range value instead of letting it spill.
  // Reuses valueFloorInk's resolved font (rather than restating
  // Style.font.family/title) so this does not add another qmllint
  // missing-property warning for Style.font to the baseline.
  TextMetrics {
    id: valueInk
    font: valueFloorInk.font
    text: root.message
  }

  // Reused by maxIconInkWidth to measure each OsdModel.allIconGlyphs()
  // glyph in turn, at the icon font.
  TextMetrics {
    id: iconProbeMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.title
  }

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string {
      root.close()
      return "ok"
    }
    function state(): string {
      return root.opened ? "open" : "closed"
    }
    function ping(): string {
      return "ok"
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Aranea.SurfaceCard {
      id: card
      property real revealOffset: root.opened ? 0 : Style.space(8)
      width: card.borderLeft + root.pad + root.contentWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + Style.font.body + root.pad + card.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(62)
      fillColor: Util.alpha(Color.background, 0.9)
      surface: "popups"
      borderColor: Color.popups.border
      opacity: root.opened ? 1 : 0
      transform: Translate {
        y: card.revealOffset
      }

      Behavior on opacity {
        enabled: root.motionEnabled
        NumberAnimation {
          duration: 160
          easing.type: Easing.OutCubic
        }
      }
      Behavior on revealOffset {
        enabled: root.motionEnabled
        NumberAnimation {
          duration: 160
          easing.type: Easing.OutCubic
        }
      }

      Row {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.pad
        anchors.rightMargin: card.borderRight + root.pad
        anchors.bottomMargin: card.borderBottom + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: root.gap

        Aranea.InkText {
          width: root.iconWidth
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignLeft
          text: root.icon
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        OsdStrand {
          width: root.strandWidth
          height: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          fraction: root.fraction
          hasProgress: root.hasProgress
          motionEnabled: root.motionEnabled
        }

        Aranea.InkText {
          visible: root.hasProgress
          width: root.valueWidth
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignLeft
          text: root.message
          elide: Text.ElideNone
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        Text {
          visible: !root.hasProgress && root.message.length > 0
          width: root.messageWidth
          anchors.verticalCenter: parent.verticalCenter
          text: root.message
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }
    }
  }
}
