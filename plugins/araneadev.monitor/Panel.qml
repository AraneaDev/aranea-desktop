// Aranea Display (araneadev.monitor, cloned from omarchy.monitor): the bar
// display icon and its dropdown. Stock's root logic stays (the
// omarchy-monitor-state poll, the debounced and queued brightness setter,
// the brightness and state IPC, the display toggle with its last-display
// guard, scale, text size with its reflow guard, the bar wheel accumulator
// and the 5 s refresh while open). Added here: the night light and keyboard
// light, instant pending state with a last-wins queue for every command,
// and the keyed keyboard cursor. The pure view, DisplaysDropdown, draws it
// in the shared keyboard frame. The rules are DisplaysLogic.js / Model.js /
// CursorLogic.js functions, tested under Node.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "DisplaysLogic.js" as DisplaysLogic
import "../araneadev.shared/CursorLogic.js" as CursorLogic
import "../araneadev.shared" as Aranea

Panel {
  id: root
  moduleName: "omarchy.monitor"
  ipcTarget: "omarchy.monitor"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits, needed for the brightness + state methods below.
  manageIpc: false

  // The displayed device's brightness, 0-100 (DDC/sysfs, via
  // `omarchy-monitor-state`), or 0 when no backlight is controllable.
  property int brightnessPercent: 0
  // The value a brightness change was last sent with; re-sent by
  // setBrightnessProc's exit handler when brightnessSetQueued is true.
  property int pendingBrightnessPercent: 0
  // True when a brightness change arrived while setBrightnessProc was
  // already running; the last value wins once it exits.
  property bool brightnessSetQueued: false
  // Whether a controllable backlight was detected.
  property bool brightnessAvailable: false
  // The internal (laptop) display's name, or "" when there is none.
  property string internalMonitor: ""
  // The external display's name, or "" when there is none.
  property string externalMonitor: ""
  // The name of the currently focused display.
  property string focusedMonitor: ""
  // Whether the internal display is enabled.
  property bool internalEnabled: false
  // Whether the external display mirrors the internal one.
  property bool mirrorEnabled: false
  // The focused display's scale, normalized (Model.normalizeScale).
  property string monitorScale: ""
  // The parsed displays list from `omarchy-monitor-state`'s JSON.
  property var displays: []
  // How many entries in displays are enabled.
  property int enabledDisplayCount: 0

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // Cursor model shared by keyboard and mouse. Sections, in keyboard order
  // (DisplaysLogic.sectionsFor): "brightness", "nightlight", "kbdlight",
  // "textsize" (one control each, index 0), "scale" (the pills, walked
  // with left/right) and "monitors" (the display rows, walked with up/down).
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  // The scale presets available for the focused display (scalePresets
  // filtered to the ones its mode actually honors), or scalePresets itself
  // before any display has loaded.
  readonly property var scaleValues: {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.availableScales(scalePresets, display.width, display.height)
    }
    return scalePresets
  }
  // Which cursor section currently has keyboard/mouse focus.
  property string focusSection: "scale"
  // The focused row/pill within focusSection; 0 for the one-control
  // sections.
  property int selectedIndex: 0
  // Whether keyboard/mouse navigation has placed a cursor yet.
  property bool cursorActive: false
  // True while the keyboard drives the cursor; any pointer action clears it.
  // The view outlines the cursor only then, so the mouse never shows one.
  property bool keyboardCursor: false
  // The key of the row the cursor was deliberately put on (a move, an
  // adjustment or a hover; never an open or a keyboard reveal): a scale
  // value, a monitor name, or the section name of a one-control section.
  // The cursor follows it when the rows change, and Enter refuses while it
  // is "" or no longer under the cursor (CursorLogic.cursorConfirmed).
  property string cursorKey: ""

  // Text size slider: curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1
  // A text size (px) asked for while textScaleProc was already running, run
  // when it exits (the last one wins); 0 for none.
  property int queuedTextPx: 0

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section,
  // otherwise left/right on the text-size slider can jump focus to another row.
  property bool reflowingText: false
  // Marks a text-size reflow in progress and arms reflowSettle to clear it;
  // also stamps the view's layout, so a click landing mid-reflow is settled.
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
    dropdown.noteLayoutChange()
  }

  // ---------- Aranea additions: night light, keyboard light, pending ----------

  // Whether `omarchy-toggle-nightlight --status` answered (the row hides
  // otherwise).
  property bool nightAvailable: false
  // Whether the night light is on, as read.
  property bool nightOn: false
  // The night light row's caption (DisplaysLogic.nightlightCaption).
  property string nightCaption: "Off"
  // The night light temperature as read (K), or null with none; the
  // toggle's prediction depends on it (DisplaysLogic.nightToggleTarget).
  property var nightTemperature: null
  // The night light state asked for but not yet confirmed by a re-read, or
  // null for none. Shown at once and pulsing busy.
  property var nightPending: null
  // The state the running omarchy-toggle-nightlight will leave, so its exit
  // handler can toggle again when the latest request differs (last wins).
  property bool nightTarget: false
  // How many night light toggles have exited, and the count when the
  // running status read started: a read only settles a request when it
  // started after the last toggle exited.
  property int nightSerial: 0
  // See nightSerial.
  property int nightReadSerial: -1

  // The keyboard backlight device (DisplaysLogic.kbdDevice), "" for none.
  property string kbdDevice: ""
  // Whether `ls /sys/class/leds` has been read (the device is found once).
  property bool kbdDeviceChecked: false
  // The keyboard light's level and maximum, as read (max 0 hides the row).
  property int kbdValue: 0
  // See kbdValue.
  property int kbdMax: 0
  // A keyboard light level asked for but not yet confirmed, or -1.
  property int kbdPending: -1
  // A level asked for while kbdSetProc was already running, or -1.
  property int kbdQueued: -1
  // Exit and read counters for the keyboard light, as nightSerial.
  property int kbdSerial: 0
  // See kbdSerial.
  property int kbdReadSerial: -1
  // The keyboard light row's control (DisplaysLogic.kbdMode).
  readonly property string kbdMode: DisplaysLogic.kbdMode(kbdMax)

  // A scale asked for but not yet confirmed by a re-read; "" for none.
  property string pendingScale: ""
  // A scale asked for while actionProc was already running; "" for none.
  property string queuedScale: ""
  // The display focused when queuedScale was clicked; the scale only lands
  // there (DisplaysLogic.scaleCommand).
  property string queuedScaleMonitor: ""
  // Display requests not yet confirmed: {name: the enabled state asked for}.
  property var pendingDisplays: ({})
  // What the running actionProc does: {kind: "scale" or "display", key,
  // enable (a display request's asked-for state)},
  // so a failure drops only that request's pending state, and a scale
  // queued behind a display command is dropped (DisplaysLogic.nextAction).
  property var actionRunning: null
  // Exit and read counters for actionProc and stateProc, as nightSerial.
  property int actionSerial: 0
  // See actionSerial.
  property int stateReadSerial: -1
  // The actionSerial the last landed state read started at, -1 for none.
  property int stateLandedSerial: -1
  // The actionSerial right after the last display command exited, 0 for
  // none: the switches stay locked until a read started after it lands.
  property int displayExitSerial: 0
  // How many state reads have started, and the count the running (or last)
  // read started as.
  property int stateReadCount: 0
  // See stateReadCount.
  property int stateReadId: 0
  // The count the last landed state read started as.
  property int stateLandedRead: 0
  // stateReadCount when the dropdown last opened: the switches stay locked
  // until a read started since then lands.
  property int openReadMark: 0
  // A display request's exit: {name: actionSerial right after its command
  // exited}, so only reads started since count toward settling it.
  property var displayExits: ({})
  // How many fresh reads have not yet shown a display request: {name:
  // count} (DisplaysLogic.settleDisplayPending drops it on the third).
  property var displayReads: ({})
  // Whether every display switch and row is refused: a command runs, the
  // last display command's fresh read hasn't landed, or no read started
  // since the open has (DisplaysLogic.displaysLocked). Display switches are
  // never queued.
  readonly property bool displaysLocked: DisplaysLogic.displaysLocked({
    running: actionProc.running,
    exitSerial: displayExitSerial,
    landedSerial: stateLandedSerial,
    openMark: openReadMark,
    landedRead: stateLandedRead
  })

  // Row arrays kept by CursorLogic.keepRows, so an unchanged refresh hands
  // the view the same array and its Repeaters keep their delegates.
  property var rowCache: ({})

  // The sections shown given the current state, in keyboard order.
  readonly property var visibleSections: DisplaysLogic.sectionsFor({
    brightness: brightnessAvailable,
    nightlight: nightAvailable,
    kbd: kbdMode !== "none",
    displayCount: displays.length
  })

  // The focused display, or null before any display has loaded.
  readonly property var focusedDisplay: {
    for (var i = 0; i < displays.length; i++) {
      if (displays[i] && displays[i].focused)
        return displays[i]
    }
    return null
  }

  // The scale pills, keyed by scale value. No selected flag: which one is
  // chosen is selectedScaleKey / pendingScale, passed separately.
  readonly property var scaleRows: CursorLogic.keepRows(rowCache, "scales", scaleValues.map(function (value) {
    return {
      key: String(value),
      label: root.effectiveScale(value) + "×"
    }
  }))

  // The display rows, keyed by monitor name. No enabled flag: that is
  // enabledDisplayMap / pendingDisplays, passed separately.
  readonly property var displayRows: CursorLogic.keepRows(rowCache, "displays", displays.map(function (d) {
    var name = String(d && d.name || "")
    var size = d && d.width && d.height ? d.width + "×" + d.height : ""
    var parts = size !== "" ? [size] : []
    if (d && d.focused)
      parts.push("focused")
    return {
      key: name,
      label: name,
      detail: parts.join(" · "),
      glyph: String.fromCodePoint(name !== "" && name === root.internalMonitor ? 0xf0322 : 0xf0379)
    }
  }))

  // Which displays are enabled, as read: {name: bool}.
  readonly property var enabledDisplayMap: {
    var map = {}
    for (var i = 0; i < displays.length; i++) {
      var d = displays[i]
      if (d && d.name)
        map[String(d.name)] = !!d.enabled
    }
    return map
  }

  // The only display confirmed on (its switch is disabled), or "": a
  // display only pending on never counts (DisplaysLogic.lastEnabledName).
  readonly property string lastEnabled: DisplaysLogic.lastEnabledName(enabledDisplayMap, pendingDisplays)

  // The scale key the pills mark chosen, as read: the active preset
  // (Model.matchingScaleIndex), or "" with no match.
  readonly property string selectedScaleKey: {
    var idx = activeScaleIndex()
    return idx >= 0 && idx < scaleValues.length ? String(scaleValues[idx]) : ""
  }

  // The view object DisplaysDropdown draws (its documented shape). The
  // states (brightness, night light, keyboard light, text stop, chosen
  // scale, enabled displays and every pending request) are separate.
  readonly property var displaysView: ({
      header: {
        title: "Display",
        caption: DisplaysLogic.headerCaption(focusedDisplay, focusedDisplay ? effectiveScale(monitorScale) : ""),
        glyph: String.fromCodePoint(displays.length > 1 ? 0xf037a : 0xf0379)
      },
      brightness: {
        visible: brightnessAvailable,
        label: brightnessName(brightnessPercent)
      },
      nightlight: {
        visible: nightAvailable
      },
      kbd: {
        visible: kbdMode !== "none",
        mode: kbdMode,
        max: kbdMax
      },
      textStops: textSizeStops,
      scales: scaleRows,
      scaleCaption: DisplaysLogic.scaleCaption(selectedScaleKey, pendingScale, focusedDisplay ? effectiveScale(monitorScale) : ""),
      displays: displayRows,
      cursor: {
        active: cursorActive && keyboardCursor,
        section: focusSection,
        index: selectedIndex
      },
      keyHint: DisplaysLogic.keyHint(focusSection, kbdMode)
    })

  // The rows of SECTION for the keyed cursor: the scale pills, the display
  // rows, or one row keyed by the section's own name. [] for the lists
  // while their bindings are still being built (a change handler can run
  // during construction).
  function sectionRows(section) {
    if (section === "scale")
      return Array.isArray(scaleRows) ? scaleRows : []
    if (section === "monitors")
      return Array.isArray(displayRows) ? displayRows : []
    return [
      {
        key: section
      }
    ]
  }

  // The key of SECTION's row INDEX, "" when there is none.
  function keyAt(section, index) {
    var row = sectionRows(section)[index]
    return row && typeof row.key === "string" ? row.key : ""
  }

  // Where the cursor lands on entering SECTION: the active scale pill, the
  // first display, or the one control.
  function sectionLanding(section) {
    if (section === "scale")
      return Math.max(0, activeScaleIndex())
    return 0
  }

  // Moves the keyboard cursor by delta rows: through the display rows, else
  // to the next or previous section (DisplaysLogic.moveSection). The row it
  // lands on is a deliberate choice.
  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0)
      return
    if (focusSection === "monitors") {
      var row = selectedIndex + delta
      if (row >= 0 && row < displayRows.length) {
        selectedIndex = row
        cursorKey = keyAt(focusSection, selectedIndex)
        return
      }
    }
    var next = DisplaysLogic.moveSection(sections, focusSection, delta)
    if (next !== focusSection) {
      focusSection = next
      selectedIndex = sectionLanding(next)
    }
    cursorKey = keyAt(focusSection, selectedIndex)
  }

  // Left/right in the scale section: walks the pill row (choosing nothing
  // until Enter); everywhere else, a no-op.
  function moveCursorH(delta) {
    if (focusSection !== "scale")
      return
    var next = selectedIndex + delta
    if (next < 0)
      next = 0
    if (next > scaleValues.length - 1)
      next = scaleValues.length - 1
    selectedIndex = next
    cursorKey = keyAt(focusSection, selectedIndex)
  }

  // Nudges brightness by delta when the brightness slider has focus; a
  // no-op elsewhere or with no controllable backlight.
  function adjustBrightness(delta) {
    if (focusSection !== "brightness")
      return
    if (!brightnessAvailable)
      return
    setBrightness(root.brightnessPercent + delta)
  }

  // Left/right on the keyboard light: a step on the slider, or off/on on
  // the switch.
  function adjustKbd(delta) {
    if (kbdMode === "slider")
      setKbd(kbdShownLevel() + delta)
    else if (kbdMode === "switch")
      setKbd(delta > 0 ? kbdMax : 0)
  }

  // Applies the action for whatever the keyboard cursor is on, only when
  // it is still the row the user chose (CursorLogic.cursorConfirmed): the
  // night light or keyboard switch toggles, a scale pill is set, a display
  // is switched. The sliders have no separate activation.
  function activateCursor() {
    if (!CursorLogic.cursorConfirmed(sectionRows(focusSection), cursorKey, selectedIndex))
      return
    if (focusSection === "nightlight")
      toggleNightlight()
    else if (focusSection === "kbdlight" && kbdMode === "switch")
      setKbd(kbdShownLevel() > 0 ? 0 : kbdMax)
    else if (focusSection === "scale")
      setScale(cursorKey)
    else if (focusSection === "monitors")
      toggleDisplay(cursorKey, displayShownOn(cursorKey))
  }

  // Keeps focusSection/selectedIndex inside the currently visible sections
  // and rows after the data they point at changes, following cursorKey
  // (CursorLogic.followCursor).
  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length)
      return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionLanding(focusSection)
      cursorKey = ""
      return
    }
    var rows = sectionRows(focusSection)
    if (cursorKey !== "") {
      var next = CursorLogic.followCursor(rows, cursorKey, selectedIndex)
      selectedIndex = Math.max(0, next.index)
      cursorKey = next.key
      return
    }
    if (selectedIndex > rows.length - 1)
      selectedIndex = rows.length - 1
    if (selectedIndex < 0)
      selectedIndex = 0
  }

  // The `brightness` IPC method: sets brightness and reports the value sent.
  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  // The `state` IPC method's JSON reply.
  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.focusedMonitor,
      scale: root.monitorScale,
      displays: root.displays
    })
  }

  IpcHandler {
    target: "omarchy.monitor"

    function brightness(percent: string): string {
      return root.brightnessIpc(percent)
    }
    function state(): string {
      return root.stateIpc()
    }
    function open() {
      root.open()
    }
    function close() {
      root.close()
    }
    function toggle() {
      root.toggle()
    }
    function show() {
      root.open()
    }
    function hide() {
      root.close()
    }
  }

  // Starts omarchy-monitor-state when it isn't already running; while
  // open, re-reads the night light and keyboard light too.
  function refresh() {
    if (!stateProc.running)
      stateProc.running = true
    if (opened) {
      readNight()
      readKbd()
    }
  }

  // Sets brightness: clamps value, updates the local state at once, and
  // runs (or queues behind) omarchy-brightness-display.
  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, percent + "%"]
    setBrightnessProc.running = true
  }

  // Shows value live while dragging the slider, and debounces the actual
  // brightness command until the drag settles.
  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  // Summons the OSD with the brightness glyph and value.
  function showBrightnessOsd(percent) {
    // qmllint disable missing-property
    if (!root.bar || !root.bar.shell)
      return
    root.bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
    // qmllint enable missing-property
  }

  // Normalizes a scale string, delegating to Model.js.
  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  // The index into scaleValues matching the focused display's current
  // scale, or -1 with no match or no focused display.
  function activeScaleIndex() {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.matchingScaleIndex(scaleValues, monitorScale, display.width, display.height)
    }
    return -1
  }

  // The scale a requested preset actually resolves to on the focused
  // display's mode, delegating to Model.cleanScale.
  function effectiveScale(scale) {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.cleanScale(scale, display.width, display.height)
    }
    return normalizeScale(scale)
  }

  // Playful mood-name for a given brightness percent. Bands intentionally
  // span ~10-20 points so casual tweaks change the label, while small
  // nudges within one band don't.
  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  // Parses omarchy-monitor-state's displays JSON into displays and
  // enabledDisplayCount.
  function updateDisplays(displaysJson) {
    var parsed = Model.parseDisplays(displaysJson)
    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
  }

  // Whether display NAME reads on: its pending request, else as read.
  function displayShownOn(name) {
    if (typeof pendingDisplays[name] === "boolean")
      return pendingDisplays[name]
    return enabledDisplayMap[name] === true
  }

  // Enables or disables a display via `hyprctl eval`, never queued: refused
  // for a name DisplaysLogic.displayCommand won't quote, while the switches
  // are locked (displaysLocked), and a disable unless another display is
  // confirmed on with no pending entry (DisplaysLogic.mayToggleDisplay /
  // mayDisable). Shown at once (pendingDisplays).
  function toggleDisplay(name, enabled) {
    var command = DisplaysLogic.displayCommand(name, !enabled)
    if (!command)
      return
    if (!DisplaysLogic.mayToggleDisplay({
      name: name,
      enable: !enabled,
      locked: root.displaysLocked,
      enabledMap: root.enabledDisplayMap,
      pendingMap: root.pendingDisplays
    }))
      return
    root.pendingDisplays = Object.assign({}, root.pendingDisplays, {
      [name]: !enabled
    })
    runDisplayCommand(name, !enabled, command)
  }

  // Starts COMMAND (DisplaysLogic.displayCommand) to enable or disable
  // display NAME.
  function runDisplayCommand(name, enable, command) {
    // A new request gets its own settle window (DisplaysLogic
    // .startDisplayRequest).
    var fresh = DisplaysLogic.startDisplayRequest({
      exits: root.displayExits,
      reads: root.displayReads
    }, name)
    root.displayExits = fresh.exits
    root.displayReads = fresh.reads
    root.actionRunning = {
      kind: "display",
      key: name,
      enable: enable
    }
    actionProc.command = command
    actionProc.running = true
  }

  // Applies scale to the display focused now (the one it was clicked on),
  // via omarchy-hyprland-monitor-scaling; refused with no focused display.
  // Shown chosen at once (pendingScale); a request while actionProc runs is
  // queued with its display, the last one winning (DisplaysLogic.takeQueued).
  function setScale(scale) {
    var monitor = root.focusedMonitor
    if (!scale || !monitor)
      return
    root.pendingScale = String(scale)
    var next = DisplaysLogic.takeQueued({
      running: actionProc.running,
      queued: String(scale)
    })
    root.queuedScale = next.queue
    root.queuedScaleMonitor = next.queue !== "" ? monitor : ""
    if (next.run !== "")
      runScaleCommand(monitor, next.run)
  }

  // Starts the scaling for SCALE on display MONITOR, which only runs while
  // MONITOR is still focused (DisplaysLogic.scaleCommand); a mismatch exits
  // non-zero, dropping the pending scale.
  function runScaleCommand(monitor, scale) {
    root.actionRunning = {
      kind: "scale",
      key: scale
    }
    actionProc.command = DisplaysLogic.scaleCommand(monitor, scale)
    actionProc.running = true
  }

  // actionProc exited with EXITCODE (DisplaysLogic.nextAction): a failure
  // drops its own pending state; a display command locks the switches
  // until a fresh read lands, drops any queued scale and always re-reads;
  // else the queued scale runs, or with nothing to run, the state is
  // re-read.
  function actionExited(exitCode) {
    var done = root.actionRunning
    root.actionRunning = null
    root.actionSerial++
    if (done && done.kind === "display") {
      root.displayExitSerial = root.actionSerial
      if (exitCode === 0)
        root.displayExits = Object.assign({}, root.displayExits, {
          [done.key]: root.actionSerial
        })
    }
    var next = DisplaysLogic.nextAction({
      done: done,
      exitCode: exitCode,
      queuedScale: root.queuedScale,
      queuedScaleMonitor: root.queuedScaleMonitor,
      pendingScale: root.pendingScale,
      pendingDisplays: root.pendingDisplays
    })
    root.queuedScale = next.queuedScale
    root.queuedScaleMonitor = next.queuedScaleMonitor
    root.pendingScale = next.pendingScale
    root.pendingDisplays = next.pendingDisplays
    if (next.run) {
      runScaleCommand(next.run.monitor, next.run.key)
      return
    }
    root.refresh()
  }

  // Settles the scale and display requests against a state read. A scale
  // the state now shows is dropped, and once the read started after the
  // last command exited with nothing left to run, the scale request is
  // (the real state shows). A display request stays until a read shows it,
  // or for at most 3 fresh reads (DisplaysLogic.settleDisplayPending).
  function settleActions() {
    root.pendingScale = DisplaysLogic.settlePending(root.pendingScale, root.selectedScaleKey)
    var displays = DisplaysLogic.settleDisplayPending({
      pending: root.pendingDisplays,
      exits: root.displayExits,
      reads: root.displayReads,
      enabledMap: root.enabledDisplayMap,
      readSerial: root.stateReadSerial
    })
    root.pendingDisplays = displays.pending
    root.displayExits = displays.exits
    root.displayReads = displays.reads
    var idle = !actionProc.running && root.queuedScale === ""
    if (idle && root.stateReadSerial === root.actionSerial)
      root.pendingScale = ""
  }

  // Whether another state read is due once one ends: the display lock waits
  // on a fresh read, a display request whose command exited waits for a
  // read to show it, or a scale request waits on a read started after its
  // command exited. Never while a command runs.
  function actionsAwaitRead() {
    if (actionProc.running)
      return false
    if (root.displaysLocked)
      return true
    var names = Object.keys(root.pendingDisplays)
    for (var i = 0; i < names.length; i++) {
      if (typeof root.displayExits[names[i]] === "number")
        return true
    }
    return root.stateReadSerial !== root.actionSerial && (root.pendingScale !== "" || names.length > 0)
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  // The index into textSizeStops nearest to px.
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) {
        bestDist = d
        best = i
      }
    }
    return best
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise whatever Style's live base-size rounds to.
  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  // px shown in the header: the pending stop if any, else the true base-size
  // (which may be an off-notch value set from the CLI).
  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  // Applies px via omarchy-display-text-size; a request while it runs is
  // queued, the last one winning.
  function setTextSize(px) {
    if (textScaleProc.running) {
      root.queuedTextPx = px
      return
    }
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    textScaleProc.running = true
  }

  // Moves the text-size stop by deltaSteps, previewing it at once while the
  // CLI round-trips. Nothing at either end.
  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0)
      idx = 0
    if (idx > textSizeStops.length - 1)
      idx = textSizeStops.length - 1
    if (idx === currentTextIndex())
      return
    requestTextStop(idx)
  }

  // Asks for text stop IDX: previews it at once (pulsing busy) and runs
  // the CLI; textPreviewTimeout drops the preview if the base size never
  // follows.
  function requestTextStop(idx) {
    markReflowing()
    textSizePreviewIndex = idx
    textPreviewTimeout.restart()
    setTextSize(textSizeStops[idx])
  }

  // The base size never followed a text-size request within 5 s: drops
  // the preview and any queued size, so the slider shows the real size.
  function textPreviewTimedOut() {
    root.textSizePreviewIndex = -1
    root.queuedTextPx = 0
  }

  // textScaleProc exited with EXITCODE: runs the queued size, else drops a
  // preview the CLI failed on or that Style already shows.
  function textScaleExited(exitCode) {
    if (root.queuedTextPx > 0) {
      var px = root.queuedTextPx
      root.queuedTextPx = 0
      setTextSize(px)
      return
    }
    if (exitCode !== 0 || (root.textSizePreviewIndex >= 0 && nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex))
      root.textSizePreviewIndex = -1
  }

  // ---- Night light ----
  // Reads `omarchy-toggle-nightlight --status` when it isn't already running.
  function readNight() {
    if (!nightProc.running)
      nightProc.running = true
  }

  // Applies a status read: shows it, settles a request it confirms, and
  // drops any request once the read started after the last toggle exited.
  function applyNight(text) {
    var state = DisplaysLogic.parseNightlight(text)
    root.nightAvailable = state.available
    root.nightOn = state.enabled
    root.nightTemperature = state.temperature
    root.nightCaption = DisplaysLogic.nightlightCaption(state)
    if (typeof root.nightPending !== "boolean" || nightToggleProc.running)
      return
    if (root.nightPending === root.nightOn || root.nightReadSerial === root.nightSerial)
      root.nightPending = null
  }

  // Flips the night light, only while its row shows: the state the toggle
  // will leave is shown at once (nightPending, pulsing busy). From a read
  // that is the script's own rule (DisplaysLogic.nightToggleTarget: an odd
  // temperature ends off); from a pending request, its opposite. A flip
  // while the toggle runs only changes what is asked for; the exit handler
  // toggles again if it still differs (the last one wins).
  function toggleNightlight() {
    if (visibleSections.indexOf("nightlight") < 0)
      return
    var target = typeof root.nightPending === "boolean" ? !root.nightPending : DisplaysLogic.nightToggleTarget({
      temperature: root.nightTemperature
    })
    root.nightPending = target
    if (nightToggleProc.running)
      return
    runNightToggle(target)
  }

  // Starts omarchy-toggle-nightlight, which will leave the light at TARGET.
  function runNightToggle(target) {
    root.nightTarget = target
    nightToggleProc.running = true
  }

  // nightToggleProc exited with EXITCODE: toggles again when the latest
  // request differs from what this toggle left; else a failure drops the
  // request, and the status is re-read either way.
  function nightExited(exitCode) {
    root.nightSerial++
    if (exitCode === 0 && typeof root.nightPending === "boolean" && root.nightPending !== root.nightTarget) {
      runNightToggle(root.nightPending)
      return
    }
    if (exitCode !== 0)
      root.nightPending = null
    readNight()
  }

  // ---- Keyboard light ----
  // Reads the keyboard light: finds the device once, then runs
  // `brightnessctl -d <device> -m` when it isn't already running.
  function readKbd() {
    if (!root.kbdDeviceChecked) {
      if (!kbdFindProc.running)
        kbdFindProc.running = true
      return
    }
    if (root.kbdDevice === "" || kbdProc.running)
      return
    kbdProc.command = ["brightnessctl", "-d", root.kbdDevice, "-m"]
    kbdProc.running = true
  }

  // Applies `ls /sys/class/leds`: caches the device and reads it.
  function applyKbdDevice(text) {
    root.kbdDevice = DisplaysLogic.kbdDevice(text)
    root.kbdDeviceChecked = true
    if (root.kbdDevice !== "")
      readKbd()
  }

  // Applies a brightnessctl read, settling requests as applyNight does.
  function applyKbd(text) {
    var state = DisplaysLogic.parseKbdLight(text)
    root.kbdValue = state.current
    root.kbdMax = state.max
    if (root.kbdPending < 0 || kbdSetProc.running || root.kbdQueued >= 0)
      return
    if (root.kbdPending === root.kbdValue || root.kbdReadSerial === root.kbdSerial)
      root.kbdPending = -1
  }

  // The keyboard light level shown: the pending request, else as read.
  function kbdShownLevel() {
    return root.kbdPending >= 0 ? root.kbdPending : root.kbdValue
  }

  // Sets the keyboard light to VALUE (clamped to 0..kbdMax), only while its
  // row shows: shown at once (kbdPending), queued behind a running set, the
  // last one winning.
  function setKbd(value) {
    if (root.kbdDevice === "" || root.kbdMax <= 0 || visibleSections.indexOf("kbdlight") < 0)
      return
    var level = Math.max(0, Math.min(root.kbdMax, Math.round(Number(value) || 0)))
    if (level === kbdShownLevel())
      return
    root.kbdPending = level
    if (kbdSetProc.running) {
      root.kbdQueued = level
      return
    }
    runKbdCommand(level)
  }

  // Starts the keyboard light command for LEVEL (DisplaysLogic.kbdCommand).
  function runKbdCommand(level) {
    kbdSetProc.command = DisplaysLogic.kbdCommand(root.kbdDevice, level, root.kbdMax)
    kbdSetProc.running = true
  }

  // kbdSetProc exited with EXITCODE: runs the queued level, else a failure
  // drops the request, and the level is re-read either way.
  function kbdExited(exitCode) {
    root.kbdSerial++
    if (root.kbdQueued >= 0) {
      var level = root.kbdQueued
      root.kbdQueued = -1
      runKbdCommand(level)
      return
    }
    if (exitCode !== 0)
      root.kbdPending = -1
    readKbd()
  }

  // ---- The view's actions ----
  // Whether a keyed pointer action ARG ({index, key}) still names the row
  // of SECTION it was reported for (CursorLogic.rowKeyMatches).
  function pointerRowMatches(section, arg) {
    return !!arg && CursorLogic.rowKeyMatches(sectionRows(section), arg.index, arg.key)
  }

  // Carries out one DisplaysDropdown action. Pointer actions hand the
  // cursor back from the keyboard; a keyed action whose row changed under
  // it is refused; a hover moves the cursor (never during a text-size
  // reflow); the rest map onto the setters above.
  function handleAction(name, arg) {
    keyboardCursor = false
    if (name === "brightnessPreview") {
      if (brightnessAvailable && arg)
        previewBrightness(arg.value)
    } else if (name === "brightnessCommit") {
      if (brightnessAvailable && arg) {
        brightnessDebounce.stop()
        setBrightness(arg.value)
      }
    } else if (name === "nightlight") {
      if (pointerRowMatches("nightlight", arg))
        toggleNightlight()
    } else if (name === "kbd") {
      if (pointerRowMatches("kbdlight", arg))
        setKbd(arg.value)
    } else if (name === "textSize") {
      // The key is the stop in px, a number: checked against the stops.
      if (arg && arg.index >= 0 && arg.index < textSizeStops.length && textSizeStops[arg.index] === arg.key)
        requestTextStop(arg.index)
    } else if (name === "scale") {
      if (pointerRowMatches("scale", arg))
        setScale(arg.key)
    } else if (name === "display") {
      if (pointerRowMatches("monitors", arg) && typeof arg.enable === "boolean" && arg.enable !== displayShownOn(arg.key))
        toggleDisplay(arg.key, !arg.enable)
    } else if (name === "hover") {
      if (reflowingText || !arg || visibleSections.indexOf(arg.section) < 0 || !pointerRowMatches(arg.section, arg))
        return
      cursorActive = true
      focusSection = arg.section
      selectedIndex = arg.index
      cursorKey = arg.key
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with the arrows ready to navigate. Keep a default landing point, but
  // don't paint the cursor until the first navigation key; a fresh open
  // chooses nothing, so Enter is refused until a move, adjustment or hover.
  onOpenedChanged: {
    keyboardCursor = false
    cursorKey = ""
    if (opened) {
      // Lock the display switches until a read started since now lands.
      openReadMark = stateReadCount
      refresh()
      if (brightnessAvailable) {
        focusSection = "brightness"
        selectedIndex = 0
      } else {
        focusSection = "scale"
        selectedIndex = sectionLanding("scale")
      }
      cursorActive = false
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Only poll while the panel is open; the bar glyph tracks monitor count via
  // Quickshell.screens, and open-time refresh + Component.onCompleted cover the
  // rest. External brightness changes are reflected whenever the panel is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // omarchy-monitor-state. Each read records which action exit it started
  // after, and a read that started too early for a waiting request is
  // followed by another.
  Process {
    id: stateProc
    command: ["omarchy-monitor-state"]
    onRunningChanged: {
      if (stateProc.running) {
        root.stateReadSerial = root.actionSerial
        root.stateReadCount++
        root.stateReadId = root.stateReadCount
      } else if (root.actionsAwaitRead())
        Qt.callLater(root.refresh)
    }
    stdout: StdioCollector {
      id: stateOut
      waitForEnd: true
      onStreamFinished: {
        var lines = String(stateOut.text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        root.internalMonitor = String(lines[1] || "").trim()
        root.externalMonitor = String(lines[2] || "").trim()
        root.internalEnabled = String(lines[3] || "").trim() !== ""
        root.mirrorEnabled = String(lines[4] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[5] || "").trim()
        root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
        root.updateDisplays(String(lines[7] || "[]").trim())
        root.stateLandedSerial = root.stateReadSerial
        root.stateLandedRead = root.stateReadId
        root.settleActions()
      }
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector {
      waitForEnd: true
    }
    // Do NOT call refresh() after a brightness set completes. The local
    // brightnessPercent we just wrote is authoritative; re-reading via
    // `omarchy-brightness-display` races the hardware/driver and can
    // return an empty string, which the parser then coerces to 0,
    // visible as a "bounce to zero" after left/right keypresses. External
    // brightness changes are still picked up by the 5s periodic refresh,
    // the open-time refresh, and Component.onCompleted.
    onRunningChanged: {
      if (setBrightnessProc.running)
        return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  // The exited handlers below only name exitCode, which qmllint still
  // can't type (QProcess::ExitStatus).
  // qmllint disable signal-handler-parameters
  // Stock's scale and display setter; actionExited runs the queue and
  // re-reads.
  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
    }
    onExited: function (exitCode) {
      root.actionExited(exitCode)
    }
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector {
      waitForEnd: true
    }
    onExited: function (exitCode) {
      root.textScaleExited(exitCode)
    }
  }

  // omarchy-toggle-nightlight (no arguments: it flips the light).
  Process {
    id: nightToggleProc
    command: ["omarchy-toggle-nightlight"]
    onExited: function (exitCode) {
      root.nightExited(exitCode)
    }
  }

  // The keyboard light setter (runKbdCommand sets the command).
  Process {
    id: kbdSetProc
    onExited: function (exitCode) {
      root.kbdExited(exitCode)
    }
  }
  // qmllint enable signal-handler-parameters

  // The night light status read; records which toggle exit it started
  // after, as stateProc does.
  Process {
    id: nightProc
    command: ["omarchy-toggle-nightlight", "--status"]
    onRunningChanged: {
      if (nightProc.running)
        root.nightReadSerial = root.nightSerial
      else if (typeof root.nightPending === "boolean" && !nightToggleProc.running && root.nightReadSerial !== root.nightSerial)
        Qt.callLater(root.readNight)
    }
    stdout: StdioCollector {
      id: nightOut
      waitForEnd: true
      onStreamFinished: root.applyNight(nightOut.text)
    }
  }

  // `ls /sys/class/leds`, once, for the keyboard backlight device.
  Process {
    id: kbdFindProc
    command: ["ls", "/sys/class/leds"]
    stdout: StdioCollector {
      id: kbdFindOut
      waitForEnd: true
      onStreamFinished: root.applyKbdDevice(kbdFindOut.text)
    }
  }

  // The keyboard light read (readKbd sets the command); records which set
  // exit it started after, as stateProc does.
  Process {
    id: kbdProc
    onRunningChanged: {
      if (kbdProc.running)
        root.kbdReadSerial = root.kbdSerial
      else if (root.kbdPending >= 0 && !kbdSetProc.running && root.kbdReadSerial !== root.kbdSerial)
        Qt.callLater(root.readKbd)
    }
    stdout: StdioCollector {
      id: kbdOut
      waitForEnd: true
      onStreamFinished: root.applyKbd(kbdOut.text)
    }
  }

  // Drops a text-size preview the base size never followed (see
  // textPreviewTimedOut).
  Timer {
    id: textPreviewTimeout
    interval: 5000
    repeat: false
    onTriggered: if (root.textSizePreviewIndex >= 0)
      root.textPreviewTimedOut()
  }

  // Clears the hover-suppression flag once the reflow triggered by a text-size
  // change has settled.
  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once Style's base-size catches up to the pending choice, drop the preview
  // so the slider tracks the live value again. The change itself reflows the
  // panel, so suppress hover for a beat while it lands.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0 && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(Quickshell.screens.length > 1 ? 0xf037a : 0xf0379)
    onPressed: function (b) {
      root.toggle()
    }
    onWheelMoved: function (delta) {
      if (!root.brightnessAvailable)
        return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0)
        return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }

  // The Aranea view in the shared keyboard frame, sized to the view.
  Aranea.KeyboardPanelFrame {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(dropdown.implicitHeight)
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      dropdown.disarmPointer()
      root.keyboardCursor = true
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      dropdown.disarmPointer()
      // The first key after opening or after mouse use only reveals the
      // cursor where it is; a reveal never chooses or adjusts.
      var revealing = !root.cursorActive || !root.keyboardCursor
      root.cursorActive = true
      root.keyboardCursor = true
      if (revealing)
        return
      if (dy !== 0) {
        root.moveCursor(dy)
        return
      }
      if (dx === 0)
        return
      if (root.focusSection === "brightness")
        root.adjustBrightness(dx * 5)
      else if (root.focusSection === "kbdlight")
        root.adjustKbd(dx)
      else if (root.focusSection === "textsize")
        root.adjustTextSize(dx)
      else if (root.focusSection === "scale") {
        root.moveCursorH(dx)
        return
      }
      // An adjustment is a deliberate choice of the control it lands on.
      root.cursorKey = root.keyAt(root.focusSection, root.selectedIndex)
    }
    // Enter acts only on a cursor the keyboard is showing, on the row the
    // user chose and still sees (CursorLogic.pressIntent, cursorConfirmed);
    // a pointer-placed cursor is only revealed.
    onActivateRequested: {
      dropdown.disarmPointer()
      var intent = CursorLogic.pressIntent(root.cursorActive, root.keyboardCursor)
      if (intent === "ignore")
        return
      root.keyboardCursor = true
      if (intent === "act")
        root.activateCursor()
    }
    onDeleteRequested: {
      dropdown.disarmPointer()
      root.keyboardCursor = true
    }
    onTextKey: function (t) {
      dropdown.disarmPointer()
      root.keyboardCursor = true
    }

    Item {
      anchors.fill: parent
      clip: true

      DisplaysDropdown {
        id: dropdown
        width: parent.width
        view: root.displaysView
        brightnessPercent: root.brightnessPercent
        brightnessBusy: setBrightnessProc.running || root.brightnessSetQueued
        reflowing: root.reflowingText
        nightlightOn: root.nightOn
        nightlightCaption: root.nightCaption
        nightlightPending: root.nightPending
        kbdValue: root.kbdValue
        kbdPending: root.kbdPending
        textIndex: root.currentTextIndex()
        textPending: root.textSizePreviewIndex >= 0
        selectedScale: root.selectedScaleKey
        pendingScale: root.pendingScale
        enabledDisplays: root.enabledDisplayMap
        pendingDisplays: root.pendingDisplays
        lastEnabled: root.lastEnabled
        displaysLocked: root.displaysLocked
        onAction: function (name, arg) {
          root.handleAction(name, arg)
        }
      }
    }
  }
}
