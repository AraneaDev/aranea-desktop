// Shared status rail/text row with optional trailing content and click input.
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: row

  property string title: ""
  property string subtitle: ""
  property color railColor: DesignTokens.foreground
  property color titleColor: DesignTokens.foreground
  property color subtitleColor: DesignTokens.foreground
  property real subtitleOpacity: 0.55
  property bool titleBold: true
  property int titleSize: Style.font.subtitle
  property int subtitleSize: Style.font.body
  property int subtitleElide: Text.ElideNone
  property int rowHeight: Style.space(50)
  property color background: "transparent"
  property color hoverBackground: Util.alpha(DesignTokens.foreground, 0.06)
  property bool highlighted: false
  property bool clickable: false
  default property alias trailingContent: trailing.data
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
    anchors.rightMargin: Style.space(14)
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
