// Presentational result row for the clipboard picker.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import "../../araneadev.shared" as Aranea

Rectangle {
  id: row

  // Index in the owning clipboard display model.
  required property int index
  // Semantic kind used to choose the fallback glyph.
  required property string kind
  // Main one-line clipboard title.
  required property string title
  // Secondary metadata shown on the right.
  required property string detail
  // Optional image preview URL.
  required property string previewImage
  // Optional source colour label.
  required property string colour
  // Optional parsed colour swatch.
  required property string swatch
  // Whether the entry is pinned.
  required property bool pinned
  // Whether the entry contains a secret.
  required property bool secret
  // Whether keyboard selection is on this row.
  property bool hasCursor: false
  // Glyph shown when there is no image or colour swatch.
  property string glyph: ""
  // Font family supplied by the clipboard window.
  property string fontFamily: Style.font.menuFamily
  // Main row text colour.
  property color foreground: Color.menu.text
  // Accent colour for the selected row and icon.
  property color selectedText: Color.menu.selectedText
  // Selected-row background colour.
  property color selectedBackground: Color.menu.selectedBackground
  // Row corner radius.
  property real cornerRadius: Style.cornerRadius

  // Emitted while the pointer moves over the row.
  signal pointerMoved(int rowIndex, var item, var mouse)
  // Emitted when the row is clicked.
  signal activated(int rowIndex)

  radius: row.cornerRadius
  color: row.hasCursor ? row.selectedBackground : "transparent"

  Behavior on color {
    ColorAnimation {
      duration: 120
      easing.type: Easing.OutCubic
    }
  }

  Rectangle {
    visible: row.hasCursor
    width: Style.space(2)
    height: parent.height - Style.space(14)
    radius: Style.space(1)
    color: row.selectedText
    opacity: 0.9
    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
  }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    spacing: Style.space(10)

    Item {
      width: Style.space(22)
      height: parent.height

      Image {
        visible: row.previewImage.length > 0
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: parent.width
        source: row.previewImage
        sourceSize: Qt.size(44, 44)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }
      Rectangle {
        visible: row.swatch.length > 0
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        height: Style.space(14)
        radius: Style.space(3)
        color: row.swatch.length > 0 ? row.swatch : "transparent"
        border.width: 1
        border.color: Util.alpha(row.foreground, 0.25)
      }
      Aranea.InkText {
        visible: row.previewImage.length === 0 && row.colour.length === 0
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignLeft
        textFormat: Text.PlainText
        text: row.secret ? "󰌾" : row.glyph
        color: row.hasCursor ? row.selectedText : Util.alpha(row.foreground, 0.7)
        font.family: row.fontFamily
        font.pixelSize: Style.font.icon
      }
    }

    Text {
      width: parent.width - Style.space(22) - detailText.width - parent.spacing * 2
      height: parent.height
      textFormat: Text.PlainText
      text: row.title
      color: row.hasCursor ? row.selectedText : row.foreground
      font.family: row.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      wrapMode: Text.NoWrap
      verticalAlignment: Text.AlignVCenter
    }

    Aranea.InkText {
      id: detailText
      height: parent.height
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: (row.pinned ? "📌 " : "") + row.detail
      color: Util.alpha(row.foreground, 0.5)
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      verticalAlignment: Text.AlignVCenter
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPositionChanged: row.pointerMoved(row.index, row, mouse)
    onClicked: row.activated(row.index)
  }
}
