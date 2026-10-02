// The DNS provider section of the Aranea Network dropdown: a "DNS
// PROVIDER" caption over one FilamentPill per provider (DHCP, Cloudflare,
// Google, Custom), the current one selected. Pure view: plain inputs in,
// signals out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section

  // The providers: [{key, label, tooltip}]. No selected flag -- which one
  // is chosen comes from selectedProvider instead, so a selection change
  // alone never rebuilds the pills (their Repeater keeps its delegates).
  property var options: []
  // The provider the pills show chosen.
  property string selectedProvider: ""
  // A provider requested but not yet confirmed (actionProc hasn't exited);
  // "" for none. The pill with this key pulses busy.
  property string pendingProvider: ""
  // The keyboard cursor's pill, or -1 when the cursor isn't here.
  property int cursorIndex: -1
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from a pill
  // moving under a still pointer.
  property var pointerGate: null

  // Emitted when the pill for provider KEY is clicked.
  signal pick(string key)
  // Emitted when the pointer moves onto pill INDEX (through the gate).
  signal pillHovered(int index)

  objectName: "dnsSection"
  spacing: Style.space(10)

  Text {
    objectName: "dnsTitle"
    text: "DNS PROVIDER"
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }
  Row {
    id: pillRow
    // Each pill's width: the row split evenly.
    readonly property real cellWidth: (width - spacing * (Math.max(1, section.options.length) - 1)) / Math.max(1, section.options.length)
    width: parent.width
    spacing: Style.space(6)
    Repeater {
      model: section.options
      Aranea.FilamentPill {
        required property var modelData
        required property int index
        width: pillRow.cellWidth
        text: modelData.label
        tooltipText: modelData.tooltip || ""
        selected: modelData.key !== undefined && modelData.key === section.selectedProvider
        busy: section.pendingProvider !== "" && modelData.key === section.pendingProvider
        hasCursor: section.cursorIndex === index
        pointerGate: section.pointerGate
        onClicked: section.pick(modelData.key)
        onHoveredMoved: section.pillHovered(index)
      }
    }
  }
}
