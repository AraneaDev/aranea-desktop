// The Wi-Fi band section of the Aranea Network dropdown: stock's section
// title on the left and "AUTOMATIC" with a FilamentSwitch on the right,
// and, while a band is pinned, one FilamentPill per band below. Whether the
// section shows at all is the host's `visible`. Pure view: plain inputs
// in, signals out. A click on the switch within 300 ms of the dropdown's
// layout shifting (pointerGate.layoutChangedAt) is ignored unless the
// pointer has really moved onto it since, as the pills' are.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

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
  // The bands: [{key, label, tooltip}]. No selected flag -- which one is
  // chosen comes from selectedBand instead, so a selection change alone
  // never rebuilds the pills (their Repeater keeps its delegates).
  property var options: []
  // The band the pills show chosen (stock's bandEffective).
  property string selectedBand: ""
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
  // When the gate last accepted a real pointer move onto the switch
  // (Date.now()), 0 for never.
  property real autoMovedAt: 0

  // Emitted when the Automatic switch is toggled.
  signal toggleAuto
  // Emitted when the pill for band KEY is clicked.
  signal pick(string key)
  // Emitted when the pointer moves onto the switch (AUTO true, INDEX -1)
  // or onto pill INDEX (AUTO false), through the gate.
  signal pillHovered(bool auto, int index)

  // Whether a pointer click may toggle the switch (its clickGate): settled
  // since the dropdown's last layout shift, or moved onto since.
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      movedAt: section.autoMovedAt,
      layoutChangedAt: section.pointerGate ? Number(section.pointerGate.layoutChangedAt) || 0 : 0
    })
  }

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
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0
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
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0
      }
      Aranea.FilamentSwitch {
        objectName: "autoSwitch"
        anchors.verticalCenter: parent.verticalCenter
        checked: section.auto
        hasCursor: section.cursorAuto
        opacity: section.busy ? 0.6 : 1
        clickGate: section
        onToggled: section.toggleAuto()
        HoverHandler {
          id: autoHover
          onHoveredChanged: if (hovered && !section.pointerGate)
            section.pillHovered(true, -1)
          onPointChanged: if (section.pointerGate && autoHover.hovered && section.pointerGate.moved(autoHover.parent, {
            x: autoHover.point.position.x,
            y: autoHover.point.position.y
          })) {
            section.autoMovedAt = Date.now()
            section.pillHovered(true, -1)
          }
        }
        PanelToolTip {
          fontFamily: Aranea.Typography.uiFamily
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
        refined: true
        required property var modelData
        required property int index
        width: pillRow.cellWidth
        text: modelData.label
        tooltipText: modelData.tooltip || ""
        selected: modelData.key !== undefined && modelData.key === section.selectedBand
        busy: section.busy && modelData.key === section.selectedBand
        hasCursor: !section.cursorAuto && section.cursorIndex === index
        pointerGate: section.pointerGate
        onClicked: section.pick(modelData.key)
        onHoveredMoved: section.pillHovered(false, index)
      }
    }
  }
}
