// Aranea Power (araneadev.power, cloned from omarchy.power): the bar
// battery icon and its dropdown. Stock's root logic stays (battery and
// profile polling, the power profile picker, the rotating hero status
// phrases, the percentage setting and IPC), minus the system stats poll.
// Added here: the charge history (UPower GetHistory over busctl, on open
// and every 60 s while open), the live power draw (EnergyRate every 1.5 s
// while open) and the keyed keyboard cursor. The pure view, PowerDropdown,
// draws it in the shared keyboard frame. The rules are PowerLogic.js /
// Model.js / CursorLogic.js functions, tested under Node.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "PowerLogic.js" as PowerLogic
import "../araneadev.shared/CursorLogic.js" as CursorLogic
import "../araneadev.shared/GraphLogic.js" as GraphLogic
import "../araneadev.shared" as Aranea

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits, needed for the togglePercentage method below.
  manageIpc: false
  // The parsed `omarchy-battery-status --shell` fields (percentage, time,
  // rate, size, cycles, threshold), or {} before the first poll.
  property var batteryInfo: ({})
  // The power profile names from `omarchy-powerprofiles-list`, in order.
  property var profiles: []
  // The currently active power profile's name.
  property string activeProfile: ""
  // Index into profiles for keyboard navigation.
  property int profileIndex: 0
  // Whether keyboard/mouse navigation has placed a cursor on a profile yet.
  property bool cursorActive: false
  // True while the keyboard drives the cursor; any pointer action clears it.
  // The view outlines the cursor only then, so the mouse never shows one.
  property bool keyboardCursor: false
  // The profile the cursor was deliberately put on (a move or a keyboard
  // reveal; never an open or a hover), so the cursor follows that
  // profile when the list changes. "" until the user picks one, and
  // dropped when it's gone, so Enter refuses (CursorLogic.followCursor).
  property string profileKey: ""
  // A profile requested (by click or Enter) but not yet confirmed by a
  // profiles refresh; "" for none. Shown chosen and pulsing busy at once,
  // so a click never looks like it did nothing while
  // omarchy-powerprofiles-set runs (PowerLogic.selectedProfile /
  // settlePending).
  property string pendingProfile: ""
  // The latest profile requested while actionProc was already running, run
  // when it exits (the last click wins instead of being dropped); "" when
  // nothing is queued.
  property string queuedProfile: ""
  // The key the profile pills show chosen: pendingProfile once set, else
  // activeProfile (PowerLogic.selectedProfile).
  readonly property string selectedProfile: PowerLogic.selectedProfile(pendingProfile, activeProfile)
  // Whether the bar icon shows the battery percentage beside its glyph.
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  // Whether UPower reports a present, usable battery device.
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  // UPowerDeviceState values as a plain object, so Model.js helpers stay
  // pure JS and Node-testable.
  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  // Moves the profile picker cursor by delta, clamped to profiles, and
  // chooses the profile it lands on.
  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
    profileKey = profileIndex < profiles.length ? String(profiles[profileIndex]) : ""
  }

  // Shows the keyboard cursor where it is, on the profile it sits on: the
  // outline marks Enter's target, so the revealed profile is the one Enter
  // then applies.
  function revealCursor() {
    cursorActive = true
    keyboardCursor = true
    profileKey = profileIndex >= 0 && profileIndex < profiles.length ? String(profiles[profileIndex]) : ""
  }

  // Applies the profile under the keyboard cursor, only when it is still
  // the one the user chose (CursorLogic.cursorConfirmed).
  function activateSelectedProfile() {
    if (!CursorLogic.cursorConfirmed(profileKeyRows(), profileKey, profileIndex))
      return
    setProfile(profileKey)
  }

  // The bar icon's battery glyph, delegating to Model.js.
  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  // The fallback hero status label (used when there is no rotating phrase),
  // delegating to Model.js.
  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  // Display glyph for a power profile name, delegating to Model.js.
  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  // Whether the battery is fully charged (and no charge threshold is
  // holding it just under 100%).
  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  // Whether the device is running on battery (not AC).
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  // Whether a charge-control threshold is holding the battery below 100%.
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  // Whether the battery reads as full, by state or by fraction.
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  // Whether the battery's charge flow is effectively idle (full or held by
  // a threshold), so "time left"/"time to full" has nothing to report.
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, for the hero's battery cell.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  // Whether current is actively flowing into the battery right now.
  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: ["Pumping power", "Injecting electrons", "Pouring juice", "Amassing watts", "Hoarding joules", "Sucking volts", "Topping reserves", "Soaking amps", "Inhaling kilowatts"]
  // Phrases shown instead while discharging.
  readonly property var onBatteryPhrases: ["Slurping power", "Spending joules", "Draining watts", "Burning electrons", "Sipping juice", "Spending coulombs", "Bleeding amps", "Guzzling volts", "Munching reserves"]
  // Index into activePhrases for the rotating status phrase.
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged)
      return []
    if (charging)
      return chargingPhrases
    if (discharging)
      return onBatteryPhrases
    return []
  }
  // Whether there is an active phrase list to rotate through.
  readonly property bool rotatingPhrases: activePhrases.length > 0

  // The hero status line's text, before case transform
  // (PowerLogic.heroStatus, stock's rule).
  readonly property string heroStatusText: PowerLogic.heroStatus({
    fullyCharged: fullyCharged
  }, activePhrases, phraseIndex, modeLabel())

  // ---------- Aranea additions: history, draw, view ----------

  // The hero status line's opacity, which phraseSwap fades between phrases.
  // Passed to the view on its own, outside powerView, so the fade never
  // rebuilds the view object.
  property real statusOpacity: 1
  // The UPower battery object path from `upower -e`
  // (PowerLogic.batteryPath), read once; "" until then or with none.
  property string batteryPath: ""
  // Charge history samples, oldest first (PowerLogic.parseHistory); [] when
  // the history is empty or busctl failed, which hides the section.
  property var historySamples: []
  // When the history was last read (epoch seconds): the right edge of its
  // 24 h window.
  property real historyNowSec: 0
  // Power draw samples for the trace, oldest first: [{iface, rx: watts,
  // tx: 0}] (GraphLogic.pushSample, 40 kept). Cleared on close.
  property var drawSamples: []
  // Row arrays kept by CursorLogic.keepRows, so an unchanged refresh hands
  // the view the same array and its Repeaters keep their delegates.
  property var rowCache: ({})
  // Whether the live draw section applies: current is flowing either way.
  readonly property bool drawFlowing: (discharging || charging) && !batteryFlowIdle
  // The current charge in percent, for the history summary and its dot.
  readonly property real nowPercent: Math.round(batteryFraction * 100)

  // Clears the draw trace on a drawFlowing rising edge (idle to flowing),
  // so an old trace from before a stretch of being idle never joins a new
  // one.
  onDrawFlowingChanged: if (root.drawFlowing)
    root.drawSamples = []

  // The profiles as keyed rows ({key: name}) for CursorLogic.
  function profileKeyRows() {
    return profiles.map(function (name) {
      return {
        key: String(name)
      }
    })
  }

  // The profile pills: one per profile, keyed by its name. Carries no
  // selected flag, so which one is chosen never changes this array and
  // CursorLogic.keepRows keeps handing back the same one: the Repeater's
  // delegates survive a selection change exactly as they survive phrase,
  // rate and history updates. Which pill shows chosen comes from
  // selectedProfile instead (PowerDropdown reads it separately).
  readonly property var profileRows: CursorLogic.keepRows(rowCache, "profiles", profiles.map(function (name) {
    var key = String(name)
    return {
      key: key,
      label: key.charAt(0).toUpperCase() + key.slice(1),
      glyph: root.profileIcon(key)
    }
  }))

  // The details grid's pairs (PowerLogic.detailRows, stock's rules), shown
  // once battery data has ever loaded, as stock's stats row.
  readonly property var detailRows: CursorLogic.keepRows(rowCache, "details", batteryInfo.percentage !== undefined ? PowerLogic.detailRows(batteryInfo, {
    thresholdActive: chargeThresholdActive,
    discharging: discharging,
    flowIdle: batteryFlowIdle,
    full: batteryFull
  }) : [])

  // The big percentage: stock's battery-status percentage without its "%",
  // else UPower's.
  readonly property string heroPercent: {
    var text = String(batteryInfo.percentage || "").replace(/%\s*$/, "")
    return text !== "" ? text : String(nowPercent)
  }

  // The history chart's window start (PowerLogic.historyWindowStart): the
  // first sample's time when the history is shorter than 24h (at least 1h),
  // else the usual 24h-ago mark; `nowSec-86400` before the first read.
  readonly property real historyWindowStart: historyNowSec > 0 ? PowerLogic.historyWindowStart(historySamples, historyNowSec) : 0

  // The view object PowerDropdown draws (its documented shape). Fast
  // changers (the status fade, history segments, draw samples) are separate.
  readonly property var powerView: ({
      hero: batteryPresent ? {
        fraction: batteryFraction,
        status: heroStatusText,
        percent: heroPercent
      } : null,
      details: detailRows,
      history: {
        visible: historySamples.length > 0,
        summary: PowerLogic.historySummary(historySamples, nowPercent),
        startLabel: historyNowSec > 0 ? PowerLogic.timeLabel(historyWindowStart, historyNowSec) : ""
      },
      draw: {
        visible: drawFlowing,
        caption: drawSamples.length > 0 ? Number(drawSamples[drawSamples.length - 1].rx).toFixed(1) + " W" : ""
      },
      profiles: profileRows,
      selectedProfile: selectedProfile,
      pendingProfile: pendingProfile,
      cursor: {
        active: cursorActive && keyboardCursor,
        section: "profiles",
        index: profileIndex
      },
      keyHint: PowerLogic.keyHint(profileRows.length > 0 ? "profiles" : "")
    })

  // The history's polyline segments in unit coordinates
  // (PowerLogic.historyPoints); the view scales them.
  readonly property var historySegments: PowerLogic.historyPoints(historySamples, historyNowSec, 1, 1, historyWindowStart)

  // Starts the battery and profiles processes when a battery is present
  // and they aren't already running.
  function refresh() {
    if (!batteryPresent)
      return
    if (!batteryProc.running)
      batteryProc.running = true
    if (!profilesProc.running)
      profilesProc.running = true
  }

  // Parses a tab-separated key/value process reply into batteryInfo,
  // keeping the last known good data on an empty reply.
  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing; happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0)
      return
    if (targetName === "battery")
      batteryInfo = next
  }

  // Parses the power-profiles-list reply into profiles/activeProfile/
  // profileIndex, keeping the cursor on the active profile while the panel
  // is open and the user hasn't moved it, and on the profile the user
  // chose when the list changes (CursorLogic.followCursor).
  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0)
      return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    pendingProfile = PowerLogic.settlePending(pendingProfile, activeProfile)
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0)
        profileIndex = idx
    }
    if (profileKey !== "") {
      var next = CursorLogic.followCursor(profileKeyRows(), profileKey, profileIndex)
      profileIndex = Math.max(0, next.index)
      profileKey = next.key
    }
  }

  // Sets the active power profile via omarchy-powerprofiles-set. Shown
  // chosen (pendingProfile) at once rather than waiting for the command to
  // finish and the profile list to be re-read. A request while one is
  // already running is queued instead of dropped, the latest replacing any
  // earlier one, and runs the moment the current one exits (the last click
  // wins); see actionProc.onExited.
  function setProfile(profile) {
    if (!profile)
      return
    pendingProfile = profile
    if (actionProc.running) {
      queuedProfile = profile
      return
    }
    runProfileCommand(profile)
  }

  // Starts omarchy-powerprofiles-set for PROFILE.
  function runProfileCommand(profile) {
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  // Flips showPercentage and persists it to the bar entry's inline settings.
  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, {
      showPercentage: !root.showPercentage
    })
    // qmllint disable missing-property
    if (root.bar && root.bar.shell)
      root.bar.shell.updateEntryInline(root.moduleName, root.settings)
    // qmllint enable missing-property
  }

  // Reads the charge history: finds the battery's object path once, then
  // asks UPower for the last 24 h. Only while open.
  function fetchHistory() {
    if (!opened)
      return
    if (batteryPath === "") {
      if (!pathProc.running)
        pathProc.running = true
      return
    }
    if (historyProc.running)
      return
    historyProc.command = ["busctl", "--json=short", "call", "org.freedesktop.UPower", batteryPath, "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", "86400", "200"]
    historyProc.running = true
  }

  // Applies `upower -e`'s reply: caches the battery path and, when there is
  // one, reads the history.
  function applyBatteryPath(text) {
    batteryPath = PowerLogic.batteryPath(text)
    if (batteryPath !== "")
      fetchHistory()
  }

  // Applies a GetHistory reply; a failure or an empty history hides the
  // section. Ignored once closed.
  function applyHistory(text) {
    if (!opened)
      return
    historyNowSec = Date.now() / 1000
    historySamples = PowerLogic.parseHistory(text)
  }

  // Asks UPower for the current EnergyRate. Only while open.
  function fetchRate() {
    if (!opened || batteryPath === "" || rateProc.running)
      return
    rateProc.command = ["busctl", "--json=short", "get-property", "org.freedesktop.UPower", batteryPath, "org.freedesktop.UPower.Device", "EnergyRate"]
    rateProc.running = true
  }

  // Records one draw sample (watts) from an EnergyRate reply, keeping 40.
  // Ignored once closed, so a late reply never refills a cleared trace.
  function applyRate(text) {
    if (!opened)
      return
    drawSamples = GraphLogic.pushSample(drawSamples, {
      iface: "battery",
      rx: PowerLogic.parseEnergyRate(text),
      tx: 0
    }, 40)
  }

  // Whether a pointer action ARG ({index, key}) still names the profile it
  // was reported for (CursorLogic.rowKeyMatches).
  function pointerRowMatches(arg) {
    return !!arg && CursorLogic.rowKeyMatches(profileRows, arg.index, arg.key)
  }

  // Carries out one PowerDropdown action. A click hands the cursor back
  // from the keyboard and sets the profile it was reported for, or nothing
  // when the pill changed underneath it. A hover is only the pill's own
  // fill: it never moves the cursor or hides the outline.
  function handleAction(name, arg) {
    if (name === "hover")
      return
    keyboardCursor = false
    if (!pointerRowMatches(arg))
      return
    if (name === "setProfile")
      setProfile(arg.key)
  }

  IpcHandler {
    target: "omarchy.power"

    function open() {
      root.open()
    }
    function close() {
      root.close()
    }
    function show() {
      root.open()
    }
    function hide() {
      root.close()
    }
    function toggle() {
      root.toggle()
    }
    function togglePercentage() {
      root.togglePercentage()
    }
  }

  onOpenedChanged: {
    // A fresh open starts with the outline hidden and chooses nothing: the
    // first key (Enter included) reveals the cursor on the active profile.
    keyboardCursor = false
    profileKey = ""
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
      fetchHistory()
      if (drawFlowing)
        fetchRate()
    } else {
      drawSamples = []
      historySamples = []
      historyNowSec = 0
    }
  }

  onBatteryPresentChanged: if (!batteryPresent)
    close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector {
      id: batteryOut
      waitForEnd: true
      onStreamFinished: root.updateKeyValue(batteryOut.text, "battery")
    }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      id: profilesOut
      waitForEnd: true
      onStreamFinished: root.updateProfiles(profilesOut.text)
    }
  }

  // Stock's profile setter. A queued request (setProfile, while this was
  // already running) runs immediately, before refreshing; otherwise a
  // failed set drops pendingProfile right away, so the real (unchanged)
  // profile shows rather than a pill stuck pulsing busy, and either way a
  // refresh re-reads the list. Its exited handler only names exitCode,
  // which qmllint still can't type (QProcess::ExitStatus).
  // qmllint disable signal-handler-parameters
  Process {
    id: actionProc
    onExited: function (exitCode) {
      if (root.queuedProfile !== "") {
        var next = root.queuedProfile
        root.queuedProfile = ""
        root.runProfileCommand(next)
        return
      }
      if (exitCode !== 0)
        root.pendingProfile = ""
      root.refresh()
    }
  }
  // qmllint enable signal-handler-parameters

  // `upower -e`, once, for the battery's object path.
  Process {
    id: pathProc
    command: ["upower", "-e"]
    stdout: StdioCollector {
      id: pathOut
      waitForEnd: true
      onStreamFinished: root.applyBatteryPath(pathOut.text)
    }
  }

  // The charge history read (fetchHistory sets the command).
  Process {
    id: historyProc
    stdout: StdioCollector {
      id: historyOut
      waitForEnd: true
      onStreamFinished: root.applyHistory(historyOut.text)
    }
  }

  // The EnergyRate read (fetchRate sets the command).
  Process {
    id: rateProc
    stdout: StdioCollector {
      id: rateOut
      waitForEnd: true
      onStreamFinished: root.applyRate(rateOut.text)
    }
  }

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // The charge history, re-read every 60 s while open.
  Timer {
    interval: 60000
    running: root.opened
    repeat: true
    onTriggered: root.fetchHistory()
  }

  // The live draw, sampled every 1.5 s while open and while the draw
  // section is shown (current flowing either way, the same condition the
  // view uses to show it): never while on AC and full.
  Timer {
    interval: 1500
    running: root.opened && root.drawFlowing
    repeat: true
    onTriggered: root.fetchRate()
  }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: root
      property: "statusOpacity"
      to: 0.0
      duration: 180
      easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0)
          root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: root
      property: "statusOpacity"
      to: 1.0
      duration: 260
      easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        root.statusOpacity = 1.0
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon() : root.batteryIcon()
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function (b) {
      if (!root.batteryPresent)
        return
      if (b === Qt.RightButton)
        root.togglePercentage()
      else
        root.toggle()
    }
  }

  // The Aranea view in the shared keyboard frame, sized to the view.
  Aranea.KeyboardPanelFrame {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
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
      // cursor where it is.
      if (!root.cursorActive || !root.keyboardCursor) {
        root.revealCursor()
        return
      }
      if (dx !== 0)
        root.selectProfileByDelta(dx)
      else if (dy !== 0)
        root.selectProfileByDelta(dy)
    }
    // Enter, like any first key, only reveals a hidden cursor; it acts only
    // on a cursor the keyboard is showing, on the profile the user chose
    // and still sees (CursorLogic.pressIntent, cursorConfirmed).
    onActivateRequested: {
      dropdown.disarmPointer()
      if (CursorLogic.pressIntent(root.cursorActive, root.keyboardCursor) === "act")
        root.activateSelectedProfile()
      else
        root.revealCursor()
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

      PowerDropdown {
        id: dropdown
        width: parent.width
        view: root.powerView
        statusOpacity: root.statusOpacity
        historySegments: root.historySegments
        drawSamples: root.drawSamples
        nowPercent: root.nowPercent
        onAction: function (name, arg) {
          root.handleAction(name, arg)
        }
      }
    }
  }
}
