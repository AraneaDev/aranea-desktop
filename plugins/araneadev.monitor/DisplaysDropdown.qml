// The Aranea Displays dropdown's view: the header (the focused display's
// name, resolution and scale), the BRIGHTNESS slider with its level name,
// the night light and keyboard light rows, the TEXT SIZE stepped slider
// with its stops, the SCALE pills, the DISPLAYS list and the key hint.
// Drawn from one plain view object (Panel.displaysView) plus state kept out
// of it (the brightness, the night light, the keyboard light, the text
// stop, the selected scale, which displays are on, and every pending
// request), and reporting every user action through a single action
// signal. No processes here: tests drive it with fixtures.
//
// The Power lesson: the row arrays (scales, displays) never carry selected
// or on/off state, so a selection or toggle never rebuilds a delegate; a
// requested change shows at once and pulses busy until a re-read settles
// it. Any section changing height or visibility stamps layoutChangedAt
// (so does a text-size reflow, through noteLayoutChange); a click within
// 300 ms of that, or of its control being built, is ignored unless the
// pointer has really moved onto it since.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Column {
  id: dropdown

  // View state built by Panel.displaysView: {header: {title, caption,
  // glyph?}, brightness: {visible, label (the level name)}, nightlight:
  // {visible}, kbd: {visible, mode ("switch" or "slider"), max},
  // textStops: [px], scales: [{key (the scale value), label}],
  // scaleCaption (e.g. "2.67× · custom", or ""), displays: [{key (the
  // monitor name), label, detail, glyph}], cursor: {active, section,
  // index}, keyHint}. The rows carry no selected or enabled flag.
  property var view: ({})
  // The focused display's brightness, 0..100.
  property real brightnessPercent: 0
  // Whether a brightness set is running or queued: the slider pulses.
  property bool brightnessBusy: false
  // Whether a text-size reflow is in progress: the sliders ignore the
  // wheel meanwhile.
  property bool reflowing: false
  // Whether the night light is on, as read.
  property bool nightlightOn: false
  // The night light caption, e.g. "4000 K" or "Off".
  property string nightlightCaption: ""
  // A night light request not yet confirmed (the state asked for), or
  // null for none.
  property var nightlightPending: null
  // The keyboard light's level, as read.
  property int kbdValue: 0
  // A keyboard light level not yet confirmed, or -1 for none.
  property int kbdPending: -1
  // The text size's stop index (the requested one while textPending).
  property int textIndex: 0
  // Whether a text size change is in flight.
  property bool textPending: false
  // The scale key the pills mark chosen, as read.
  property string selectedScale: ""
  // A scale request not yet confirmed; "" for none. That pill reads
  // selected and pulses busy.
  property string pendingScale: ""
  // Which displays are enabled, as read: {name: bool}.
  property var enabledDisplays: ({})
  // Display requests not yet confirmed: {name: bool (the state asked for)}.
  property var pendingDisplays: ({})
  // The name of the only enabled display (its switch is disabled), or "".
  property string lastEnabled: ""
  // Whether every display switch and row is refused (a display command or
  // its fresh re-read is due): the switches show disabled, the pending
  // target keeps pulsing.
  property bool displaysLocked: false
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0
  // Filters synthetic hover from controls moving under a still pointer,
  // and carries layoutChangedAt to the controls that settle clicks.
  readonly property alias pointerGate: gate
  // Cursor object from the view, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      section: "",
      index: -1
    })
  // The view's header, or an empty one.
  readonly property var header: view && view.header ? view.header : ({})
  // The view's brightness section, or a hidden one.
  readonly property var brightness: view && view.brightness ? view.brightness : ({
      visible: false
    })
  // The view's night light row, or a hidden one.
  readonly property var nightlight: view && view.nightlight ? view.nightlight : ({
      visible: false
    })
  // The view's keyboard light row, or a hidden one.
  readonly property var kbd: view && view.kbd ? view.kbd : ({
      visible: false
    })
  // The keyboard light's highest level, at least 1.
  readonly property int kbdMax: Math.max(1, Math.round(Number(kbd.max) || 1))
  // The text size stops in px, or [].
  readonly property var textStops: view && Array.isArray(view.textStops) ? view.textStops : []
  // The view's scale pills, or [].
  readonly property var scales: view && Array.isArray(view.scales) ? view.scales : []
  // The view's display rows, or [].
  readonly property var displays: view && Array.isArray(view.displays) ? view.displays : []
  // Whether the night light reads on: the pending request, else as read.
  readonly property bool nightlightShownOn: typeof nightlightPending === "boolean" ? nightlightPending : nightlightOn
  // The keyboard light level shown: the pending request, else as read.
  readonly property int kbdLevel: kbdPending >= 0 ? kbdPending : kbdValue
  // The scale key the pills mark chosen: the pending one, else as read.
  readonly property string shownScale: pendingScale !== "" ? pendingScale : selectedScale

  // Emitted for every user action, NAME with its ARG:
  //   brightnessPreview ({value}): a brightness drag moved (0..100);
  //   brightnessCommit ({value}): a drag or click let go, or a wheel step;
  //   nightlight ({index: 0, key: "nightlight"}): the switch was clicked;
  //   kbd ({index: 0, key: "kbdlight", value}): a keyboard light level
  //     was asked for;
  //   textSize ({index, key: stop}): a text size stop was asked for (key
  //     is the stop in px);
  //   scale ({index, key}): a scale pill was clicked;
  //   display ({index, key: name, enable}): a display switch or row was
  //     clicked (never for the last enabled display, nor while locked);
  //   hover ({section, index, key}): the pointer really moved onto a
  //     control (through the gate); section is "brightness", "nightlight",
  //     "kbdlight", "textsize", "scale" or "monitors".
  // Keyed actions carry the key as the view saw it, so the host can refuse
  // one whose row changed underneath the click.
  signal action(string name, var arg)

  // Stamps layoutChangedAt: something (a section, a text-size reflow)
  // moved the controls without rebuilding them.
  function noteLayoutChange() {
    dropdown.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; called after every keyboard-driven move so a
  // stale pointer sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

  // The cursor's index in SECTION, or -1 when the cursor isn't active there.
  function cursorIn(section) {
    return cursor.active && cursor.section === section ? cursor.index : -1
  }

  // The key of SECTION's row INDEX: a scale value, a monitor name, or the
  // fixed key of a single-control section; "" when there's no such row.
  function keyAt(section, index) {
    var rows = section === "scale" ? dropdown.scales : section === "monitors" ? dropdown.displays : null
    if (rows === null)
      return index === 0 && ["brightness", "nightlight", "kbdlight", "textsize"].indexOf(section) !== -1 ? section : ""
    var row = rows[index]
    return row && typeof row.key === "string" ? row.key : ""
  }

  // Reports a real pointer move onto SECTION's row INDEX.
  function hoverAt(section, index) {
    dropdown.action("hover", {
      section: section,
      index: index,
      key: dropdown.keyAt(section, index)
    })
  }

  // Whether display NAME reads on: its pending request, else as read.
  function displayOn(name) {
    if (dropdown.pendingDisplays && typeof dropdown.pendingDisplays[name] === "boolean")
      return dropdown.pendingDisplays[name]
    return !!dropdown.enabledDisplays && dropdown.enabledDisplays[name] === true
  }

  // Asks to flip display INDEX; refused while the displays are locked and
  // for the last enabled display.
  function toggleDisplay(index) {
    var key = dropdown.keyAt("monitors", index)
    if (dropdown.displaysLocked || key === "" || key === dropdown.lastEnabled)
      return
    dropdown.action("display", {
      index: index,
      key: key,
      enable: !dropdown.displayOn(key)
    })
  }

  // Asks for text stop INDEX (rounded and clamped); nothing when it's the
  // one shown already.
  function requestTextIndex(index) {
    var last = dropdown.textStops.length - 1
    if (last < 0)
      return
    var next = Math.max(0, Math.min(last, Math.round(index)))
    if (next === dropdown.textIndex)
      return
    dropdown.action("textSize", {
      index: next,
      key: dropdown.textStops[next]
    })
  }

  spacing: Style.space(10)

  // A hairline above a section, shown with it.
  component Separator: Rectangle {
    objectName: "separator"
    width: parent ? parent.width : 0
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }

  Aranea.DropdownHeader {
    refined: true
    objectName: "displaysHeader"
    width: parent.width
    glyph: dropdown.header.glyph || String.fromCodePoint(0xf0379)
    title: dropdown.header.title || "Display"
    caption: dropdown.header.caption || ""
    onHeightChanged: dropdown.noteLayoutChange()
  }
  Separator {
    visible: brightnessSection.visible
  }
  Column {
    id: brightnessSection
    objectName: "brightnessSection"
    width: parent.width
    visible: !!dropdown.brightness.visible
    spacing: Style.space(4)
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()

    DisplaysCaption {
      width: parent.width
      title: "BRIGHTNESS"
      trailing: Math.round(brightSlider.dragging ? brightSlider.liveValue : dropdown.brightnessPercent) + "%" + (dropdown.brightness.label ? " · " + dropdown.brightness.label : "")
      trailingName: "brightnessCaption"
    }
    DisplaysControlRow {
      id: brightRow
      width: parent.width
      implicitHeight: brightSlider.implicitHeight
      hasCursor: dropdown.cursorIn("brightness") === 0
      pointerGate: dropdown.pointerGate
      onHoveredMoved: dropdown.hoverAt("brightness", 0)

      Aranea.FilamentSlider {
        id: brightSlider
        objectName: "brightnessSlider"
        anchors.fill: parent
        minimum: 0
        maximum: 100
        step: 5
        value: dropdown.brightnessPercent
        busy: dropdown.brightnessBusy
        clickGate: brightRow
        pointerGate: dropdown.pointerGate
        gateWheel: true
        wheelHeld: dropdown.reflowing
        onMoved: function (value) {
          if (brightSlider.dragging)
            dropdown.action("brightnessPreview", {
              value: Math.round(value)
            })
        }
        onCommitted: function (value) {
          dropdown.action("brightnessCommit", {
            value: Math.round(value)
          })
        }
      }
    }
  }
  Separator {
    visible: toggles.visible
  }
  DisplaysToggles {
    id: toggles
    width: parent.width
    visible: toggles.nightVisible || toggles.kbdVisible
    nightVisible: !!dropdown.nightlight.visible
    nightOn: dropdown.nightlightShownOn
    nightBusy: typeof dropdown.nightlightPending === "boolean"
    nightCaption: dropdown.nightlightCaption
    nightCursor: dropdown.cursorIn("nightlight") === 0
    kbdVisible: !!dropdown.kbd.visible && (dropdown.kbd.mode === "switch" || dropdown.kbd.mode === "slider")
    kbdMode: dropdown.kbd.mode === "slider" ? "slider" : "switch"
    kbdMax: dropdown.kbdMax
    kbdLevel: dropdown.kbdLevel
    kbdBusy: dropdown.kbdPending >= 0
    kbdCursor: dropdown.cursorIn("kbdlight") === 0
    pointerGate: dropdown.pointerGate
    reflowing: dropdown.reflowing
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()
    onNightToggled: dropdown.action("nightlight", {
      index: 0,
      key: "nightlight"
    })
    onKbdRequested: function (value) {
      dropdown.action("kbd", {
        index: 0,
        key: "kbdlight",
        value: value
      })
    }
    onHovered: function (section) {
      dropdown.hoverAt(section, 0)
    }
  }
  Separator {
    visible: textSection.visible
  }
  Column {
    id: textSection
    objectName: "textSection"
    // The stop index shown: under a drag, the nearest stop; else textIndex.
    readonly property int shownIndex: Math.max(0, Math.min(dropdown.textStops.length - 1, Math.round(textSlider.dragging ? textSlider.liveValue : dropdown.textIndex)))
    width: parent.width
    visible: dropdown.textStops.length > 0
    spacing: Style.space(4)
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()

    DisplaysCaption {
      width: parent.width
      title: "TEXT SIZE"
      trailing: dropdown.textStops.length > 0 ? dropdown.textStops[textSection.shownIndex] + " px" : ""
      trailingName: "textCaption"
    }
    DisplaysControlRow {
      id: textRow
      width: parent.width
      implicitHeight: textSlider.implicitHeight
      hasCursor: dropdown.cursorIn("textsize") === 0
      pointerGate: dropdown.pointerGate
      onHoveredMoved: dropdown.hoverAt("textsize", 0)

      Aranea.FilamentSlider {
        id: textSlider
        objectName: "textSlider"
        anchors.fill: parent
        minimum: 0
        maximum: Math.max(1, dropdown.textStops.length - 1)
        step: 1
        value: dropdown.textIndex
        busy: dropdown.textPending
        clickGate: textRow
        pointerGate: dropdown.pointerGate
        gateWheel: true
        wheelHeld: dropdown.reflowing
        onCommitted: function (value) {
          dropdown.requestTextIndex(value)
        }
      }
    }
    Item {
      id: stopRow
      // The node's width on the slider, so each label centres under its
      // stop.
      readonly property real nodeWidth: Style.space(12)
      width: parent.width
      implicitHeight: Style.font.caption + Style.space(4)

      Repeater {
        model: dropdown.textStops
        Text {
          id: stopLabel
          required property var modelData
          required property int index
          objectName: "textStop"
          // Where this stop's node sits on the slider.
          readonly property real centre: stopRow.nodeWidth / 2 + (stopRow.width - stopRow.nodeWidth) * stopLabel.index / Math.max(1, dropdown.textStops.length - 1)
          x: Math.max(0, Math.min(stopRow.width - stopLabel.width, stopLabel.centre - stopLabel.width / 2))
          anchors.verticalCenter: parent.verticalCenter
          text: String(stopLabel.modelData)
          color: stopLabel.index === textSection.shownIndex ? Aranea.DesignTokens.foreground : Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
          font.family: Aranea.Typography.technicalFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
  Separator {
    visible: scaleSection.visible
  }
  Column {
    id: scaleSection
    objectName: "scaleSection"
    width: parent.width
    visible: dropdown.scales.length > 0
    spacing: Style.space(8)
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()

    DisplaysCaption {
      width: parent.width
      title: "SCALE"
      trailing: dropdown.view && dropdown.view.scaleCaption ? dropdown.view.scaleCaption : ""
      trailingName: "scaleCaption"
    }
    Row {
      id: pillRow
      // Each pill's width: the row split evenly.
      readonly property real cellWidth: (width - spacing * (Math.max(1, dropdown.scales.length) - 1)) / Math.max(1, dropdown.scales.length)
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: dropdown.scales
        Item {
          id: cell
          required property var modelData
          required property int index
          // When this pill was built (Date.now()), for the settle guard.
          property real createdAt: 0

          // Whether a pointer click may choose this pill (the pill's
          // clickGate): settled since it was built and since the
          // dropdown's last layout shift, or moved onto since.
          function clickSettled() {
            return ClickSettle.clickSettled({
              now: Date.now(),
              createdAt: cell.createdAt,
              movedAt: pill.pointerMovedAt,
              layoutChangedAt: dropdown.layoutChangedAt
            })
          }

          width: pillRow.cellWidth
          height: pill.implicitHeight
          Component.onCompleted: cell.createdAt = Date.now()

          Aranea.FilamentPill {
            id: pill
            refined: true
            objectName: "scalePill"
            anchors.fill: parent
            text: cell.modelData.label || ""
            selected: cell.modelData.key !== undefined && cell.modelData.key === dropdown.shownScale
            busy: dropdown.pendingScale !== "" && cell.modelData.key === dropdown.pendingScale
            hasCursor: dropdown.cursorIn("scale") === cell.index
            pointerGate: dropdown.pointerGate
            clickGate: cell
            onClicked: dropdown.action("scale", {
              index: cell.index,
              key: dropdown.keyAt("scale", cell.index)
            })
            onHoveredMoved: dropdown.hoverAt("scale", cell.index)
          }
        }
      }
    }
  }
  Separator {
    visible: displaysSection.visible
  }
  DisplaysList {
    id: displaysSection
    objectName: "displaysSection"
    width: parent.width
    // Stock's rule: the list shows only with more than one display.
    visible: dropdown.displays.length > 1
    rows: dropdown.displays
    enabledDisplays: dropdown.enabledDisplays
    pendingDisplays: dropdown.pendingDisplays
    lastEnabled: dropdown.lastEnabled
    locked: dropdown.displaysLocked
    cursorIndex: dropdown.cursorIn("monitors")
    pointerGate: dropdown.pointerGate
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()
    onToggle: function (index) {
      dropdown.toggleDisplay(index)
    }
    onHovered: function (index) {
      dropdown.hoverAt("monitors", index)
    }
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    topPadding: Style.space(4)
    text: dropdown.view && dropdown.view.keyHint ? dropdown.view.keyHint : ""
    color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PointerMoveGate {
    id: gate
    // The dropdown's last layout shift, for the controls' clickSettled().
    property real layoutChangedAt: dropdown.layoutChangedAt

    referenceItem: dropdown
  }
}
