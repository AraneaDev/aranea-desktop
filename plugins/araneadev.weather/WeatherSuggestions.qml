// The Aranea Weather dropdown's place suggestions while editing: one row
// per geocoding suggestion (a web node, the name and its region), keyed by
// name and coordinates. The Repeater's model is the row count, so a new
// highlight, or an equal list rebuilt by the host, never rebuilds a row.
// The highlighted row (the one Enter commits) lights its node and name; the
// keyboard cursor outline shows on it only while the host's cursor is
// active, never on hover. A click remembers the key under the press and is
// refused when the row's key has changed by the release, or within 300 ms
// of the dropdown's layout shifting unless the pointer has really moved
// onto it since. Pure view: plain inputs in, signals out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Column {
  id: list

  // Suggestion rows: [{key, name, description}].
  property var rows: []
  // The highlighted row's index, or -1 for none.
  property int highlight: -1
  // Whether the keyboard cursor outline shows on the highlighted row.
  property bool cursorActive: false
  // The dropdown's PointerMoveGate, carrying layoutChangedAt.
  property var pointerGate: null

  // Emitted on a settled click on row INDEX, with the KEY it held when
  // pressed.
  signal picked(int index, string key)
  // Emitted when the pointer really moves onto row INDEX.
  signal hovered(int index)

  // The key of row INDEX, or "".
  function keyAt(index) {
    var row = list.rows[index]
    return row && typeof row.key === "string" ? row.key : ""
  }

  spacing: 0

  Repeater {
    model: list.rows.length
    Item {
      id: row
      required property int index
      // This row's suggestion, read live so the row is never rebuilt.
      readonly property var suggestion: list.rows[row.index] || ({})
      // The row's key (name and coordinates).
      readonly property string key: list.keyAt(row.index)
      // Whether this is the row Enter commits.
      readonly property bool highlighted: row.index === list.highlight
      // Whether the keyboard cursor outline shows here.
      readonly property bool hasCursor: list.cursorActive && row.highlighted
      // When the row was built (Date.now()).
      property real createdAt: 0
      // When the gate last accepted a real pointer move onto the row.
      property real pointerMovedAt: 0
      // The key under the last press, compared on release.
      property string pressedKey: ""

      // Whether a pointer click may act on this row (ClickSettle).
      function clickSettled() {
        return ClickSettle.clickSettled({
          now: Date.now(),
          createdAt: row.createdAt,
          movedAt: row.pointerMovedAt,
          layoutChangedAt: list.pointerGate ? Number(list.pointerGate.layoutChangedAt) || 0 : 0
        })
      }

      objectName: "suggestionRow"
      width: list.width
      implicitHeight: Style.space(28)
      Component.onCompleted: row.createdAt = Date.now()

      Rectangle {
        // The keyboard cursor outline.
        objectName: "cursorOutline"
        anchors.fill: parent
        color: row.hasCursor ? Util.alpha(Aranea.DesignTokens.accent, 0.08) : "transparent"
        border.width: row.hasCursor ? 1 : 0
        border.color: Aranea.DesignTokens.accent
      }
      Rectangle {
        id: node
        width: Style.space(8)
        height: width
        rotation: 45
        x: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        color: row.highlighted ? Aranea.DesignTokens.accent : "transparent"
        border.width: 1
        border.color: row.highlighted ? Aranea.DesignTokens.accent : Util.alpha(Aranea.DesignTokens.foreground, 0.22)
      }
      Text {
        id: name
        objectName: "suggestionName"
        anchors.left: node.right
        anchors.leftMargin: Style.space(12)
        anchors.right: region.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.suggestion.name || ""
        elide: Text.ElideRight
        color: row.highlighted ? Aranea.DesignTokens.accent : Aranea.DesignTokens.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        id: region
        objectName: "suggestionRegion"
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.suggestion.description || ""
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: row.pressedKey = row.key
        onPositionChanged: function (mouse) {
          if (list.pointerGate && list.pointerGate.moved(rowMouse, mouse)) {
            row.pointerMovedAt = Date.now()
            list.hovered(row.index)
          }
        }
        onClicked: if (row.clickSettled() && row.pressedKey !== "" && row.pressedKey === row.key)
          list.picked(row.index, row.pressedKey)
      }
    }
  }
}
