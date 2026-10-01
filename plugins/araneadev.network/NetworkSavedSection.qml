// The "Saved, out of range" section of the Aranea Network dropdown: saved
// Wi-Fi profiles the scan doesn't see, as dimmed NodeDeviceRows with a
// forget button on hover or under the cursor. A row click does nothing
// (there's nothing in range to connect to). Hidden when empty. Pure view:
// plain inputs in, signals out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section

  // Saved rows from NetworkLogic.savedRows: [{key, label, detail}], key
  // being the profile's uuid.
  property var rows: []
  // Per-profile action state, keyed by uuid: {uuid: {busy, text}}. A
  // profile being forgotten breathes and reads its text ("Forgetting…").
  property var status: ({})
  // The keyboard cursor's row, or -1 when the cursor isn't here.
  property int cursorIndex: -1
  // Whether the keyboard cursor sits on the cursor row's forget action.
  property bool cursorAction: false
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from a row
  // moving under a still pointer.
  property var pointerGate: null

  // Emitted when row INDEX's forget button is clicked.
  signal forget(int index)
  // Emitted when the pointer moves onto row INDEX (ACTION false) or its
  // forget button (ACTION true), through the gate.
  signal hovered(int index, bool action)
  // Emitted when the pointer leaves row INDEX's forget button.
  signal actionLeft(int index)

  // The row at INDEX (objectName "savedRow"), or null when out of range;
  // for ensureVisible.
  function rowWrapperAt(index) {
    return repeater.itemAt(index)
  }

  objectName: "savedSection"
  visible: section.rows.length > 0
  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: captionText.implicitHeight
    Text {
      id: captionText
      objectName: "savedCaption"
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "SAVED, OUT OF RANGE"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Text {
      objectName: "savedCount"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: String(section.rows.length)
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
  Repeater {
    id: repeater
    model: section.rows
    Aranea.NodeDeviceRow {
      id: savedRow
      required property var modelData
      required property int index
      objectName: "savedRow"
      width: section.width
      opacity: 0.7
      glyph: String.fromCodePoint(0xf092e)
      label: savedRow.modelData.label || ""
      // This row's action state.
      readonly property var actionState: section.status ? section.status[savedRow.modelData.key] : undefined
      detail: savedRow.actionState && savedRow.actionState.text ? String(savedRow.actionState.text) : (savedRow.modelData.detail || "")
      busy: !!(savedRow.actionState && savedRow.actionState.busy)
      available: true
      hasCursor: section.cursorIndex === savedRow.index
      pointerGate: section.pointerGate
      onEntered: section.hovered(savedRow.index, false)

      // The trailing slot's only child.
      NetworkForgetButton {
        forgettable: true
        rowHovered: savedRow.hovered
        hasCursor: section.cursorIndex === savedRow.index
        cursorAction: section.cursorAction
        pointerGate: section.pointerGate
        onClicked: section.forget(savedRow.index)
        onPointerEntered: section.hovered(savedRow.index, true)
        onPointerLeft: section.actionLeft(savedRow.index)
      }
    }
  }
}
