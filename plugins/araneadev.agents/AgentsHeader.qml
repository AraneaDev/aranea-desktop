// Header of the Aranea agents dropdown: the shared DropdownHeader with the
// tool's mark (an image, falling back to the bar glyph), the tool as title,
// the plan plus "updated HH:MM" as caption, and the Refresh pill in its
// trailing slot. Pure view: plain inputs in, signals out. The pill shows
// "Refreshing…" and breathes (without the selected look) while a refresh
// is in flight, and ignores
// clicks then; a click within 300 ms of the dropdown's layout shifting
// (pointerGate.layoutChangedAt) is ignored unless the pointer has really
// moved onto it since (FilamentPill's own settle).
import QtQuick
import "../araneadev.shared" as Aranea

Aranea.DropdownHeader {
  id: header
  refined: true

  // Whether a refresh is in flight: the pill reads "Refreshing…", pulses
  // and ignores clicks.
  property bool busy: false
  // Whether the keyboard cursor is on the Refresh pill.
  property bool hasCursor: false
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from the
  // pill moving under a still pointer.
  property var pointerGate: null
  // The Refresh pill, exposed for tests and the host's keyboard path.
  readonly property alias refreshPill: pill

  // Emitted when the Refresh pill is clicked while idle.
  signal refreshRequested
  // Emitted when the pointer really moves onto the Refresh pill.
  signal entered

  objectName: "agentsHeader"

  Aranea.FilamentPill {
    id: pill
    refined: true
    objectName: "refreshPill"
    text: header.busy ? "Refreshing" + String.fromCodePoint(0x2026) : "Refresh"
    busy: header.busy
    hasCursor: header.hasCursor
    pointerGate: header.pointerGate
    // Busy ignores every click: the refresh already running is the answer.
    onClicked: if (!header.busy)
      header.refreshRequested()
    onHoveredMoved: header.entered()
  }
}
