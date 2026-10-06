// Presentational group header for the notification inbox: the collapse
// glyph, the app and its count, and a close glyph. The header lights with
// the shared hover fill after a real pointer move. The close tint follows
// only real pointer moves when a PointerMoveGate is set (plain hover
// without one). The row records its key under each press and offers
// clickSettled() so NotificationList can refuse a click whose row changed
// or moved under a still pointer.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../../araneadev.shared" as Aranea
import "../../araneadev.shared/ClickSettle.js" as ClickSettle

RowLayout {
  id: row

  // Application name used as the group label and action key.
  property string app: ""
  // Number of notifications represented by this group.
  property int count: 0
  // Whether the group's entries are currently hidden.
  property bool collapsed: false
  // Font family supplied by the containing panel.
  property string fontFamily: Aranea.Typography.uiFamily
  // Main text colour.
  property color foreground: Color.popups.text
  // Accent colour used while the close action is hovered.
  property color accent: Color.notifications.countdown
  // Muted colour for the close action at rest.
  property color dim: Qt.darker(foreground, 1.4)
  // Optional PointerMoveGate (qs.Ui) carrying layoutChangedAt; with it the
  // close tint follows only real moves and clickSettled() honours the
  // layout stamp.
  property var pointerGate: null
  // The center row's key (InboxLogic.rowKey); recorded into pressedKey on
  // every press.
  property string rowKey: ""
  // The row key under the last press (header or close).
  property string pressedKey: ""
  // When the row was built (Date.now()), for clickSettled().
  property real createdAt: 0
  // When the gate last accepted a real pointer move onto the row's close
  // (Date.now()), 0 for never.
  property real pointerMovedAt: 0
  // Whether the close glyph is tinted (a real move onto it through the
  // gate, or plain hover without one).
  property bool closeHot: false

  // Emitted when the group header is clicked.
  signal groupClicked
  // Emitted when the close affordance is clicked.
  signal closeRequested

  // Whether a pointer click may act on this row: always without a gate;
  // with one, ClickSettle over the row's creation, the gate's
  // layoutChangedAt and the last real pointer move.
  function clickSettled(): bool {
    if (!row.pointerGate)
      return true
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: row.createdAt,
      movedAt: row.pointerMovedAt,
      layoutChangedAt: Number(row.pointerGate.layoutChangedAt) || 0
    })
  }

  spacing: Style.space(6)
  Component.onCompleted: row.createdAt = Date.now()
  // Another group now fills this row: drop the tint the previous one had.
  onRowKeyChanged: row.closeHot = false

  Text {
    id: title
    objectName: "groupTitle"
    text: String.fromCodePoint(row.collapsed ? 0x25B8 : 0x25BE) + " " + row.app + " " + String.fromCodePoint(0x00B7) + " " + row.count
    color: row.foreground
    font.family: row.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
    Layout.fillWidth: true

    Aranea.HoverTint {
      z: -1
      pointerGate: row.pointerGate
    }
    MouseArea {
      id: titleArea
      anchors.fill: parent
      hoverEnabled: !!row.pointerGate
      cursorShape: Qt.PointingHandCursor
      onPressed: row.pressedKey = row.rowKey
      onPositionChanged: function (mouse) {
        if (row.pointerGate && row.pointerGate.moved(titleArea, mouse))
          row.pointerMovedAt = Date.now()
      }
      onClicked: {
        row.groupClicked()
        // A press is used once.
        row.pressedKey = ""
      }
    }
  }

  Text {
    id: close
    objectName: "groupClose"
    text: String.fromCodePoint(0x2715)
    color: (row.pointerGate ? row.closeHot : closeArea.containsMouse) ? row.accent : row.dim
    font.family: Aranea.Typography.iconFamily
    font.pixelSize: Style.font.body
    // Same right inset as the card's close button: the card border plus its
    // content margin (NotificationCard: border Math.max(1, Style.space(1)), Layout.rightMargin Style.space(12)).
    Layout.rightMargin: Math.max(1, Style.space(1)) + Style.space(12)

    MouseArea {
      id: closeArea
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPressed: row.pressedKey = row.rowKey
      onPositionChanged: function (mouse) {
        if (row.pointerGate && row.pointerGate.moved(closeArea, mouse)) {
          row.pointerMovedAt = Date.now()
          row.closeHot = true
        }
      }
      onExited: row.closeHot = false
      onClicked: {
        row.closeRequested()
        row.pressedKey = ""
      }
    }
  }
}
