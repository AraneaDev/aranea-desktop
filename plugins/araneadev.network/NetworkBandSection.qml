// The Wi-Fi band section of the Aranea Network dropdown: stock's section
// title on the left and "AUTOMATIC" with a FilamentSwitch on the right,
// and, while a band is pinned, one FilamentPill per band below. Whether the
// section shows at all is the host's `visible`. Pure view: plain inputs
// in, signals out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: section

  // Stock's bandSectionTitle, e.g. "WI-FI BAND: 2.4GHZ".
  property string title: ""
  // Whether Wi-Fi picks the band itself (no pin): the switch is on.
  property bool auto: true
  // The live band's label, e.g. "2.4ghz", for the switch's tooltip.
  property string currentLabel: ""
  // Whether the band pills show (stock's bandPillsVisible: pinned).
  property bool pillsVisible: false
  // The bands: [{key, label, tooltip, selected}].
  property var options: []
  // Whether a band change is pending: the selected pill breathes and the
  // switch dims.
  property bool busy: false
  // Whether the keyboard cursor is on the Automatic switch.
  property bool cursorAuto: false
  // The keyboard cursor's pill, or -1 when the cursor isn't on a pill.
  property int cursorIndex: -1
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from the
  // switch or a pill moving under a still pointer.
  property var pointerGate: null

  // Emitted when the Automatic switch is toggled.
  signal toggleAuto
  // Emitted when the pill for band KEY is clicked.
  signal pick(string key)
  // Emitted when the pointer moves onto the switch (AUTO true, INDEX -1)
  // or onto pill INDEX (AUTO false), through the gate.
  signal pillHovered(bool auto, int index)

  objectName: "bandSection"
  spacing: Style.space(10)

  Item {
    width: parent.width
    implicitHeight: Math.max(titleText.implicitHeight, autoRow.implicitHeight)
    Text {
      id: titleText
      objectName: "bandTitle"
      anchors.left: parent.left
      anchors.right: autoRow.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: section.title
      elide: Text.ElideRight
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Row {
      id: autoRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "AUTOMATIC"
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }
      Aranea.FilamentSwitch {
        objectName: "autoSwitch"
        anchors.verticalCenter: parent.verticalCenter
        checked: section.auto
        hasCursor: section.cursorAuto
        opacity: section.busy ? 0.6 : 1
        onToggled: section.toggleAuto()
        HoverHandler {
          id: autoHover
          onHoveredChanged: if (hovered && !section.pointerGate)
            section.pillHovered(true, -1)
          onPointChanged: if (section.pointerGate && autoHover.hovered && section.pointerGate.moved(autoHover.parent, {
            x: autoHover.point.position.x,
            y: autoHover.point.position.y
          }))
            section.pillHovered(true, -1)
        }
        PanelToolTip {
          objectName: "autoTip"
          visible: autoHover.hovered
          text: section.auto ? "Stay on " + section.currentLabel : "Let Wi-Fi pick the band"
        }
      }
    }
  }
  Row {
    id: pillRow
    objectName: "bandPills"
    // Each pill's width: the row split evenly.
    readonly property real cellWidth: (width - spacing * (Math.max(1, section.options.length) - 1)) / Math.max(1, section.options.length)
    width: parent.width
    visible: section.pillsVisible
    spacing: Style.space(6)
    Repeater {
      model: section.options
      Aranea.FilamentPill {
        required property var modelData
        required property int index
        width: pillRow.cellWidth
        text: modelData.label
        tooltipText: modelData.tooltip || ""
        selected: !!modelData.selected
        busy: section.busy && !!modelData.selected
        hasCursor: !section.cursorAuto && section.cursorIndex === index
        pointerGate: section.pointerGate
        onClicked: section.pick(modelData.key)
        onHoveredMoved: section.pillHovered(false, index)
      }
    }
  }
}
