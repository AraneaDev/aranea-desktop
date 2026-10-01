// Now playing strip in the Aranea audio dropdown: player name, track
// title and artist/album, transport buttons and a progress hairline.
// Pure view: plain inputs in, signals out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: strip
  objectName: "nowPlaying"

  // The NowPlaying object (see AudioLogic.js's nowPlayingState).
  property var info: ({
      visible: false,
      player: "",
      title: "",
      artist: "",
      album: "",
      progress: -1,
      playing: false,
      canPrevious: false,
      canNext: false
    })
  // Whether the keyboard cursor is on the strip.
  property bool hasCursor: false

  // Emitted when the previous button is activated.
  signal previousRequested
  // Emitted when the play/pause button is activated.
  signal playPauseRequested
  // Emitted when the next button is activated.
  signal nextRequested
  // Emitted when the pointer enters the strip.
  signal entered

  visible: info.visible

  // A wrapping Item, so the cursor outline can anchor.fill it: Column
  // manages its direct children's y, which anchors.fill would conflict
  // with.
  Item {
    id: card
    width: parent.width
    implicitHeight: content.implicitHeight

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.width: strip.hasCursor ? 1 : 0
      border.color: Aranea.DesignTokens.accent
    }
    Column {
      id: content
      width: parent.width
      spacing: Style.space(6)

      Item {
        width: parent.width
        implicitHeight: captionText.implicitHeight
        Text {
          id: captionText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "NOW PLAYING"
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: strip.info.player
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
      Item {
        width: parent.width
        implicitHeight: Math.max(labels.implicitHeight, buttons.implicitHeight)
        Column {
          id: labels
          anchors.left: parent.left
          anchors.right: buttons.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: strip.info.title
            color: Aranea.DesignTokens.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: [strip.info.artist, strip.info.album].filter(function (part) {
              return part !== ""
            }).join(" · ")
            color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Row {
          id: buttons
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF04AE)
            opacity: strip.info.canPrevious ? 1 : 0.35
            color: Aranea.DesignTokens.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            MouseArea {
              anchors.fill: parent
              enabled: strip.info.canPrevious
              cursorShape: Qt.PointingHandCursor
              onClicked: strip.previousRequested()
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: strip.info.playing ? String.fromCodePoint(0xF03E4) : String.fromCodePoint(0xF040A)
            color: Aranea.DesignTokens.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: strip.playPauseRequested()
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF04AD)
            opacity: strip.info.canNext ? 1 : 0.35
            color: Aranea.DesignTokens.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            MouseArea {
              anchors.fill: parent
              enabled: strip.info.canNext
              cursorShape: Qt.PointingHandCursor
              onClicked: strip.nextRequested()
            }
          }
        }
      }
      Item {
        width: parent.width
        height: Math.max(1, Style.spacing.hairline)
        visible: strip.info.progress >= 0
        Rectangle {
          anchors.fill: parent
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.15)
        }
        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: parent.width * Math.max(0, Math.min(1, strip.info.progress))
          color: Aranea.DesignTokens.strandEnd
        }
      }
    }
    HoverHandler {
      onHoveredChanged: if (hovered)
        strip.entered()
    }
  }
}
