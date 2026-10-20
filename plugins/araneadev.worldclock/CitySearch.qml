// In-place city search. The focused editor owns all keys while adding.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: search
  // Runtime font token object; the host supplies its members dynamically.
  readonly property var fontSizes: Style.font
  // Current city search text.
  property string query: ""
  // Ranked city search results from the bundled catalog.
  property var matches: []
  // Reports a named user action and its scalar argument to the controller.
  signal action(string name, var arg)
  // Hands keyboard focus to the city editor after its layout is visible.
  function focusQuery() {
    editor.forceActiveFocus()
  }
  onVisibleChanged: if (visible)
    Qt.callLater(focusQuery)
  Component.onCompleted: if (visible)
    Qt.callLater(focusQuery)
  Item {
    width: parent.width
    height: Style.space(32)
    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Aranea.DesignTokens.accent, 0.04)
      border.width: 1
      border.color: Util.alpha(Aranea.DesignTokens.accent, 0.35)
    }
    Aranea.UiLabel {
      x: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: "+"
      color: Aranea.DesignTokens.accent
      font.pixelSize: search.fontSizes.body
    }
    TextInput {
      id: editor
      objectName: "cityQuery"
      anchors.left: parent.left
      anchors.leftMargin: Style.space(32)
      anchors.right: count.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: search.query
      color: Aranea.DesignTokens.foreground
      selectionColor: Util.alpha(Aranea.DesignTokens.accent, 0.25)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: search.fontSizes.body
      clip: true
      selectByMouse: true
      onTextEdited: search.action("queryChanged", text)
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape)
          search.action("cancelAdd", null)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          for (let i = 0; i < search.matches.length; i++)
            if (search.matches[i].selected) {
              search.action("add", i)
              break
            }
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
          let selected = search.matches.findIndex(function (m) {
            return !!m.selected
          })
          search.action("matchSelect", Math.max(0, Math.min(search.matches.length - 1, selected + (event.key === Qt.Key_Down ? 1 : -1))))
        } else {
          event.accepted = false
          return
        }
        event.accepted = true
      }
    }
    Aranea.UiLabel {
      id: count
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: search.matches.length + " matches"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.5)
    }
  }
  Repeater {
    model: search.matches
    Item {
      id: match
      required property var modelData
      required property int index
      objectName: "cityMatch"
      width: search.width
      height: Style.space(30)
      Rectangle {
        anchors.fill: parent
        visible: !!match.modelData.selected
        color: Util.alpha(Aranea.DesignTokens.accent, 0.06)
      }
      Aranea.HoverTint {}
      Rectangle {
        visible: !!match.modelData.selected
        width: Math.max(1, Style.space(2))
        height: parent.height - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        color: Aranea.DesignTokens.accent
      }
      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(32)
        anchors.right: offset.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: match.modelData.name + (match.modelData.country ? " · " + match.modelData.country : "") + (match.modelData.abbrev ? " · " + match.modelData.abbrev : "")
        elide: Text.ElideRight
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: search.fontSizes.body
      }
      Text {
        id: offset
        objectName: "matchOffset"
        anchors.right: time.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(70)
        horizontalAlignment: Text.AlignRight
        text: match.modelData.offset || ""
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: search.fontSizes.caption
      }
      Text {
        id: time
        objectName: "matchTime"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(50)
        horizontalAlignment: Text.AlignRight
        text: match.modelData.time || "-:-"
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: search.fontSizes.body
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onEntered: search.action("matchSelect", match.index)
        onClicked: search.action("add", match.index)
      }
    }
  }
}
