// Aranea on-screen display (the araneadev.osd plugin's "panel" entry point,
// replacing the stock Omarchy OSD): a bottom-centre card with an icon, a
// filament progress strand and a value or message. Driven through the "osd"
// IPC target (show/close/state/ping); display rules live in OsdModel.js.

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
  property string icon: ""
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
  // changes. Measured once at startup (Component.onCompleted): the icon set
  // is fixed and Style tokens only change across a shell restart, which
  // recreates this component anyway. Left-aligned ink (Aranea.InkText) then
  // starts `pad` from the inner border for every icon.
  property real iconWidth: 0
  // Value column: fixed to the ink width of "100%" at the value font, so
  // the card never resizes across 0-100%. Left-aligned ink (Aranea.InkText)
  // then starts `gap` after the strand for every value.
  readonly property real valueWidth: valueFloorInk.tightBoundingRect.width
  // Message column width: the message's width, capped.
  readonly property int messageWidth: Math.min(Style.space(220), messageMetrics.advanceWidth)
  // Width of the card content between the paddings.
  readonly property real contentWidth: root.iconWidth + root.gap + root.strandWidth + (root.hasProgress ? root.gap + root.valueWidth : (root.message.length > 0 ? root.gap + root.messageWidth : 0))

  // Widest ink among OsdModel.allIconGlyphs() at the icon font: reuses
  // iconProbeMetrics (one TextMetrics, its text set per glyph in turn, read
  // back synchronously) rather than one TextMetrics per glyph.
  function maxIconInkWidth() {
    var max = 0
    var glyphs = OsdModel.allIconGlyphs()
    for (var i = 0; i < glyphs.length; i++) {
      iconProbeMetrics.text = glyphs[i]
      max = Math.max(max, iconProbeMetrics.tightBoundingRect.width)
    }
    return max
  }

  Component.onCompleted: {
    root.iconWidth = root.maxIconInkWidth()
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

  // "100%" at the value font: the value column's fixed width (valueWidth).
  TextMetrics {
    id: valueFloorInk
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    text: "100%"
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

        Item {
          width: root.strandWidth
          height: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Math.max(1, Style.spacing.hairline)
            color: Util.alpha(Color.popups.text, 0.3)
          }
          Rectangle {
            width: root.hasProgress ? parent.width * root.fraction : parent.width * 0.28
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: Math.max(2, Style.spacing.sm)
            radius: height / 2
            color: Color.accent
            Behavior on width {
              enabled: root.motionEnabled
              NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
              }
            }
          }
          Rectangle {
            width: Style.space(8)
            height: width
            radius: width / 2
            x: root.hasProgress ? parent.width * root.fraction - width / 2 : parent.width * 0.28 - width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: Color.accent
            Behavior on x {
              enabled: root.motionEnabled
              NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
              }
            }
          }
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
