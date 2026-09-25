import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "OsdModel.js" as OsdModel

Item {
  id: root

  property bool opened: false
  property string icon: ""
  property string iconKey: ""
  property string message: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200
  property bool motionEnabled: Quickshell.env("ARANEA_REDUCED_MOTION") !== "1"
  readonly property string motionStatePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/aranea/motion"
  readonly property real fraction: OsdModel.progressFraction({ hasProgress: root.hasProgress, value: root.value, maxValue: root.maxValue })
  readonly property bool mediaOsd: root.iconKey.indexOf("media") === 0 || root.iconKey.indexOf("player") === 0
  readonly property int pad: Style.space(12)
  readonly property int gap: Style.space(12)
  readonly property int strandWidth: root.hasProgress ? Style.space(168) : Style.space(64)
  readonly property int iconWidth: Style.space(24)
  readonly property int valueWidth: Style.space(42)
  readonly property int messageWidth: Math.min(Style.space(220), messageMetrics.advanceWidth)
  readonly property int contentWidth: root.iconWidth + root.gap + root.strandWidth + (root.hasProgress ? root.gap + root.valueWidth : (root.message.length > 0 ? root.gap + root.messageWidth : 0))

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration)
    root.iconKey = next.iconKey
    root.icon = next.icon
    root.message = next.message
    root.value = next.value
    root.maxValue = next.maxValue
    root.hasProgress = next.hasProgress
    root.duration = next.duration
    root.opened = true
    if (root.duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function open(payloadJson: string): void {
    try {
      var payload = JSON.parse(payloadJson || "{}")
      root.show(payload.icon || "", payload.message || "", payload.value === undefined ? "" : String(payload.value), payload.max === undefined ? "100" : String(payload.max), payload.progressText || "", payload.duration === undefined ? "1200" : String(payload.duration))
    } catch (error) {}
  }

  function close(): void { root.opened = false }

  FileView {
    path: root.motionStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.motionEnabled = String(text || "").trim() !== "off"
    onLoadFailed: root.motionEnabled = Quickshell.env("ARANEA_REDUCED_MOTION") !== "1"
    onFileChanged: reload()
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

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    BorderSurface {
      id: card
      property real revealOffset: root.opened ? 0 : Style.space(8)
      width: card.borderLeft + root.pad + root.contentWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + Style.font.body + root.pad + card.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(62)
      color: Util.alpha(Color.background, 0.9)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(1)))
      radius: Style.cornerRadius
      opacity: root.opened ? 1 : 0
      transform: Translate { y: card.revealOffset }

      Behavior on opacity {
        enabled: root.motionEnabled
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on revealOffset {
        enabled: root.motionEnabled
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }

      Row {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.pad
        anchors.rightMargin: card.borderRight + root.pad
        anchors.bottomMargin: card.borderBottom + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: root.gap

        Text {
          width: root.iconWidth
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
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
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
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
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
          }
        }

        Text {
          visible: root.hasProgress
          width: root.valueWidth
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: root.message
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
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
