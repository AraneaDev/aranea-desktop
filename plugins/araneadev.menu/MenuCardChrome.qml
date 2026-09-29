// Presentational chrome for the menu card header, root tiles, context and footer.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

Item {
  id: chrome
  property bool fullRootHeader: false
  property bool dmenuActive: false
  property string activeTitle: ""
  property string dmenuPrompt: ""
  property string hint: ""
  property string workspaceContext: ""
  property string clockContext: ""
  property var rootTiles: []
  property string brandingMarksPath: ""
  property string brandingMotifsPath: ""
  property string brandingGlyphsPath: ""
  property color foreground: Color.menu.text
  property color contextText: Util.alpha(foreground, 0.58)
  property color selectedText: Color.menu.selectedText
  property color footerText: contextText
  property string fontFamily: Style.font.menuFamily
  property real menuFontScale: 1
  property real menuLetterSpacing: 0
  property bool motionEnabled: true
  property int rootHeaderHeight: Style.space(68)
  property int headerHeight: Style.space(44)
  property int rootContextHeight: Style.space(24)
  property int rootTileHeight: Style.space(72)
  property int footerHeight: Style.space(30)
  signal tileActivated(var tile)

  function scaled(size) { return size * menuFontScale }

  Column {
    anchors.fill: parent
    spacing: fullRootHeader ? Style.spacing.md : Style.spacing.sm

    Item {
      width: parent.width
      height: fullRootHeader ? rootHeaderHeight : headerHeight

      Image {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: fullRootHeader ? Style.space(48) : Style.space(28)
        height: width
        source: "file://" + brandingMarksPath + (fullRootHeader ? "aranea-primary.svg" : "aranea-glyph.svg")
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
        height: Style.space(68)
        source: "file://" + brandingMotifsPath + "menu-network.svg"
        fillMode: Image.PreserveAspectFit
        opacity: 0.24
        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
        smooth: true
        mipmap: true
      }

      Column {
        anchors.left: parent.left
        anchors.leftMargin: fullRootHeader ? Style.space(62) : Style.space(38)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: fullRootHeader ? "ARANEA" : (dmenuActive ? dmenuPrompt : "ARANEA / " + activeTitle)
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
      Text { text: workspaceContext; color: contextText; font.family: fontFamily; font.pixelSize: scaled(Style.font.caption); verticalAlignment: Text.AlignVCenter }
      Text { text: "SYSTEM READY"; color: contextText; font.family: fontFamily; font.pixelSize: scaled(Style.font.caption); verticalAlignment: Text.AlignVCenter }
      Text { text: clockContext; color: contextText; font.family: fontFamily; font.pixelSize: scaled(Style.font.caption); verticalAlignment: Text.AlignVCenter }
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
      Text { anchors.left: parent.left; anchors.bottom: parent.bottom; text: "COMMANDS  ·  QUICK ACCESS  ·  ENTER TO OPEN"; color: footerText; font.family: fontFamily; font.pixelSize: scaled(Style.font.bodySmall); elide: Text.ElideRight }
      Text { anchors.right: parent.right; anchors.bottom: parent.bottom; text: "ARANEA"; color: selectedText; opacity: 0.7; font.family: fontFamily; font.pixelSize: scaled(Style.font.caption) }
    }
  }
}
