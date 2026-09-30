// Presentational group header for the notification inbox.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: row

  // Application name used as the group label and action key.
  property string app: ""
  // Number of notifications represented by this group.
  property int count: 0
  // Whether the group's entries are currently hidden.
  property bool collapsed: false
  // Font family supplied by the containing panel.
  property string fontFamily: Style.font.family
  // Main text colour.
  property color foreground: Color.popups.text
  // Accent colour used while the close action is hovered.
  property color accent: Color.notifications.countdown
  // Muted colour for the close action at rest.
  property color dim: Qt.darker(foreground, 1.4)

  // Emitted when the group header is clicked.
  signal groupClicked
  // Emitted when the close affordance is clicked.
  signal closeRequested

  spacing: Style.space(6)

  Text {
    id: title
    text: (row.collapsed ? "▸ " : "▾ ") + row.app + " · " + row.count
    color: row.foreground
    font.family: row.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
    Layout.fillWidth: true

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: row.groupClicked()
    }
  }

  Text {
    id: close
    text: "✕"
    color: closeArea.containsMouse ? row.accent : row.dim
    font.family: row.fontFamily
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
      onClicked: row.closeRequested()
    }
  }
}
