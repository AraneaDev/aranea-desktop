// The night light and keyboard light rows of the Aranea Displays
// dropdown. Night light: its caption ("4000 K" or "Off") and a switch.
// Keyboard light: a switch for an on/off device, or a stepped slider with
// its level for one with levels. Both show a requested change at once
// (the inputs are already the pending state) and pulse busy until it is
// applied. Pure view: plain inputs in, signals out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: toggles

  // Whether the night light row shows.
  property bool nightVisible: false
  // Whether the night light reads on (the pending request while one is in
  // flight).
  property bool nightOn: false
  // Whether a night light change is in flight.
  property bool nightBusy: false
  // The night light caption, e.g. "4000 K" or "Off".
  property string nightCaption: ""
  // Whether the keyboard cursor is on the night light row.
  property bool nightCursor: false
  // Whether the keyboard light row shows.
  property bool kbdVisible: false
  // "switch" for an on/off device, "slider" for one with levels.
  property string kbdMode: "switch"
  // The keyboard light's highest level (1 for on/off).
  property int kbdMax: 1
  // The keyboard light's level (the pending request while one is in
  // flight).
  property int kbdLevel: 0
  // Whether a keyboard light change is in flight.
  property bool kbdBusy: false
  // Whether the keyboard cursor is on the keyboard light row.
  property bool kbdCursor: false
  // The dropdown's PointerMoveGate (with layoutChangedAt).
  property var pointerGate: null
  // Whether the dropdown is reflowing (a text-size change): the keyboard
  // light slider ignores the wheel meanwhile.
  property bool reflowing: false

  // Emitted when the night light switch is clicked.
  signal nightToggled
  // Emitted with the keyboard light level a click, drag or wheel asked for.
  signal kbdRequested(int value)
  // Emitted when the pointer really moves onto row SECTION ("nightlight"
  // or "kbdlight").
  signal hovered(string section)

  spacing: Style.space(8)

  DisplaysControlRow {
    id: nightRow
    objectName: "nightlightRow"
    width: toggles.width
    implicitHeight: Math.max(nightTitle.implicitHeight, nightSwitch.implicitHeight)
    visible: toggles.nightVisible
    hasCursor: toggles.nightCursor
    pointerGate: toggles.pointerGate
    onHoveredMoved: toggles.hovered("nightlight")

    DisplaysCaption {
      id: nightTitle
      anchors.left: parent.left
      anchors.right: nightSwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      title: "NIGHT LIGHT"
      trailing: toggles.nightCaption
      trailingName: "nightlightCaption"
    }
    Aranea.FilamentSwitch {
      id: nightSwitch
      objectName: "nightlightSwitch"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: toggles.nightOn
      busy: toggles.nightBusy
      clickGate: nightRow
      onToggled: toggles.nightToggled()
    }
  }
  Column {
    objectName: "kbdRow"
    width: toggles.width
    visible: toggles.kbdVisible
    spacing: Style.space(4)

    DisplaysControlRow {
      id: kbdSwitchRow
      width: toggles.width
      implicitHeight: Math.max(kbdTitle.implicitHeight, kbdSwitch.implicitHeight)
      visible: toggles.kbdMode === "switch"
      hasCursor: toggles.kbdCursor
      pointerGate: toggles.pointerGate
      onHoveredMoved: toggles.hovered("kbdlight")

      DisplaysCaption {
        id: kbdTitle
        anchors.left: parent.left
        anchors.right: kbdSwitch.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        title: "KEYBOARD LIGHT"
      }
      Aranea.FilamentSwitch {
        id: kbdSwitch
        objectName: "kbdSwitch"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: toggles.kbdLevel > 0
        busy: toggles.kbdBusy
        clickGate: kbdSwitchRow
        onToggled: toggles.kbdRequested(toggles.kbdLevel > 0 ? 0 : Math.max(1, toggles.kbdMax))
      }
    }
    DisplaysCaption {
      width: toggles.width
      visible: toggles.kbdMode === "slider"
      title: "KEYBOARD LIGHT"
      trailing: Math.round(kbdSlider.dragging ? kbdSlider.liveValue : toggles.kbdLevel) + "/" + toggles.kbdMax
      trailingName: "kbdCaption"
    }
    DisplaysControlRow {
      id: kbdSliderRow
      width: toggles.width
      implicitHeight: kbdSlider.implicitHeight
      visible: toggles.kbdMode === "slider"
      hasCursor: toggles.kbdCursor
      pointerGate: toggles.pointerGate
      onHoveredMoved: toggles.hovered("kbdlight")

      Aranea.FilamentSlider {
        id: kbdSlider
        objectName: "kbdSlider"
        anchors.fill: parent
        minimum: 0
        maximum: Math.max(1, toggles.kbdMax)
        step: 1
        value: toggles.kbdLevel
        busy: toggles.kbdBusy
        clickGate: kbdSliderRow
        gateWheel: true
        wheelHeld: toggles.reflowing
        onCommitted: function (value) {
          var level = Math.max(0, Math.min(toggles.kbdMax, Math.round(value)))
          if (level !== toggles.kbdLevel)
            toggles.kbdRequested(level)
        }
      }
    }
  }
}
