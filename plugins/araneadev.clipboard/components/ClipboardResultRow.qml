// Result row for the clipboard picker. Two separate highlights: the mint
// outline marks the keyboard cursor (Enter's target, hasCursor); the hover
// fill shows on the row the pointer really moved onto (hovered, set by the
// pane). A click is keyed by the row's entry id and settled (ClickSettle).
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import "../../araneadev.shared" as Aranea
import "../../araneadev.shared/ClickSettle.js" as ClickSettle

Rectangle {
  id: row

  // Index in the owning clipboard display model.
  required property int index
  // Id of the entry the row shows (ClipboardLogic.rowId); clicks are keyed by it.
  required property string entryId
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
  // Whether the keyboard cursor (the mint outline) is on this row.
  property bool hasCursor: false
  // Whether the pointer really moved onto this row and it still holds the
  // same entry (the hover fill); set by the pane.
  property bool hovered: false
  // Whether the row's text is lit (hovered or under the keyboard cursor).
  readonly property bool lit: row.hovered || row.hasCursor
  // The gate that tells real pointer moves from rows moving under a still
  // pointer (PointerMoveGate), or null to ignore hover.
  property var pointerGate: null
  // When the rows last changed or scrolled under a still pointer
  // (Date.now()), 0 for never.
  property real layoutChangedAt: 0
  // When this row was built (Date.now()).
  property real createdAt: 0
  // When the gate last accepted a real pointer move onto this row.
  property real pointerMovedAt: 0
  // The entry id under the last press, compared on release.
  property string pressedKey: ""
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

  // Emitted when the pointer really moved onto the row holding KEY.
  signal hoverMoved(int rowIndex, string key)
  // Emitted when the pointer leaves the row.
  signal hoverLeft(int rowIndex)
  // Emitted for a settled click on the row that still holds KEY on release.
  signal activated(int rowIndex, string key)

  // Whether a pointer click may act on this row (ClickSettle).
  function clickSettled(): bool {
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: row.createdAt,
      movedAt: row.pointerMovedAt,
      layoutChangedAt: row.layoutChangedAt
    })
  }

  Component.onCompleted: row.createdAt = Date.now()

  radius: row.cornerRadius
  color: row.hovered ? row.selectedBackground : "transparent"

  Behavior on color {
    ColorAnimation {
      duration: 120
      easing.type: Easing.OutCubic
    }
  }

  Rectangle {
    // The keyboard cursor outline (mint): Enter's target.
    objectName: "cursorOutline"
    anchors.fill: parent
    radius: row.cornerRadius
    visible: row.hasCursor
    color: Util.alpha(Aranea.DesignTokens.accent, 0.08)
    border.width: 1
    border.color: Aranea.DesignTokens.accent
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
        text: row.secret ? String.fromCodePoint(0xf033e) : row.glyph
        color: row.lit ? row.selectedText : Util.alpha(row.foreground, 0.7)
        font.family: row.fontFamily
        font.pixelSize: Style.font.icon
      }
    }

    Text {
      width: parent.width - Style.space(22) - detailText.width - parent.spacing * 2
      height: parent.height
      textFormat: Text.PlainText
      text: row.title
      color: row.lit ? row.selectedText : row.foreground
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
    id: rowArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // Hover fills the row and feeds the settle rule; it never moves the
    // keyboard cursor.
    onPositionChanged: function (mouse) {
      if (row.pointerGate && row.pointerGate.moved(rowArea, mouse)) {
        row.pointerMovedAt = Date.now()
        row.hoverMoved(row.index, row.entryId)
      }
    }
    onExited: row.hoverLeft(row.index)
    onPressed: row.pressedKey = row.entryId
    onClicked: {
      var key = row.pressedKey
      row.pressedKey = ""
      if (!key || key !== row.entryId || !row.clickSettled())
        return
      row.activated(row.index, key)
    }
  }
}
