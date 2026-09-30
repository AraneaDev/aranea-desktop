// Result list and fold affordances for the menu card.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

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
  // Inner horizontal inset of row content (the highlight's bleed).
  property int rowInset: Style.spacing.rowPaddingX
  // Width of the icon column.
  property int iconSlot: Style.space(24)
  // Height of the peeking row at the fold (MenuStyle.rowPeek).
  property int foldPeek: Style.space(22)
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
        anchors.leftMargin: results.rowInset
        anchors.right: parent.right
        anchors.rightMargin: results.rowInset
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

      Aranea.InkText {
        id: iconText
        visible: row.hasIcon && !row.isApp
        text: row.icon
        color: row.hasCursor ? results.selectedText : results.foreground
        font.family: row.iconFont.length > 0 ? row.iconFont : results.fontFamily
        font.pixelSize: Style.font.iconLarge
        horizontalAlignment: Text.AlignLeft
        anchors.left: parent.left
        anchors.leftMargin: results.rowReservedBorderLeft + results.rowInset
        anchors.verticalCenter: parent.verticalCenter
      }

      Image {
        id: appIconImage
        visible: row.isApp
        width: Style.font.iconLarge
        height: Style.font.iconLarge
        fillMode: Image.PreserveAspectFit
        // Decode at physical pixels so desktop icons remain sharp on HiDPI.
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        source: row.isApp && results.appLibrary && results.appLibrary.iconSource ? results.appLibrary.iconSource(row.appIcon) : ""
        asynchronous: true
        anchors.left: parent.left
        anchors.leftMargin: results.rowReservedBorderLeft + results.rowInset
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        // One label column for every row with an icon, whatever the glyph's width.
        anchors.left: parent.left
        anchors.leftMargin: results.rowReservedBorderLeft + results.rowInset + (row.hasIcon ? results.iconSlot + Style.space(10) : 0)
        anchors.right: parent.right
        anchors.rightMargin: results.rowReservedBorderRight + results.rowInset + Style.space(14)
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

      Aranea.InkText {
        anchors.right: parent.right
        anchors.rightMargin: results.rowReservedBorderRight + results.rowInset
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
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
    // Fade only the lower half of the peeking row: the cut-off row itself is
    // the fold affordance and must stay readable.
    height: Math.min(Math.round(results.foldPeek / 2), parent.height / 2)
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
