// Result list and fold affordances for the menu card.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: results
  // Public contract member.
  property var model: null
  // Public contract member.
  property var appLibrary: null
  // Public contract member.
  property int selectedIndex: -1
  // Public contract member.
  property bool cursorActive: false
  // Public contract member.
  property string filterText: ""
  // Public contract member.
  property bool fullRootHeader: false
  // Public contract member.
  property color background: Color.menu.background
  // Public contract member.
  property color foreground: Color.menu.text
  // Public contract member.
  property color selectedBackground: Color.menu.selectedBackground
  // Public contract member.
  property color selectedText: Color.menu.selectedText
  // Public contract member.
  property color border: Color.menu.border
  // Public contract member.
  property var selectedBorderSpec: Border.none()
  // Public contract member.
  property string fontFamily: Style.font.menuFamily
  // Public contract member.
  property real menuFontScale: 1
  // Public contract member.
  property real menuLetterSpacing: 0
  // Public contract member.
  property int cornerRadius: Style.cornerRadius
  // Public contract member.
  property int rowSpacing: Style.spacing.xs
  // Public contract member.
  property int rowReservedBorderLeft: 0
  // Public contract member.
  property int rowReservedBorderRight: 0
  // Public contract member.
  property int dividerHeight: Style.spacing.md
  // Public contract member.
  property var rowHeightForDetail: null
  // Public contract member.
  signal rowHovered(int index, var row, var point)
  // Public contract member.
  signal rowActivated(int index, var row, int button)
  // Public contract member.
  signal appContextRequested(string appId)

  // Public contract member.
  readonly property alias list: resultList

  ListView {
    id: resultList
    anchors.fill: parent
    model: parent.model
    clip: true
    spacing: parent.rowSpacing
    boundsBehavior: Flickable.StopAtBounds
    section.property: "section"
    section.criteria: ViewSection.FullString

    section.delegate: Item {
      required property string section
      width: ListView.view.width
      height: section === "drilldown" ? results.dividerHeight : 0
      visible: section === "drilldown"
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.spacing.hairline
        color: Util.alpha(results.foreground, 0.2)
      }
    }

    delegate: BorderSurface {
      id: row
      required property int index
      required property string kind
      required property string icon
      required property string iconFont
      required property string appIcon
      required property string appId
      required property string label
      required property string detail
      required property int childCount
      readonly property bool hasCursor: results.cursorActive && index === results.selectedIndex
      readonly property bool isApp: kind === "app"
      readonly property bool hasIcon: icon.length > 0 || isApp

      width: ListView.view.width
      height: results.rowHeightForDetail ? results.rowHeightForDetail(detail) : Style.space(44)
      radius: results.cornerRadius
      color: hasCursor ? results.selectedBackground : "transparent"
      borderSpec: hasCursor ? results.selectedBorderSpec : Border.none()

      Text {
        id: iconText
        visible: row.hasIcon && !row.isApp
        text: row.icon
        color: row.hasCursor ? results.selectedText : results.foreground
        font.family: row.iconFont.length > 0 ? row.iconFont : results.fontFamily
        font.pixelSize: Style.font.iconLarge
        width: Style.space(36)
        horizontalAlignment: Text.AlignHCenter
        anchors.left: parent.left
        anchors.leftMargin: results.rowReservedBorderLeft + Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        anchors.left: row.hasIcon ? iconText.right : parent.left
        anchors.leftMargin: row.hasIcon ? Style.space(6) : results.rowReservedBorderLeft + Style.space(18)
        anchors.right: parent.right
        anchors.rightMargin: results.rowReservedBorderRight + Style.space(22)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        Text {
          width: parent.width
          text: row.label
          color: row.hasCursor ? results.selectedText : results.foreground
          font.family: results.fontFamily
          font.pixelSize: results.menuFontScale * Style.font.bodySmall
          font.letterSpacing: results.menuLetterSpacing
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: row.detail
          visible: (results.fullRootHeader || results.filterText || row.kind === "dmenu") && row.detail.length > 0
          color: row.hasCursor ? results.selectedText : results.foreground
          opacity: row.hasCursor ? 0.7 : 0.52
          font.family: results.fontFamily
          font.pixelSize: results.menuFontScale * Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: results.rowReservedBorderRight + Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: row.kind === "menu" || row.kind === "link" ? "›" : ""
        color: row.hasCursor ? results.selectedText : results.foreground
        opacity: 0.36
        font.family: results.fontFamily
        font.pixelSize: results.menuFontScale * Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: results.rowHovered(row.index, row, {
          x: mouseX,
          y: mouseY
        })
        onPositionChanged: function (mouse) {
          results.rowHovered(row.index, row, mouse)
        }
        onClicked: function (mouse) {
          if (mouse.button === Qt.RightButton && row.isApp) {
            results.appContextRequested(row.appId)
            return
          }
          results.rowActivated(row.index, row, mouse.button)
        }
      }
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Math.min(Style.space(28), parent.height / 2)
    visible: opacity > 0
    opacity: resultList.contentHeight > resultList.height ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height)) : 0
    gradient: Gradient {
      GradientStop {
        position: 0
        color: results.background
      }
      GradientStop {
        position: 1
        color: Util.alpha(results.background, 0)
      }
    }
  }
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.min(Style.space(28), parent.height / 2)
    visible: opacity > 0
    opacity: resultList.contentHeight > resultList.height ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height)) : 0
    gradient: Gradient {
      GradientStop {
        position: 0
        color: Util.alpha(results.background, 0)
      }
      GradientStop {
        position: 1
        color: results.background
      }
    }
  }
}
