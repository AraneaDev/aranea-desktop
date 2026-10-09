// Now playing strip in the Aranea audio dropdown: player name, track
// title and artist/album, transport buttons and a progress hairline lit
// as the filament strand (mint to violet). Pure view: plain inputs in,
// signals out. A transport click within 300 ms of the dropdown's layout
// shifting (pointerGate.layoutChangedAt) is ignored unless the pointer has
// really moved onto the strip since.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

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
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from the
  // strip moving under a still pointer.
  property var pointerGate: null
  // When the gate last accepted a real pointer move over the strip
  // (Date.now()), 0 for never.
  property real pointerMovedAt: 0

  // Emitted when the previous button is activated.
  signal previousRequested
  // Emitted when the play/pause button is activated.
  signal playPauseRequested
  // Emitted when the next button is activated.
  signal nextRequested
  // Emitted when the pointer enters the strip.
  signal entered

  // Whether a pointer click may reach a transport button: settled since
  // the dropdown's last layout shift, or moved onto since.
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      movedAt: strip.pointerMovedAt,
      layoutChangedAt: strip.pointerGate ? Number(strip.pointerGate.layoutChangedAt) || 0 : 0
    })
  }

  visible: info.visible

  // A wrapping Item, so the cursor outline can anchor.fill it: Column
  // manages its direct children's y, which anchors.fill would conflict
  // with.
  Item {
    id: card
    width: parent.width
    implicitHeight: content.implicitHeight

    Rectangle {
      // The keyboard cursor outline.
      objectName: "cursorOutline"
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
          color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
          font.family: Aranea.Typography.uiFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: strip.info.player
          color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
          font.family: Aranea.Typography.uiFamily
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
            font.family: Aranea.Typography.uiFamily
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: [strip.info.artist, strip.info.album].filter(function (part) {
              return part !== ""
            }).join(" · ")
            color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
            font.family: Aranea.Typography.uiFamily
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
            color: Util.alpha(Aranea.DesignTokens.foreground, 0.82)
            font.family: Aranea.Typography.iconFamily
            font.pixelSize: Style.font.body
            Aranea.HoverTint {
              z: -1
              anchors.margins: -Style.space(3)
              active: strip.info.canPrevious
              pointerGate: strip.pointerGate
            }
            MouseArea {
              objectName: "previousButton"
              anchors.fill: parent
              enabled: strip.info.canPrevious
              cursorShape: Qt.PointingHandCursor
              onClicked: if (strip.clickSettled())
                strip.previousRequested()
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: strip.info.playing ? String.fromCodePoint(0xF03E4) : String.fromCodePoint(0xF040A)
            color: Aranea.DesignTokens.accent
            font.family: Aranea.Typography.iconFamily
            font.pixelSize: Style.font.body
            Aranea.HoverTint {
              z: -1
              anchors.margins: -Style.space(3)
              pointerGate: strip.pointerGate
            }
            MouseArea {
              objectName: "playPauseButton"
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (strip.clickSettled())
                strip.playPauseRequested()
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF04AD)
            opacity: strip.info.canNext ? 1 : 0.35
            color: Util.alpha(Aranea.DesignTokens.foreground, 0.82)
            font.family: Aranea.Typography.iconFamily
            font.pixelSize: Style.font.body
            Aranea.HoverTint {
              z: -1
              anchors.margins: -Style.space(3)
              active: strip.info.canNext
              pointerGate: strip.pointerGate
            }
            MouseArea {
              objectName: "nextButton"
              anchors.fill: parent
              enabled: strip.info.canNext
              cursorShape: Qt.PointingHandCursor
              onClicked: if (strip.clickSettled())
                strip.nextRequested()
            }
          }
        }
      }
      Item {
        objectName: "progressBar"
        width: parent.width
        height: Math.max(2, Style.space(2))
        visible: strip.info.progress >= 0
        Rectangle {
          anchors.fill: parent
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.15)
        }
        // The played part, lit as the filament strand: mint to violet
        // across its own length, as FilamentSlider's lit strand.
        Rectangle {
          objectName: "progressFill"
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: parent.width * Math.max(0, Math.min(1, strip.info.progress))
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
              position: 0
              color: Aranea.DesignTokens.accent
            }
            GradientStop {
              position: 1
              color: Aranea.DesignTokens.strandEnd
            }
          }
        }
      }
    }
    HoverHandler {
      id: stripHover
      onHoveredChanged: if (hovered && !strip.pointerGate)
        strip.entered()
      onPointChanged: if (strip.pointerGate && stripHover.hovered && strip.pointerGate.moved(stripHover.parent, {
        x: stripHover.point.position.x,
        y: stripHover.point.position.y
      })) {
        strip.pointerMovedAt = Date.now()
        strip.entered()
      }
    }
  }
}
