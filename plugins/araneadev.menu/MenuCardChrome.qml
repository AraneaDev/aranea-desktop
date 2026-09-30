// Presentational chrome for the menu card header, root tiles, context and footer.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: chrome
  // Public contract member.
  property bool fullRootHeader: false
  // Public contract member.
  property bool dmenuActive: false
  // Public contract member.
  property string activeTitle: ""
  // Public contract member.
  property string dmenuPrompt: ""
  // Public contract member.
  property string hint: ""
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
  property color foreground: Color.menu.text
  // Public contract member.
  property color contextText: Util.alpha(foreground, 0.58)
  // Public contract member.
  property color selectedText: Color.menu.selectedText
  // Public contract member.
  property color footerText: contextText
  // Public contract member.
  property string fontFamily: Style.font.menuFamily
  // Public contract member.
  property real menuFontScale: 1
  // Public contract member.
  property real menuLetterSpacing: 0
  // Public contract member.
  property bool motionEnabled: true
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
      width: parent.width
      height: fullRootHeader ? rootHeaderHeight : headerHeight

      Image {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: fullRootHeader ? Style.space(48) : Style.space(22)
        height: width
        source: Aranea.RuntimePaths.brandUrl
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
        smooth: true
        mipmap: true
      }

      Image {
        visible: fullRootHeader
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(220)
        height: parent.height
        source: "file://" + brandingMotifsPath + "menu-network.svg"
        fillMode: Image.PreserveAspectFit
        opacity: 0.24
        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
        smooth: true
        mipmap: true
      }

      Column {
        anchors.left: parent.left
        // Glyph plus BrandHeader's 10 px gap; the root mark keeps 48 + 14.
        anchors.leftMargin: fullRootHeader ? Style.space(62) : Style.space(32)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: fullRootHeader ? Aranea.BrandConfig.shortName : (dmenuActive ? dmenuPrompt : Aranea.BrandConfig.shortName + " / " + activeTitle)
          color: foreground
          font.family: fontFamily
          font.pixelSize: scaled(fullRootHeader ? Style.font.title : Style.font.body)
          font.weight: Font.Medium
          font.letterSpacing: menuLetterSpacing
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: hint
          color: contextText
          font.family: fontFamily
          font.pixelSize: scaled(Style.font.caption)
          font.weight: Font.Medium
          font.letterSpacing: menuLetterSpacing
          elide: Text.ElideRight
        }
      }

      Image {
        visible: fullRootHeader
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(64)
        height: Style.space(12)
        source: "file://" + brandingMotifsPath + "edge-trace.svg"
        fillMode: Image.PreserveAspectFit
        opacity: 0.55
        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
        smooth: true
        mipmap: true
      }
    }

    Row {
      visible: fullRootHeader
      width: parent.width
      height: rootContextHeight
      spacing: Style.spacing.md
      Text {
        text: "◈"
        color: contextText
        font.family: fontFamily
        font.pixelSize: scaled(Style.font.caption)
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: workspaceContext
        color: contextText
        font.family: fontFamily
        font.pixelSize: scaled(Style.font.caption)
        verticalAlignment: Text.AlignVCenter
      }
      Text {
        text: "SYSTEM READY"
        color: contextText
        font.family: fontFamily
        font.pixelSize: scaled(Style.font.caption)
        verticalAlignment: Text.AlignVCenter
      }
      Text {
        text: clockContext
        color: contextText
        font.family: fontFamily
        font.pixelSize: scaled(Style.font.caption)
        verticalAlignment: Text.AlignVCenter
      }
    }

    Row {
      visible: fullRootHeader
      width: parent.width
      height: rootTileHeight
      spacing: Style.spacing.xs
      Repeater {
        model: rootTiles
        delegate: MenuRootTile {
          required property var modelData
          width: (parent.width - Style.spacing.xs * 2) / 3
          height: rootTileHeight
          tileData: modelData
          fontFamily: chrome.fontFamily
          foreground: chrome.foreground
          contextText: chrome.contextText
          selectedText: chrome.selectedText
          menuFontScale: chrome.menuFontScale
          menuLetterSpacing: chrome.menuLetterSpacing
          motionEnabled: chrome.motionEnabled
          onActivated: chrome.tileActivated(modelData)
        }
      }
    }

    Item {
      visible: fullRootHeader
      width: parent.width
      height: footerHeight
      Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        text: "COMMANDS  ·  QUICK ACCESS  ·  ENTER TO OPEN"
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
