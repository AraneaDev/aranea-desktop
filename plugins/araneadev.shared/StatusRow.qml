// Shared status rail/text row with optional trailing content and click input.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: row

  // Primary row title.
  property string title: ""
  // Secondary row subtitle.
  property string subtitle: ""
  // Color of the leading status rail.
  property color railColor: DesignTokens.foreground
  // Primary title color.
  property color titleColor: DesignTokens.foreground
  // Secondary subtitle color.
  property color subtitleColor: DesignTokens.foreground
  // Opacity applied to the subtitle.
  property real subtitleOpacity: 0.55
  // Whether the title uses a bold weight.
  property bool titleBold: true
  // Primary title font size.
  property int titleSize: Style.font.subtitle
  // Secondary subtitle font size.
  property int subtitleSize: Style.font.body
  // Elision mode for the subtitle.
  property int subtitleElide: Text.ElideNone
  // Logical row height.
  property int rowHeight: Style.space(50)
  // Default row background.
  property color background: "transparent"
  // Background shown while hovered or highlighted.
  property color hoverBackground: Util.alpha(DesignTokens.foreground, 0.06)
  // Whether the row is in its highlighted state.
  property bool highlighted: false
  // Whether the row accepts pointer interaction.
  property bool clickable: false
  // Content rendered after the text pair.
  default property alias trailingContent: trailing.data
  // Emitted when a clickable row is activated.
  signal clicked

  implicitHeight: row.rowHeight

  Rectangle {
    anchors.fill: parent
    color: row.clickable && (row.highlighted || pointer.containsMouse) ? row.hoverBackground : row.background
  }

  StatusRail {
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    railColor: row.railColor
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(16)
    // The row is unboxed: its trailing values meet the panel's right content
    // edge, like the header hint and footer actions above and below it.
    anchors.rightMargin: 0
    spacing: Style.space(12)

    StatusTextPair {
      Layout.fillWidth: true
      title: row.title
      subtitle: row.subtitle
      titleColor: row.titleColor
      subtitleColor: row.subtitleColor
      subtitleOpacity: row.subtitleOpacity
      titleBold: row.titleBold
      titleSize: row.titleSize
      subtitleSize: row.subtitleSize
      subtitleElide: row.subtitleElide
    }

    RowLayout {
      id: trailing
      Layout.alignment: Qt.AlignVCenter
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    visible: row.clickable
    hoverEnabled: row.clickable
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }
}
