// Aranea Clock (araneadev.clock, cloned from omarchy.clock): the bar's
// date/time label and the host for the calendar dropdown. Stock's root
// logic, label markup and IPC target stay. Added: the showcase IPC method,
// relayed to whichever instance's dropdown is open for README captures,
// and clockPanel, through which the instances share one wttr.in lookup.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "ClockLogic.js" as ClockLogic

// Date/time label for the bar, and the host for the calendar popup.
//
// Left click reveals the calendar - asking "what is the date?" is what a
// click on a clock means - right click walks the common label formats, and
// middle click opens the timezone picker.
BarWidget {
  id: root
  moduleName: "omarchy.clock"

  // The minute SystemClock below keeps current; the label and the formats
  // below read from it rather than Date.now() so every binding updates
  // together on the same tick.
  property date displayDate: clock.date

  // The horizontal or vertical label format in effect, from shell.json or
  // its stock default.
  readonly property string configuredFormat: vertical ? setting("verticalFormat", "HH\n—\nmm") : setting("format", "dddd HH:mm")
  // The alternate format right click cycles to next, same split by
  // orientation.
  readonly property string configuredAltFormat: vertical ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy") : setting("formatAlt", "d MMMM 'W'ww yyyy")

  // The ring cycleFormat() walks: the configured pair plus the stock
  // presets for this orientation, deduplicated.
  readonly property var formatRing: Model.clockFormatRing(configuredFormat, configuredAltFormat, Model.clockFormats(vertical))

  // What the bar shows is what shell.json stores, so a cycled format is the
  // format from then on rather than something that reverts on restart.
  readonly property string activeFormat: configuredFormat
  // The formatted label text for the current minute.
  readonly property string displayText: formatted(displayDate)
  // displayText split into the vertical layout's stacked lines.
  readonly property var verticalLines: displayText.split("\n")

  // Re-reads the clock and forwards to the open panel, if any (the IPC
  // refresh method and the periodic poll both call this).
  function refresh() {
    displayDate = new Date()
    // qmllint disable missing-property
    if (panelLoader.item && panelLoader.item.refresh)
      panelLoader.item.refresh()
    // qmllint enable missing-property
  }

  // Right click: advances to the next format in formatRing and persists it.
  function cycleFormat() {
    var current = String(configuredFormat)
    var next = Model.nextClockFormat(formatRing, current)
    if (next === "" || next === current)
      return
    var entry = {
      id: root.moduleName
    }
    for (var key in root.settings)
      if (key !== "id")
        entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    // qmllint disable missing-property
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    // qmllint enable missing-property
  }

  // Renders date against activeFormat, substituting the ISO week token.
  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  // ---- Calendar popup. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  // qmllint disable missing-property
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  // qmllint enable missing-property

  // Opens the calendar popup.
  function open() {
    // qmllint disable missing-property
    if (panelLoader.item)
      panelLoader.item.open()
    // qmllint enable missing-property
  }

  // Closes the calendar popup.
  function close() {
    // qmllint disable missing-property
    if (panelLoader.item)
      panelLoader.item.close()
    // qmllint enable missing-property
  }

  // This instance's loaded Panel.qml, or null; the other monitors'
  // panels read its wttr.in place through it (Panel.peerAreas).
  readonly property var clockPanel: panelLoader.item

  // The showcase IPC method: the IPC target lands on one instance, while
  // the dropdown may be open on another monitor's, so the stand-in place
  // goes to whichever instance is open (ClockLogic.firstOpen); "closed"
  // when none is.
  function showcase(placeJson) {
    // qmllint disable missing-property
    var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : []
    // qmllint enable missing-property
    var open = ClockLogic.firstOpen(items.length > 0 ? items : [root])
    return open && typeof open.showcaseHere === "function" ? open.showcaseHere(placeJson) : "closed"
  }

  // Hands the stand-in place to this instance's popup; "closed" before it
  // has loaded.
  function showcaseHere(placeJson) {
    // qmllint disable missing-property
    if (panelLoader.item && typeof panelLoader.item.showcase === "function")
      return panelLoader.item.showcase(placeJson)
    // qmllint enable missing-property
    return "closed"
  }

  // Opens the popup if closed, closes it if open.
  function togglePanel() {
    // qmllint disable missing-property
    if (panelLoader.item)
      panelLoader.item.toggle()
    // qmllint enable missing-property
  }

  // Forwards the "W" week-start toggle to the popup (used by the IPC method).
  function toggleWeekStart() {
    // qmllint disable missing-property
    if (panelLoader.item)
      panelLoader.item.toggleWeekStart()
    // qmllint enable missing-property
  }

  // The clock fills more slot than it paints a mark for, at both
  // orientations: horizontally it is a text label in a padded slot, so the
  // dot takes the label width; vertically it is a stack of icon-sized lines,
  // so the dot takes one line - the same mark every icon widget gets, rather
  // than a rule running the height of the whole stack.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  // The open-panel dot's height at the vertical orientation (one icon line).
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  // qmllint disable missing-property
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  // qmllint enable missing-property

  // Closes the popup for a popout hand-off rather than a normal dismissal.
  function closeForPopoutSwitch() {
    // qmllint disable missing-property
    if (panelLoader.item)
      panelLoader.item.closeForPopoutSwitch()
    // qmllint enable missing-property
  }

  // Hands the loaded Panel.qml instance the bar, settings and anchor it
  // needs; called again after load since the loader's onLoaded can race the
  // bindings below.
  function injectPanel() {
    var target = panelLoader.item
    if (!target)
      return
    if ("bar" in target)
      target.bar = root.bar
    if ("settings" in target)
      target.settings = root.settings
    if ("anchorItem" in target)
      target.anchorItem = button
    if ("hostWidget" in target)
      target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "omarchy.clock"

    function refresh(): void {
      root.broadcast("refresh")
    }
    function cycleFormat(): void {
      root.cycleFormat()
    }
    function toggleWeekStart(): void {
      root.toggleWeekStart()
    }
    function open(): void {
      root.open()
    }
    function close(): void {
      root.close()
    }
    function show(): void {
      root.open()
    }
    function hide(): void {
      root.close()
    }
    function toggle(): void {
      root.togglePanel()
    }
    // Screenshot stand-in (scripts/capture-screenshots): PLACEJSON, a
    // {"name", "latitude", "longitude"} object, replaces the sun and moon
    // place until the dropdown closes; while it is closed the answer is
    // "closed" and nothing is set. Display only.
    function showcase(placeJson: string): string {
      return root.showcase(placeJson)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function (b) {
      if (b === Qt.RightButton)
        root.cycleFormat()
      else if (b === Qt.MiddleButton) {
        // qmllint disable missing-property
        if (root.bar)
          root.bar.run("omarchy-menu-timezone")
        // qmllint enable missing-property
      } else
        root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
