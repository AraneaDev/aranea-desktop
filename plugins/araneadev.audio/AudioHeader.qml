// Header of the Aranea audio dropdown: the shared DropdownHeader with a
// mute-all switch in its trailing slot. Pure view: plain inputs in,
// signals out. (glyph, title and caption come from DropdownHeader.) A
// click on the switch within 300 ms of the dropdown's layout shifting
// (pointerGate.layoutChangedAt) is ignored unless the pointer has really
// moved onto it since.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Aranea.DropdownHeader {
  id: header
  refined: true

  // Mood caption under the title, e.g. "Cranked up".
  property string mood: ""
  // Whether any channel is unmuted.
  property bool anyAudible: true
  // Whether the keyboard cursor is on the mute-all switch.
  property bool hasCursor: false
  // The switch's tooltip, e.g. "Mute" (stock's toggleHint).
  property string hint: ""
  // The switch's tooltip, exposed for tests.
  readonly property alias hintTip: tip
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from the
  // switch moving under a still pointer.
  property var pointerGate: null
  // When the gate last accepted a real pointer move onto the switch
  // (Date.now()), 0 for never.
  property real switchMovedAt: 0

  // Emitted when the mute-all switch is toggled.
  signal toggleAll
  // Emitted when the pointer enters the switch.
  signal entered

  // Whether a pointer click may toggle the switch (its clickGate): settled
  // since the dropdown's last layout shift, or moved onto since.
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      movedAt: header.switchMovedAt,
      layoutChangedAt: header.pointerGate ? Number(header.pointerGate.layoutChangedAt) || 0 : 0
    })
  }

  objectName: "audioHeader"
  title: "Audio"
  caption: header.mood

  Row {
    spacing: Style.space(8)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "MUTE ALL"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0
    }
    Aranea.FilamentSwitch {
      objectName: "muteSwitch"
      anchors.verticalCenter: parent.verticalCenter
      checked: header.anyAudible
      hasCursor: header.hasCursor
      clickGate: header
      onToggled: header.toggleAll()
      HoverHandler {
        id: switchHover
        onHoveredChanged: if (hovered && !header.pointerGate)
          header.entered()
        onPointChanged: if (header.pointerGate && switchHover.hovered && header.pointerGate.moved(switchHover.parent, {
          x: switchHover.point.position.x,
          y: switchHover.point.position.y
        })) {
          header.switchMovedAt = Date.now()
          header.entered()
        }
      }
      PanelToolTip {
        id: tip
        fontFamily: Aranea.Typography.uiFamily
        visible: switchHover.hovered && header.hint !== ""
        text: header.hint
      }
    }
  }
}
