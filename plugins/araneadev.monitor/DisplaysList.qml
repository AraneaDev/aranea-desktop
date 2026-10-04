// The displays list of the Aranea Displays dropdown: a caption with the
// count, then one NodeDeviceRow per display with a trailing switch. The
// rows are keyed by monitor name and carry no on/off state: whether a
// display reads on comes from `enabledDisplays` and `pendingDisplays`, so a toggle never
// rebuilds a delegate. A pending display reads its requested state at once
// and pulses busy; the last enabled display's switch is disabled, and so is
// every switch while the list is locked. Pure
// view: plain inputs in, signals out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: list

  // Display rows: [{key (the monitor name), label, detail, glyph}].
  property var rows: []
  // Which displays are enabled, as read: {name: bool}. Not named
  // "enabled": that would shadow QQuickItem.enabled.
  property var enabledDisplays: ({})
  // Requested but unconfirmed states: {name: bool}.
  property var pendingDisplays: ({})
  // The name of the only enabled display, or "" when more are on.
  property string lastEnabled: ""
  // Whether every switch is disabled (a display command or its re-read is
  // due).
  property bool locked: false
  // The keyboard cursor's row, or -1 when the cursor isn't here.
  property int cursorIndex: -1
  // The dropdown's PointerMoveGate (with layoutChangedAt).
  property var pointerGate: null

  // Emitted when row INDEX or its switch is clicked.
  signal toggle(int index)
  // Emitted when the pointer really moves onto row INDEX.
  signal hovered(int index)

  // Whether display NAME has a request in flight.
  function busyOf(name) {
    return !!list.pendingDisplays && typeof list.pendingDisplays[name] === "boolean"
  }

  // Whether display NAME reads on: its pending request, else as read.
  function onOf(name) {
    if (list.busyOf(name))
      return list.pendingDisplays[name]
    return !!list.enabledDisplays && list.enabledDisplays[name] === true
  }

  spacing: Style.space(4)

  DisplaysCaption {
    width: list.width
    title: "DISPLAYS"
    trailing: String(list.rows.length)
    trailingName: "displaysCount"
  }
  Repeater {
    model: list.rows
    Aranea.NodeDeviceRow {
      id: displayRow
      required property var modelData
      required property int index
      objectName: "displayRow"
      width: list.width
      glyph: displayRow.modelData.glyph || ""
      label: displayRow.modelData.label || ""
      detail: displayRow.modelData.detail || ""
      active: list.onOf(displayRow.modelData.key)
      // A display in use carries the selected highlight.
      selected: active
      busy: list.busyOf(displayRow.modelData.key)
      hasCursor: list.cursorIndex === displayRow.index
      pointerGate: list.pointerGate
      onChosen: list.toggle(displayRow.index)
      onEntered: list.hovered(displayRow.index)

      Aranea.FilamentSwitch {
        objectName: "displaySwitch"
        // A rebuild or a section growing can put this row under a still
        // pointer: the row's settle guard covers its switch too.
        clickGate: displayRow
        // The row's own hover fill covers the switch.
        ownHover: false
        checked: list.onOf(displayRow.modelData.key)
        busy: list.busyOf(displayRow.modelData.key)
        enabled: !list.locked && (list.lastEnabled === "" || list.lastEnabled !== displayRow.modelData.key)
        onToggled: list.toggle(displayRow.index)
      }
    }
  }
}
