// Presentational tile used by the menu's full root header. Its hover tint
// follows real pointer moves only (PointerMoveGate), so a tile appearing
// under a still pointer is not tinted. Clicks are keyed by the tile id and
// settled (ClickSettle): refused within 300 ms of the tile being built or
// the menu's layout changing, unless the pointer really moved onto it.
// qmllint disable missing-property
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

BorderSurface {
  id: tile

  // Menu data object containing icon, label and detail fields.
  required property var tileData
  // Primary tile label.
  property string label: tileData && tileData.label ? tileData.label : ""
  // Tile icon glyph.
  property string icon: tileData && tileData.icon ? tileData.icon : ""
  // Secondary tile detail text.
  property string detail: tileData && tileData.detail ? tileData.detail : ""
  // External selection state.
  property bool selected: false
  // Font family used for all tile text.
  property string fontFamily: Aranea.Typography.uiFamily
  // Main tile text colour.
  property color foreground: Color.menu.text
  // Secondary tile text colour.
  property color contextText: Util.alpha(foreground, 0.58)
  // Accent colour for the icon and edge marks.
  property color selectedText: Color.menu.selectedText
  // Scale applied to the shell font sizes.
  property real menuFontScale: 1.0
  // Letter spacing applied to tile text.
  property real menuLetterSpacing: 0
  // Whether parent animations are enabled.
  property bool motionEnabled: true
  // Whether the pointer really moved onto the tile and is still over it.
  property bool hovered: false
  // The window's shared PointerMoveGate, or null for the tile's own.
  property var sharedGate: null
  // The gate the tile's hover goes through.
  readonly property var pointerGate: sharedGate || ownGate
  // When the menu's layout last changed under the pointer (Date.now()).
  property real layoutChangedAt: 0
  // When the tile was built (Date.now()).
  property real createdAt: 0
  // When the gate last accepted a real pointer move onto the tile.
  property real pointerMovedAt: 0
  // The tile id under the last press, compared on release.
  property string pressedKey: ""
  // The tile's key: its id.
  readonly property string key: tileData && tileData.id ? String(tileData.id) : ""

  // Whether a pointer click may act on this tile (ClickSettle).
  function clickSettled(): bool {
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: tile.createdAt,
      movedAt: tile.pointerMovedAt,
      layoutChangedAt: tile.layoutChangedAt
    })
  }

  Component.onCompleted: tile.createdAt = Date.now()
  onVisibleChanged: if (!tile.visible)
    tile.hovered = false

  // Emitted when the tile is clicked.
  signal activated

  implicitHeight: Style.space(64)
  radius: Aranea.DesignTokens.cornerRadius
  color: tile.selected || tile.hovered ? Util.alpha(tile.selectedText, 0.12) : "transparent"
  borderSpec: Border.none()

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    width: Style.space(18)
    height: Style.space(2)
    color: tile.selectedText
    opacity: tile.selected || tile.hovered ? 0.7 : 0.12
  }

  Rectangle {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: Style.space(18)
    height: Style.space(2)
    color: tile.selectedText
    opacity: tile.selected || tile.hovered ? 0.7 : 0.12
  }

  Column {
    width: parent.width - Style.space(28)
    anchors.centerIn: parent
    spacing: Style.space(4)

    Aranea.InkText {
      width: parent.width
      text: tile.icon
      color: tile.selectedText
      font.family: Aranea.Typography.iconFamily
      font.pixelSize: Style.font.iconLarge
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width
      text: tile.label
      color: tile.foreground
      font.family: tile.fontFamily
      font.pixelSize: Style.font.bodySmall * tile.menuFontScale
      font.letterSpacing: tile.menuLetterSpacing
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: tile.detail
      color: tile.contextText
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption * tile.menuFontScale
      font.weight: Font.Medium
      font.letterSpacing: tile.menuLetterSpacing
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  PointerMoveGate {
    id: ownGate
    referenceItem: tile
  }

  MouseArea {
    id: tileArea
    objectName: "tileArea"
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPositionChanged: function (mouse) {
      if (tile.pointerGate.moved(tileArea, mouse)) {
        tile.pointerMovedAt = Date.now()
        tile.hovered = true
      }
    }
    onExited: tile.hovered = false
    onPressed: tile.pressedKey = tile.key
    onClicked: {
      var key = tile.pressedKey
      tile.pressedKey = ""
      if (key && key === tile.key && tile.clickSettled())
        tile.activated()
    }
  }
}
