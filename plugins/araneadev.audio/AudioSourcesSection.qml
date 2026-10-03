// The Sources section of the Aranea audio dropdown: one row per playback
// stream, each with a mute glyph, label, percentage and its own filament
// slider (streams can boost past 100%). Pure view: plain inputs in,
// signals out. Every action carries the stream's key (its node id): a
// drag carries the key its press landed on, so a stream that comes or
// goes mid-drag never hands the drag to its neighbour (the dropdown
// refuses a key that no longer matches). A press, click or wheel step on
// a row within 300 ms of its creation or of the dropdown's layout shifting
// (pointerGate.layoutChangedAt) is ignored unless the pointer has really
// moved onto the row since.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Column {
  id: section
  objectName: "sourcesSection"

  // Stream rows: [{key, label, volume, muted, current}].
  property var streams: []
  // Cursor here: -1 none, 0.. a stream row.
  property int cursor: -1
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from a
  // stream row moving under a still pointer.
  property var pointerGate: null

  // Emitted with a new volume for stream INDEX holding KEY.
  signal volumeMoved(int index, string key, real value)
  // Emitted when the mute of stream INDEX, holding KEY, is toggled.
  signal muteToggled(int index, string key)
  // Emitted when the pointer enters stream row INDEX.
  signal rowHovered(int index)

  visible: streams.length > 0
  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: captionText.implicitHeight
    Text {
      id: captionText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "SOURCES"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: String(section.streams.length)
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
  // The model is the row count, not the array: a stream's volume or mute
  // arrives as a new streams array, and an array model would rebuild every
  // row then, dropping a slider drag after its first step.
  Repeater {
    model: section.streams.length
    Column {
      id: row
      required property int index
      // This row's stream, read from the live array.
      readonly property var modelData: section.streams[index] || ({
          key: "",
          label: "",
          volume: 0,
          muted: false,
          current: false
        })
      // The key the slider's current drag started on, "" between drags.
      property string dragKey: ""

      objectName: "streamRow"
      width: section.width

      // A wrapping Item, so the cursor outline and hover can cover both
      // lines: Column manages its direct children's y, which anchors.fill
      // would conflict with.
      Item {
        id: card
        // When the row was created (Date.now()), for the settle window.
        property real createdAt: 0
        // When the gate last accepted a real pointer move over the row
        // (Date.now()), 0 for never.
        property real pointerMovedAt: 0

        // Whether a pointer press or click may act on the row (its
        // slider's clickGate and the mute glyph): on screen and still
        // since the dropdown's last layout shift, or moved onto since.
        function clickSettled() {
          return ClickSettle.clickSettled({
            now: Date.now(),
            createdAt: card.createdAt,
            movedAt: card.pointerMovedAt,
            layoutChangedAt: section.pointerGate ? Number(section.pointerGate.layoutChangedAt) || 0 : 0
          })
        }

        width: parent.width
        implicitHeight: content.implicitHeight
        Component.onCompleted: card.createdAt = Date.now()

        Rectangle {
          // The keyboard cursor outline.
          objectName: "cursorOutline"
          anchors.fill: parent
          color: "transparent"
          border.width: section.cursor === row.index ? 1 : 0
          border.color: Aranea.DesignTokens.accent
        }
        Column {
          id: content
          width: parent.width
          spacing: Style.space(2)

          Item {
            width: parent.width
            height: Math.max(muteGlyph.implicitHeight, labelText.implicitHeight, percentText.implicitHeight)
            Text {
              id: muteGlyph
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.muted ? String.fromCodePoint(0xF075F) : String.fromCodePoint(0xF057E)
              color: Aranea.DesignTokens.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              MouseArea {
                objectName: "streamMute"
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (card.clickSettled())
                  section.muteToggled(row.index, String(row.modelData.key))
              }
            }
            Text {
              id: labelText
              anchors.left: muteGlyph.right
              anchors.leftMargin: Style.space(8)
              anchors.right: percentText.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: row.modelData.label
              color: row.modelData.current ? Aranea.DesignTokens.accent : Util.alpha(Aranea.DesignTokens.foreground, row.modelData.muted ? 0.55 : 1)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Text {
              id: percentText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.muted ? "muted" : Math.round((streamSlider.dragging ? streamSlider.liveValue : row.modelData.volume) * 100) + "%"
              color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
          Item {
            width: parent.width
            height: streamSlider.implicitHeight + Style.space(6)
            Aranea.FilamentSlider {
              id: streamSlider
              objectName: "streamSlider"
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              maximum: 1.5
              value: row.modelData.volume
              muted: row.modelData.muted
              clickGate: card
              // A wheel step right after a layout shift is settled too.
              gateWheel: true
              // A drag keeps the key it started on.
              onDraggingChanged: row.dragKey = dragging ? String(row.modelData.key) : ""
              onMoved: function (value) {
                section.volumeMoved(row.index, streamSlider.dragging ? row.dragKey : String(row.modelData.key), value)
              }
              onRightClicked: if (card.clickSettled())
                section.muteToggled(row.index, String(row.modelData.key))
            }
          }
        }
        HoverHandler {
          id: streamHover
          onHoveredChanged: if (hovered && !section.pointerGate)
            section.rowHovered(row.index)
          onPointChanged: if (section.pointerGate && streamHover.hovered && section.pointerGate.moved(streamHover.parent, {
            x: streamHover.point.position.x,
            y: streamHover.point.position.y
          })) {
            card.pointerMovedAt = Date.now()
            section.rowHovered(row.index)
          }
        }
      }
    }
  }
}
