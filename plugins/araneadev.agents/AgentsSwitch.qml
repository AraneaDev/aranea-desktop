// The agent switch of the Aranea agents dropdown: one FilamentPill per
// agent, the current one in the pill's own selected look. Shown only with
// more than one agent (stock's rule). Pure view: plain inputs in, signals
// out.
//
// The Repeater runs over the agent count, so a refresh that rebuilds the
// agents array with the same keys never recreates a pill (its settle
// window and hover state survive). Each choice carries the pill's key (the
// provider id) as it was when the pointer pressed it, so the host can
// refuse a click whose pill changed underneath between press and release.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Row {
  id: section

  // Agent pills: [{key, label, selected}].
  property var agents: []
  // Cursor pill index here, or -2 when the keyboard cursor isn't on the
  // switch.
  property int cursor: -2
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from a pill
  // moving under a still pointer; its layoutChangedAt settles clicks.
  property var pointerGate: null

  // An even share of the row per pill: the cap on each pill's width.
  readonly property real cellWidth: {
    var n = (section.agents || []).length
    return n > 0 ? (section.width - section.spacing * (n - 1)) / n : section.width
  }

  // Emitted when pill INDEX (holding KEY when pressed) is chosen.
  signal chosen(int index, string key)
  // Emitted when the pointer really moves onto pill INDEX.
  signal pillHovered(int index)

  // The pill at INDEX, or null when out of range (for tests and a host
  // that needs its geometry).
  function pillAt(index) {
    return repeater.itemAt(index)
  }

  visible: (section.agents || []).length > 1
  spacing: Style.space(8)

  Repeater {
    id: repeater
    model: (section.agents || []).length

    Aranea.FilamentPill {
      id: chip
      refined: true
      required property int index
      // This pill's agent, read from the live array.
      readonly property var agent: section.agents[chip.index] || ({
          key: "",
          label: "",
          selected: false
        })
      // The pill's key (the provider id), sent with its choice.
      readonly property string key: chip.agent && chip.agent.key !== undefined ? String(chip.agent.key) : ""
      // The key the pill held when the pointer last pressed it, "" when
      // no press is pending (the keyboard's activate()).
      property string pressedKey: ""

      objectName: "agentPill"
      // Natural width, capped at an even share of the row (stock's even
      // split), so long labels elide instead of overflowing.
      width: Math.min(chip.implicitWidth, section.cellWidth)
      text: chip.agent.label || ""
      selected: !!chip.agent.selected
      hasCursor: section.cursor === chip.index
      pointerGate: section.pointerGate
      onPressed: chip.pressedKey = chip.key
      // A press that ends without a choice forgets its key, so a later
      // keyboard activate() never sends a stale one.
      onPressCanceled: chip.pressedKey = ""
      onClicked: {
        var key = chip.pressedKey !== "" ? chip.pressedKey : chip.key
        chip.pressedKey = ""
        section.chosen(chip.index, key)
      }
      onHoveredMoved: section.pillHovered(chip.index)
    }
  }
}
