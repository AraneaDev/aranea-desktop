// One device list (Connected, Paired or Available) in the Aranea
// Bluetooth dropdown: a caption row with the count, a Repeater of
// Aranea.NodeDeviceRow, each with an optional Aranea.ForgetButton and a
// right-click MouseArea for the secondary action. Pure view: plain
// inputs in, signals out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: section

  // This section's identity, used only to build the emitted action
  // payloads' "section" field: "connected", "known" or "discovered".
  property string sectionName: ""
  // Section caption, e.g. "CONNECTED".
  property string caption: ""
  // Trailing badge text next to the caption, e.g. a count or "scanning".
  property string countText: ""
  // Device rows: [{key, label, glyph, detail, busy, forgettable}].
  property var rows: []
  // Address -> live signal level (0..3), for Available rows' node glow.
  property var signals: ({})
  // Cursor row index here, or -2 when the keyboard cursor isn't on this section.
  property int cursor: -2
  // Whether the keyboard cursor sits on the cursor row's forget action.
  property bool cursorAction: false
  // Tooltip shown on a row's hover: "Connect", "Disconnect" or "Pair".
  property string rowTooltip: ""
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from a
  // device row moving under a still pointer.
  property var pointerGate: null

  // Emitted when row INDEX is chosen (connect, disconnect or pair).
  signal primary(int index)
  // Emitted when row INDEX is right-clicked.
  signal secondary(int index)
  // Emitted when row INDEX's forget button is clicked.
  signal forget(int index)
  // Emitted when the pointer enters row INDEX.
  signal rowHovered(int index)
  // Emitted when the pointer enters (HOVERED true) or leaves (false) row
  // INDEX's forget button specifically, distinct from the row itself.
  signal actionHovered(int index, bool hovered)

  // The row wrapper at INDEX (objectName "deviceRowWrapper", carrying its
  // own "index"), or null when out of range. Lets a host, BluetoothDropdown's
  // ensureVisible, locate and scroll a specific row without its own copy
  // of the row model.
  function rowWrapperAt(index) {
    return repeater.itemAt(index)
  }

  visible: section.rows.length > 0
  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: captionText.implicitHeight
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
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: section.countText
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
  Repeater {
    id: repeater
    model: section.rows
    Item {
      id: wrapper
      required property var modelData
      required property int index
      objectName: "deviceRowWrapper"
      width: section.width
      implicitHeight: devRow.implicitHeight

      Aranea.NodeDeviceRow {
        id: devRow
        objectName: "deviceRow"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: wrapper.modelData.glyph
        label: wrapper.modelData.label
        detail: wrapper.modelData.detail
        active: section.sectionName === "connected"
        busy: !!wrapper.modelData.busy
        signal: section.sectionName === "discovered" ? (section.signals[wrapper.modelData.key] !== undefined ? section.signals[wrapper.modelData.key] : -1) : -1
        hasCursor: section.cursor === wrapper.index
        pointerGate: section.pointerGate
        onChosen: section.primary(wrapper.index)
        onEntered: section.rowHovered(wrapper.index)

        // The only item in NodeDeviceRow's default (trailing) slot, so the
        // slot's childrenRect sizing stays just the button's own size: the
        // row tooltip and the right-click area below sit outside it.
        Aranea.ForgetButton {
          id: forgetBtn
          forgettable: !!wrapper.modelData.forgettable
          rowHovered: devRow.hovered
          hasCursor: section.cursor === wrapper.index
          cursorAction: section.cursorAction
          pointerGate: section.pointerGate
          onClicked: section.forget(wrapper.index)
          onPointerEntered: section.actionHovered(wrapper.index, true)
          onPointerLeft: section.actionHovered(wrapper.index, false)
        }
      }
      // The row's Connect/Disconnect/Pair tooltip, hidden while the forget
      // button's own tooltip is showing instead.
      PanelToolTip {
        visible: devRow.hovered && !forgetBtn.hovered && section.rowTooltip !== ""
        text: section.rowTooltip
      }
      // A right-click signal NodeDeviceRow doesn't have: a dedicated
      // overlay rather than changing its left-click (shared with audio)
      // behaviour. RightButton only, so left-clicks and hover reach the
      // row and forget button beneath it untouched.
      MouseArea {
        id: secondaryArea
        objectName: "secondaryArea"
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: section.secondary(wrapper.index)
      }
    }
  }
}
