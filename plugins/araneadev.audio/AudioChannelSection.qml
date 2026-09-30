// One audio channel (Output or Input) in the Aranea audio dropdown: the
// caption and level, a filament slider with the live signal glow, and
// the device list. Pure view: plain inputs in, signals out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section

  // Section caption, e.g. "OUTPUT".
  property string caption: ""
  // Text shown instead of the slider when there is no device.
  property string emptyText: ""
  // Channel state: {present, volume, muted, level}.
  property var channel: ({
      present: false,
      volume: 0,
      muted: false,
      level: 0
    })
  // Device rows: [{key, label, glyph, detail, active, available}].
  property var devices: []
  // Cursor here: -2 none, -1 the slider row, 0.. a device row.
  property int cursor: -2

  // Emitted with a new volume from the slider.
  signal volumeMoved(real value)
  // Emitted when the slider is right-clicked.
  signal muteToggled
  // Emitted when device row INDEX is chosen.
  signal deviceChosen(int index)
  // Emitted when the pointer enters the slider row (-1) or device row INDEX.
  signal rowHovered(int index)

  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: Math.max(captionText.implicitHeight, levelText.implicitHeight)
    Text {
      id: captionText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: section.caption
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Text {
      id: levelText
      objectName: "levelText"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: section.channel.present
      text: section.channel.muted ? "muted" : Math.round((slider.dragging ? slider.liveValue : section.channel.volume) * 100) + "%"
      color: Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
  Text {
    objectName: "emptyText"
    visible: !section.channel.present
    text: section.emptyText
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
  Item {
    width: parent.width
    height: slider.implicitHeight + Style.space(6)
    visible: section.channel.present
    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.width: section.cursor === -1 ? 1 : 0
      border.color: Aranea.DesignTokens.accent
    }
    Aranea.FilamentSlider {
      id: slider
      objectName: "channelSlider"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      value: section.channel.volume
      muted: section.channel.muted
      level: section.channel.level
      onMoved: function (value) {
        section.volumeMoved(value)
      }
      onRightClicked: section.muteToggled()
    }
    HoverHandler {
      onHoveredChanged: if (hovered)
        section.rowHovered(-1)
    }
  }
  Repeater {
    model: section.devices
    Aranea.NodeDeviceRow {
      required property var modelData
      required property int index
      objectName: "deviceRow"
      width: section.width
      glyph: modelData.glyph
      label: modelData.label
      detail: modelData.detail
      active: modelData.active
      available: modelData.available
      hasCursor: section.cursor === index
      onChosen: section.deviceChosen(index)
      onEntered: section.rowHovered(index)
    }
  }
}
