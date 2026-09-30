// The Sources section of the Aranea audio dropdown: one row per playback
// stream, each with a mute glyph, label, percentage and its own filament
// slider (streams can boost past 100%). Pure view: plain inputs in,
// signals out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section
  objectName: "sourcesSection"

  // Stream rows: [{key, label, volume, muted, current}].
  property var streams: []
  // Cursor here: -1 none, 0.. a stream row.
  property int cursor: -1

  // Emitted with a new volume for stream INDEX.
  signal volumeMoved(int index, real value)
  // Emitted when stream INDEX's mute is toggled.
  signal muteToggled(int index)
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
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
  // qmllint disable unqualified
  Repeater {
    model: section.streams
    Column {
      id: row
      required property var modelData
      required property int index
      objectName: "streamRow"
      width: section.width
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
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: section.muteToggled(row.index)
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
          color: row.modelData.current ? Aranea.DesignTokens.accent : Aranea.DesignTokens.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          id: percentText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.muted ? "muted" : Math.round((streamSlider.dragging ? streamSlider.liveValue : row.modelData.volume) * 100) + "%"
          color: Aranea.DesignTokens.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
      Item {
        width: parent.width
        height: streamSlider.implicitHeight + Style.space(6)
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.width: section.cursor === row.index ? 1 : 0
          border.color: Aranea.DesignTokens.accent
        }
        Aranea.FilamentSlider {
          id: streamSlider
          objectName: "streamSlider"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          maximum: 1.5
          value: row.modelData.volume
          muted: row.modelData.muted
          onMoved: function (value) {
            section.volumeMoved(row.index, value)
          }
          onRightClicked: section.muteToggled(row.index)
        }
        HoverHandler {
          onHoveredChanged: if (hovered)
            section.rowHovered(row.index)
        }
      }
    }
  }
  // qmllint enable unqualified
}
