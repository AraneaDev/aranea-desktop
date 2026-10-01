// The VPN section of the Aranea Network dropdown: a "VPN" caption with
// "N up", and one NodeDeviceRow per VPN or WireGuard profile with a
// trailing FilamentSwitch. A profile being brought up or down breathes; a
// failed one reads "Couldn't connect" in the urgent colour. Pure view:
// plain inputs in, signals out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section

  // VPN rows from NetworkLogic.vpnRows: [{key, glyph, label, detail,
  // active}], key being the profile's uuid.
  property var rows: []
  // Per-profile action state, keyed by uuid: {uuid: {busy, failed}}.
  // Separate from rows so an action never rebuilds them.
  property var status: ({})
  // The keyboard cursor's row, or -1 when the cursor isn't here.
  property int cursorIndex: -1
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from a row
  // moving under a still pointer.
  property var pointerGate: null
  // How many profiles are up.
  readonly property int upCount: section.rows.filter(function (r) {
    return !!r.active
  }).length

  // Emitted when row INDEX's switch or the row itself is clicked.
  signal toggle(int index)
  // Emitted when the pointer moves onto row INDEX (through the gate).
  signal rowHovered(int index)

  // The action state for KEY: {busy, failed}, both false when unknown.
  function statusOf(key) {
    var s = section.status ? section.status[key] : undefined
    return {
      busy: !!(s && s.busy),
      failed: !!(s && s.failed)
    }
  }

  objectName: "vpnSection"
  visible: section.rows.length > 0
  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: captionText.implicitHeight
    Text {
      id: captionText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "VPN"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Text {
      objectName: "vpnCount"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: section.upCount + " up"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
  Repeater {
    model: section.rows
    Aranea.NodeDeviceRow {
      id: vpnRow
      required property var modelData
      required property int index
      // This row's action state.
      readonly property var actionState: section.statusOf(vpnRow.modelData.key)
      objectName: "vpnRow"
      width: section.width
      glyph: vpnRow.modelData.glyph
      label: vpnRow.modelData.label
      detail: vpnRow.actionState.failed ? "Couldn't connect" : vpnRow.modelData.detail
      detailColor: vpnRow.actionState.failed ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      active: !!vpnRow.modelData.active
      busy: vpnRow.actionState.busy
      hasCursor: section.cursorIndex === vpnRow.index
      pointerGate: section.pointerGate
      onChosen: section.toggle(vpnRow.index)
      onEntered: section.rowHovered(vpnRow.index)

      // The only item in the trailing slot, so the slot sizes to it.
      Aranea.FilamentSwitch {
        objectName: "vpnSwitch"
        checked: !!vpnRow.modelData.active
        onToggled: section.toggle(vpnRow.index)
      }
    }
  }
}
