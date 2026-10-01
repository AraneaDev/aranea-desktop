// One device list (Connected, Paired or Available) in the Aranea
// Bluetooth dropdown: a caption row with the count, a Repeater of
// Aranea.NodeDeviceRow, each with an optional forget button and a
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
        onChosen: section.primary(wrapper.index)
        onEntered: section.rowHovered(wrapper.index)

        // The only item in NodeDeviceRow's default (trailing) slot, so the
        // slot's childrenRect sizing stays just the button's own size: the
        // tooltips and the right-click area below sit outside it instead.
        // width/height are forced to 0 while hidden: NodeDeviceRow's
        // trailing slot sizes to childrenRect, which (unlike layout
        // anchoring) counts invisible children's geometry too, so an
        // implicitly-sized hidden button would still push the detail text
        // left of it.
        Item {
          id: forgetBtn
          objectName: "forgetButton"
          // Whether this row can be forgotten and either the pointer is
          // over the row or the keyboard cursor sits on it.
          readonly property bool shown: !!wrapper.modelData.forgettable && (devRow.hovered || section.cursor === wrapper.index)
          // Whether the keyboard cursor's action (not just the row) is here.
          readonly property bool bright: section.cursor === wrapper.index && section.cursorAction

          visible: shown
          anchors.verticalCenter: parent.verticalCenter
          width: shown ? forgetLabel.implicitWidth + Style.space(12) : 0
          height: shown ? forgetLabel.implicitHeight + Style.space(4) : 0

          // Directly callable from tests, like NodeDeviceRow.activate().
          function activate() {
            section.forget(wrapper.index)
          }

          Rectangle {
            id: forgetBorder
            objectName: "forgetBorder"
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: forgetBtn.bright ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.foreground, 0.22)
          }
          Text {
            id: forgetLabel
            objectName: "forgetLabel"
            anchors.centerIn: parent
            text: String.fromCodePoint(0xf0156) + " forget"
            color: forgetBtn.bright ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.urgent, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: forgetBtn.activate()
          }
          // Non-blocking: only observes hover, never intercepts the click
          // above. Scoped to the button's own (small) bounds, so it fires
          // true entering it and false leaving it, independent of the
          // row's own, much larger, hover area.
          HoverHandler {
            id: forgetHover
            onHoveredChanged: section.actionHovered(wrapper.index, hovered)
          }
        }
      }
      // The row's Connect/Disconnect/Pair tooltip, hidden while the forget
      // button's own tooltip (below) is showing instead.
      PanelToolTip {
        visible: devRow.hovered && !forgetHover.hovered && section.rowTooltip !== ""
        text: section.rowTooltip
      }
      PanelToolTip {
        visible: forgetHover.hovered
        text: "Forget"
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
