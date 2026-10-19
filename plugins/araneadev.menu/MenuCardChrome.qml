// Presentational chrome for the menu card header, root tiles, context and footer.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Item {
  id: chrome
  // Public contract member.
  property bool fullRootHeader: false
  // Compress the command console and tile content on short screens.
  property bool compactDeck: false
  // Existing menu owner supplies logical open; animations never delay input.
  property bool presented: true
  Aranea.DeckReveal {
    id: identityEntrance
    opened: chrome.presented && chrome.fullRootHeader
    motionEnabled: chrome.motionEnabled
  }
  // Scoped queries expose a query-preserving global search route.
  property bool scopedSearch: false
  // Requests the owning menu to return to global search.
  signal searchEverywhereRequested
  // Public contract member.
  property bool dmenuActive: false
  // Public contract member.
  property string activeTitle: ""
  // Public contract member.
  property string dmenuPrompt: ""
  // Public contract member.
  property string hint: ""
  // Optional unfiltered root search guidance; empty preserves the supplied hint.
  property string rootSearchHint: ""
  // Matched menu query; special modes and no-match presentation keep their own text.
  property string matchedQuery: ""
  // Public contract member.
  property string workspaceContext: ""
  // Public contract member.
  property string clockContext: ""
  // Public contract member.
  property var rootTiles: []
  // Public contract member.
  property string brandingMarksPath: ""
  // Public contract member.
  property string brandingMotifsPath: ""
  // Public contract member.
  property string brandingGlyphsPath: ""
  // Public contract member.
  property color foreground: Commons.Color.menu.text
  // Public contract member.
  property color contextText: Util.alpha(foreground, Aranea.DesignTokens.secondaryOpacity)
  // Public contract member.
  property color selectedText: Commons.Color.menu.selectedText
  // Public contract member.
  property color footerText: contextText
  // Public contract member.
  property string fontFamily: Aranea.Typography.uiFamily
  // Public contract member.
  property real menuFontScale: 1
  // Public contract member.
  property real menuLetterSpacing: 0
  // Public contract member.
  property bool motionEnabled: Aranea.MotionState.motionEnabled
  // Public contract member.
  property int rootHeaderHeight: Style.space(68)
  // Public contract member.
  property int headerHeight: Style.space(44)
  // Public contract member.
  property int rootContextHeight: Style.space(24)
  // Public contract member.
  property int rootTileHeight: Style.space(72)
  // Public contract member.
  property int footerHeight: Style.space(30)
  // Gap between header, context band, tiles and footer on the root.
  property int sectionSpacing: Style.spacing.md
  // The window's PointerMoveGate, shared with the tiles (null: each tile
  // uses its own).
  property var pointerGate: null
  // Shared gate for the search control, with a local fallback for standalone chrome.
  readonly property var searchPointerGate: chrome.pointerGate || ownSearchGate
  PointerMoveGate {
    id: ownSearchGate
    referenceItem: chrome
  }
  // When the menu's layout last changed under the pointer, for the tiles'
  // settled clicks.
  property real layoutChangedAt: 0
  // Public contract member.
  signal tileActivated(var tile)

  // Public contract member.
  function scaled(size) {
    return size * menuFontScale
  }

  Column {
    anchors.fill: parent
    spacing: fullRootHeader ? chrome.sectionSpacing : Style.spacing.sm

    Item {
      id: deckHeader
      opacity: chrome.fullRootHeader ? identityEntrance.progress : 1
      transform: Translate {
        y: chrome.fullRootHeader ? identityEntrance.offset : 0
      }
      width: parent.width
      height: fullRootHeader ? rootHeaderHeight : headerHeight
      readonly property bool expanded: chrome.fullRootHeader && !chrome.compactDeck
      readonly property int emblemSize: chrome.fullRootHeader ? Style.space(expanded ? 84 : 54) : Style.space(24)

      Rectangle {
        visible: chrome.fullRootHeader
        anchors.fill: parent
        radius: Aranea.DesignTokens.cornerRadius
        color: Util.alpha(chrome.foreground, 0.025)
        border.width: 1
        border.color: Util.alpha(chrome.foreground, 0.08)
      }

      Item {
        id: emblem
        // A fixed width with explicit placement avoids retaining both edge
        // anchors when search swaps between the compact and root headers.
        x: chrome.fullRootHeader ? parent.width - width - Style.space(14) : 0
        anchors.verticalCenter: parent.verticalCenter
        width: deckHeader.emblemSize
        height: width
        Aranea.OrbitalHalo {
          objectName: "menuOrbitalHalo"
          anchors.fill: parent
          visible: chrome.fullRootHeader
          presented: chrome.presented
          motionEnabled: chrome.motionEnabled
          primary: chrome.selectedText
          secondary: Aranea.DesignTokens.strandEnd
        }
        Image {
          objectName: "menuBrandEmblem"
          anchors.centerIn: parent
          width: chrome.fullRootHeader ? parent.width * 0.65 : parent.width
          height: width
          source: Aranea.RuntimePaths.brandUrl
          fillMode: Image.PreserveAspectFit
          sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
          smooth: true
          mipmap: true
        }
      }

      Column {
        anchors.left: parent.left
        anchors.leftMargin: chrome.fullRootHeader ? Style.space(16) : Style.space(34)
        anchors.right: parent.right
        anchors.rightMargin: chrome.fullRootHeader ? deckHeader.emblemSize + Style.space(40) : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(deckHeader.expanded ? 7 : 4)
        Text {
          visible: deckHeader.expanded
          text: "COMMAND DECK"
          color: chrome.selectedText
          font.family: Aranea.Typography.technicalFamily
          font.pixelSize: chrome.scaled(Style.font.caption)
          font.letterSpacing: 2.2
        }
        Text {
          objectName: "menuHeaderTitle"
          width: parent.width
          textFormat: Text.PlainText
          text: chrome.matchedQuery ? "› " + chrome.matchedQuery : chrome.fullRootHeader ? Aranea.BrandConfig.shortName : (chrome.dmenuActive ? chrome.dmenuPrompt : Aranea.BrandConfig.shortName + " / " + chrome.activeTitle)
          color: chrome.foreground
          font.family: chrome.fontFamily
          font.pixelSize: chrome.scaled(chrome.fullRootHeader ? (deckHeader.expanded ? Style.font.displayLarge : Style.font.title) : Style.font.body)
          font.weight: Font.Bold
          font.letterSpacing: chrome.fullRootHeader ? 4 : chrome.menuLetterSpacing
          elide: chrome.matchedQuery ? Text.ElideLeft : Text.ElideRight
        }
        Rectangle {
          width: parent.width
          height: hintLabel.implicitHeight + (chrome.fullRootHeader ? Style.space(12) : 0)
          color: "transparent"
          border.width: 0
          border.color: Util.alpha(chrome.selectedText, 0.22)
          Rectangle {
            visible: chrome.fullRootHeader
            anchors.bottom: parent.bottom
            width: parent.width * 0.42
            height: 1
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop {
                position: 0
                color: Util.alpha(chrome.selectedText, 0.6)
              }
              GradientStop {
                position: 1
                color: "transparent"
              }
            }
          }
          Text {
            id: hintLabel
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            x: chrome.fullRootHeader ? Style.space(10) : 0
            width: parent.width - x * 2 - (chrome.scopedSearch ? globalSearch.width + Style.spacing.md : 0)
            text: (chrome.fullRootHeader ? "›  " : "") + (chrome.rootSearchHint || chrome.hint)
            color: chrome.fullRootHeader ? chrome.foreground : chrome.contextText
            font.family: Aranea.Typography.technicalFamily
            font.pixelSize: chrome.scaled(Style.font.caption)
            elide: Text.ElideRight
          }
        }
      }

      Text {
        id: globalSearch
        objectName: "searchEverywhere"
        visible: chrome.scopedSearch && !chrome.dmenuActive
        // Last appearance is independent of whether the result identities changed.
        property real appearedAt: 0
        // Real movement after appearance can lift the existing settling guard.
        property real pointerMovedAt: 0
        onVisibleChanged: if (visible) {
          appearedAt = Date.now()
          pointerMovedAt = 0
        }
        Component.onCompleted: if (visible)
          appearedAt = Date.now()
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: "Search everywhere · ^F"
        color: chrome.selectedText
        font.family: chrome.fontFamily
        font.pixelSize: chrome.scaled(Style.font.caption)
        MouseArea {
          id: searchArea
          anchors.fill: parent
          hoverEnabled: true
          // An affordance changing under a held pointer cannot navigate.
          property real pressedStamp: -1
          // A hide/reappear cycle invalidates a press even with identical result keys.
          property real pressedAppearance: -1
          onPositionChanged: function (mouse) {
            if (chrome.searchPointerGate.moved(searchArea, mouse))
              globalSearch.pointerMovedAt = Date.now()
          }
          onPressed: {
            pressedStamp = chrome.layoutChangedAt
            pressedAppearance = globalSearch.appearedAt
          }
          onClicked: {
            var unchanged = pressedStamp === chrome.layoutChangedAt && pressedAppearance === globalSearch.appearedAt
            pressedStamp = -1
            pressedAppearance = -1
            if (chrome.scopedSearch && unchanged && ClickSettle.clickSettled({
              now: Date.now(),
              createdAt: globalSearch.appearedAt,
              movedAt: globalSearch.pointerMovedAt,
              layoutChangedAt: chrome.layoutChangedAt
            }))
              chrome.searchEverywhereRequested()
          }
        }
      }
    }

    Row {
      visible: fullRootHeader && rootContextHeight > 0
      width: parent.width
      height: rootContextHeight
      spacing: Style.spacing.md
      Text {
        text: "◈"
        color: selectedText
        font.family: Aranea.Typography.iconFamily
        font.pixelSize: scaled(Style.font.caption)
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: workspaceContext
        color: contextText
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: scaled(Style.font.caption)
        verticalAlignment: Text.AlignVCenter
      }
      Text {
        text: "System ready"
        color: contextText
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: scaled(Style.font.caption)
        verticalAlignment: Text.AlignVCenter
      }
      Text {
        text: clockContext
        color: contextText
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: scaled(Style.font.caption)
        verticalAlignment: Text.AlignVCenter
      }
    }

    Row {
      visible: fullRootHeader && rootTileHeight > 0
      width: parent.width
      height: rootTileHeight
      spacing: Style.spacing.xs
      Repeater {
        model: rootTiles
        delegate: MenuRootTile {
          required property var modelData
          required property int index
          width: (parent.width - Style.spacing.xs * 2) / 3
          height: rootTileHeight
          tileData: modelData
          compact: chrome.compactDeck
          presented: chrome.presented && chrome.fullRootHeader
          entranceDelay: 70 + index * 55
          fontFamily: chrome.fontFamily
          foreground: chrome.foreground
          contextText: chrome.contextText
          selectedText: chrome.selectedText
          menuFontScale: chrome.menuFontScale
          menuLetterSpacing: chrome.menuLetterSpacing
          motionEnabled: chrome.motionEnabled
          sharedGate: chrome.pointerGate
          layoutChangedAt: chrome.layoutChangedAt
          onActivated: chrome.tileActivated(modelData)
        }
      }
    }

    Item {
      visible: fullRootHeader && footerHeight > 0
      width: parent.width
      height: footerHeight
      Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        text: "Quick access · Enter to open"
        color: footerText
        font.family: fontFamily
        font.pixelSize: scaled(Style.font.bodySmall)
        elide: Text.ElideRight
      }
      Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: Aranea.BrandConfig.shortName
        color: selectedText
        opacity: 0.7
        font.family: fontFamily
        font.pixelSize: scaled(Style.font.caption)
      }
    }
  }
}
