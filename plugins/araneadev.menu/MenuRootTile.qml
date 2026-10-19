// Presentational tile used by the menu's full root header. Its hover tint
// follows real pointer moves only (PointerMoveGate), so a tile appearing
// under a still pointer is not tinted. Clicks are keyed by the tile id and
// settled (ClickSettle): refused within 300 ms of the tile being built or
// the menu's layout changing, unless the pointer really moved onto it.
// qmllint disable missing-property
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
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
  // Compact deck omits secondary tile text, preserving the primary label.
  property bool compact: false
  // Entrance choreography affects artwork only, never the tile's input bounds.
  property bool presented: true
  // Stagger this tile after the identity reveal, in milliseconds.
  property int entranceDelay: 0
  Aranea.DeckReveal {
    id: entrance
    opened: tile.presented
    delay: tile.entranceDelay
    motionEnabled: tile.motionEnabled
  }
  // Font family used for all tile text.
  property string fontFamily: Aranea.Typography.uiFamily
  // Main tile text colour.
  property color foreground: Commons.Color.menu.text
  // Secondary tile text colour.
  property color contextText: Util.alpha(foreground, Aranea.DesignTokens.secondaryOpacity)
  // Accent colour for the icon and edge marks.
  property color selectedText: Commons.Color.menu.selectedText
  // Scale applied to the shell font sizes.
  property real menuFontScale: 1.0
  // Letter spacing applied to tile text.
  property real menuLetterSpacing: 0
  // Whether parent animations are enabled.
  property bool motionEnabled: Aranea.MotionState.motionEnabled
  // Whether the pointer really moved onto the tile and is still over it.
  property bool hovered: false
  // Interpolated light intensity; the tile's input rectangle remains stationary.
  readonly property real highlight: Math.max(0, Math.min(1, hoverLight.value))
  Aranea.SpringValue {
    id: hoverLight
    targetValue: tile.selected || tile.hovered ? 1 : 0
    motionEnabled: tile.motionEnabled
    epsilon: 0.001
  }
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
  color: "transparent"
  borderSpec: Border.none()

  Shape {
    anchors.fill: parent
    opacity: entrance.progress
    transform: Translate {
      y: entrance.offset
    }
    ShapePath {
      strokeWidth: 1
      strokeColor: Util.alpha(tile.foreground, 0.12 + tile.highlight * 0.12)
      fillGradient: LinearGradient {
        x1: 0
        y1: 0
        x2: tile.width
        y2: tile.height
        GradientStop {
          position: 0
          color: Util.alpha(tile.selectedText, 0.08 + tile.highlight * 0.12)
        }
        GradientStop {
          position: 1
          color: Util.alpha(Aranea.DesignTokens.strandEnd, 0.07 + tile.highlight * 0.09)
        }
      }
      startX: 1
      startY: 1
      PathLine {
        x: tile.width - Style.space(16)
        y: 1
      }
      PathLine {
        x: tile.width - 1
        y: Style.space(16)
      }
      PathLine {
        x: tile.width - 1
        y: tile.height - 1
      }
      PathLine {
        x: Style.space(12)
        y: tile.height - 1
      }
      PathLine {
        x: 1
        y: tile.height - Style.space(12)
      }
      PathLine {
        x: 1
        y: 1
      }
    }
  }

  Aranea.FocusFrame {
    anchors.fill: parent
    anchors.margins: 1
    focused: tile.selected
  }

  Rectangle {
    id: glyphPlate
    radius: Style.space(6)
    opacity: entrance.progress
    transform: Translate {
      y: entrance.offset
    }
    x: Style.space(14)
    y: Style.space(12)
    width: Style.space(tile.compact ? 28 : 32)
    height: width
    color: Util.alpha(tile.selectedText, 0.1)
    scale: 1 + tile.highlight * 0.1
    border.width: 0
    Aranea.InkText {
      anchors.centerIn: parent
      text: tile.icon
      color: tile.selectedText
      font.family: Aranea.Typography.iconFamily
      font.pixelSize: Style.font.iconLarge
    }
  }

  Text {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(18)
    text: "↗"
    color: tile.selectedText
    opacity: entrance.progress * (0.55 + tile.highlight * 0.45)
    transform: Translate {
      x: tile.highlight * Style.space(3)
      y: -tile.highlight * Style.space(3)
    }
    font.family: Aranea.Typography.technicalFamily
    font.pixelSize: Style.font.subtitle
  }

  Column {
    opacity: entrance.progress
    transform: Translate {
      y: entrance.offset
    }
    x: Style.space(14)
    y: glyphPlate.y + glyphPlate.height + Style.space(6)
    width: parent.width - Style.space(28)
    spacing: Style.space(4)
    Text {
      width: parent.width
      text: tile.label
      color: tile.foreground
      font.family: tile.fontFamily
      font.pixelSize: Style.font.subtitle * tile.menuFontScale
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Text {
      visible: !tile.compact
      width: parent.width
      text: tile.detail
      color: tile.contextText
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: Style.font.caption * tile.menuFontScale
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
