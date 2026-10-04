// Result list and fold affordances for the menu card.
//
// Two separate highlights. The keyboard cursor is the mint outline on
// selectedIndex, drawn while cursorActive (Menu.qml: whenever Enter has a
// target); hover never moves it. Hover draws the menu's
// selected fill on the row under the pointer, but only after a real
// pointer move (PointerMoveGate), and it clears when the rows change or
// scroll under the pointer. Clicks are keyed by the row's item id: a
// press records it and the release is refused when the row holds another
// item by then, or within 300 ms of the rows changing or scrolling under
// the pointer (layoutChangedAt, the list's own scroll stamp) unless the
// pointer has really moved onto the row since (ClickSettle).
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Item {
  id: results
  // Public contract member.
  property var model: null
  // Public contract member.
  property var appLibrary: null
  // Public contract member.
  property int selectedIndex: -1
  // Whether the keyboard outline shows on selectedIndex.
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
  // When the menu's rows last changed under a still pointer (Menu.qml's
  // layoutChangedAt), 0 for never.
  property real layoutChangedAt: 0
  // When the list last scrolled (Date.now()), 0 for never: a scroll moves
  // the rows under a still pointer.
  property real scrolledAt: 0
  // The gate that tells real pointer moves from rows moving under a still
  // pointer; the window shares its own, else the list's.
  property var pointerGate: ownGate
  // The row the pointer really moved onto (hover fill), -1 for none.
  property int hoveredIndex: -1
  // The item id that row held when hovered; the fill shows only while the
  // row still holds it.
  property string hoveredKey: ""

  // Drops the hover fill: the rows moved or changed under the pointer.
  function clearHover(): void {
    results.hoveredIndex = -1
    results.hoveredKey = ""
  }

  onLayoutChangedAtChanged: results.clearHover()
  // Emitted for a settled left click on row INDEX that still holds KEY
  // (its item id) on release.
  signal rowActivated(int index, string key)
  // Emitted for a settled right click on an app row that still holds its
  // item id on release, with the row's APPID.
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
    onContentYChanged: {
      results.scrolledAt = Date.now()
      results.clearHover()
    }
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
      objectName: "menuRow"
      required property int index
      required property string itemId
      required property string kind
      required property string icon
      required property string iconFont
      required property string appIcon
      required property string appId
      required property string label
      required property string detail
      required property int childCount
      readonly property bool hasCursor: results.cursorActive && index === results.selectedIndex
      // Whether the pointer really moved onto this row and it still holds
      // the same item (the hover fill).
      readonly property bool hovered: results.hoveredIndex === index && results.hoveredKey === itemId
      // Whether the row's text is lit (hovered or under the keyboard cursor).
      readonly property bool lit: hovered || hasCursor
      readonly property bool isApp: kind === "app"
      readonly property bool hasIcon: icon.length > 0 || isApp
      // When this row was built (Date.now()).
      property real createdAt: 0
      // When the gate last accepted a real pointer move onto this row.
      property real pointerMovedAt: 0
      // The item id under the last press, compared on release.
      property string pressedKey: ""

      // Whether a pointer click may act on this row (ClickSettle).
      function clickSettled(): bool {
        return ClickSettle.clickSettled({
          now: Date.now(),
          createdAt: row.createdAt,
          movedAt: row.pointerMovedAt,
          layoutChangedAt: Math.max(results.layoutChangedAt, results.scrolledAt)
        })
      }

      Component.onCompleted: row.createdAt = Date.now()

      width: ListView.view.width
      height: results.rowHeightForDetail ? results.rowHeightForDetail(detail) : Style.space(44)
      radius: results.cornerRadius
      // The hover fill only, as the pickers draw it: no border.
      color: hovered ? results.selectedBackground : "transparent"

      Rectangle {
        // The keyboard cursor outline (mint, keyboard only).
        objectName: "cursorOutline"
        anchors.fill: parent
        radius: results.cornerRadius
        visible: row.hasCursor
        color: Util.alpha(Aranea.DesignTokens.accent, 0.08)
        border.width: 1
        border.color: Aranea.DesignTokens.accent
      }

      Aranea.InkText {
        id: iconText
        visible: row.hasIcon && !row.isApp
        text: row.icon
        color: row.lit ? results.selectedText : results.foreground
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
          color: row.lit ? results.selectedText : results.foreground
          font.family: results.fontFamily
          font.pixelSize: results.menuFontScale * Style.font.bodySmall
          font.letterSpacing: results.menuLetterSpacing
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: row.detail
          visible: (results.fullRootHeader || results.filterText || row.kind === "dmenu") && row.detail.length > 0
          color: row.lit ? results.selectedText : results.foreground
          opacity: row.lit ? 0.7 : 0.52
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
        color: row.lit ? results.selectedText : results.foreground
        opacity: 0.36
        font.family: results.fontFamily
        font.pixelSize: results.menuFontScale * Style.font.body
      }

      MouseArea {
        id: rowArea
        objectName: "rowArea"
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // Hover fills the row and feeds the settle rule; it never moves
        // the keyboard cursor.
        onPositionChanged: function (mouse) {
          if (results.pointerGate && results.pointerGate.moved(rowArea, mouse)) {
            row.pointerMovedAt = Date.now()
            results.hoveredIndex = row.index
            results.hoveredKey = row.itemId
          }
        }
        onExited: if (results.hoveredIndex === row.index)
          results.clearHover()
        onPressed: row.pressedKey = row.itemId
        onClicked: function (mouse) {
          var key = row.pressedKey
          row.pressedKey = ""
          if (!key || key !== row.itemId || !row.clickSettled())
            return
          if (mouse.button === Qt.RightButton) {
            if (row.isApp)
              results.appContextRequested(row.appId)
            return
          }
          results.rowActivated(row.index, key)
        }
      }
    }
  }

  // The list's own gate, used when the window shares none (tests).
  PointerMoveGate {
    id: ownGate
    referenceItem: results
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
