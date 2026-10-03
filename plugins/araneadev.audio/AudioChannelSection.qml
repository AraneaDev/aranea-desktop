// One audio channel (Output or Input) in the Aranea audio dropdown: the
// caption and level, a filament slider with the live signal glow, and
// the device list. Pure view: plain inputs in, signals out. A press on
// the slider within 300 ms of the dropdown's layout shifting
// (pointerGate.layoutChangedAt) is ignored unless the pointer has really
// moved onto it since; device rows settle their clicks the same way, and
// the pending default's row pulses (busy).
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

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
  // Device rows: [{key, label, glyph, detail, active, available, busy}];
  // the key is the node id, busy pulses the pending default's row.
  property var devices: []
  // Cursor here: -2 none, -1 the slider row, 0.. a device row.
  property int cursor: -2
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from the
  // slider row or a device row moving under a still pointer.
  property var pointerGate: null

  // Emitted with a new volume from the slider.
  signal volumeMoved(real value)
  // Emitted when the slider is right-clicked (settled, as a press is).
  signal muteToggled
  // Emitted when device row INDEX, holding KEY, is chosen.
  signal deviceChosen(int index, string key)
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
      font.pixelSize: Style.font.body
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
    id: sliderRow
    // When the gate last accepted a real pointer move over the slider row
    // (Date.now()), 0 for never.
    property real pointerMovedAt: 0

    // Whether a pointer press may move the slider (its clickGate): settled
    // since the dropdown's last layout shift, or moved onto since.
    function clickSettled() {
      return ClickSettle.clickSettled({
        now: Date.now(),
        movedAt: sliderRow.pointerMovedAt,
        layoutChangedAt: section.pointerGate ? Number(section.pointerGate.layoutChangedAt) || 0 : 0
      })
    }

    width: parent.width
    height: slider.implicitHeight + Style.space(6)
    visible: section.channel.present
    Rectangle {
      // The keyboard cursor outline.
      objectName: "cursorOutline"
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
      clickGate: sliderRow
      onMoved: function (value) {
        section.volumeMoved(value)
      }
      onRightClicked: if (sliderRow.clickSettled())
        section.muteToggled()
    }
    HoverHandler {
      id: sliderHover
      onHoveredChanged: if (hovered && !section.pointerGate)
        section.rowHovered(-1)
      onPointChanged: if (section.pointerGate && sliderHover.hovered && section.pointerGate.moved(sliderHover.parent, {
        x: sliderHover.point.position.x,
        y: sliderHover.point.position.y
      })) {
        sliderRow.pointerMovedAt = Date.now()
        section.rowHovered(-1)
      }
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
      busy: !!modelData.busy
      hasCursor: section.cursor === index
      pointerGate: section.pointerGate
      onChosen: section.deviceChosen(index, String(modelData.key))
      onEntered: if (modelData.available)
        section.rowHovered(index)
    }
  }
}
