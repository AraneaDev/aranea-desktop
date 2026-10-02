// Aranea Clock (araneadev.clock, cloned from omarchy.clock): the bar's
// date/time label and the host for the calendar popup. This is the Task 2
// clone: the stock root logic, markup and IPC target below are unchanged
// from Omarchy's Clock, so the bar entry keeps working identically while
// the Aranea-native dropdown view lands in a later task.
// Temporary for this clone (stock's dynamic root.bar.* access and its lack
// of ComponentBehavior: Bound); Task 4 removes this once the view is rebuilt.
// qmllint disable missing-property unqualified
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

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
    if (panelLoader.item && panelLoader.item.refresh)
      panelLoader.item.refresh()
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
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Renders date against activeFormat, substituting the ISO week token.
  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  // ---- Calendar popup. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  // Opens the calendar popup.
  function open() {
    if (panelLoader.item)
      panelLoader.item.open()
  }

  // Closes the calendar popup.
  function close() {
    if (panelLoader.item)
      panelLoader.item.close()
  }

  // Opens the popup if closed, closes it if open.
  function togglePanel() {
    if (panelLoader.item)
      panelLoader.item.toggle()
  }

  // Forwards the "W" week-start toggle to the popup (used by the IPC method).
  function toggleWeekStart() {
    if (panelLoader.item)
      panelLoader.item.toggleWeekStart()
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
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  // Closes the popup for a popout hand-off rather than a normal dismissal.
  function closeForPopoutSwitch() {
    if (panelLoader.item)
      panelLoader.item.closeForPopoutSwitch()
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
        if (root.bar)
          root.bar.run("omarchy-menu-timezone")
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
