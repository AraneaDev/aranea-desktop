// Aranea Power (araneadev.power, cloned from omarchy.power): the bar
// battery icon and its dropdown. Stock logic (battery/system stats polling,
// the power profile picker, the rotating hero status phrases and IPC) and
// the stock view are unchanged for now.
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  // Stock code, unqualified by design (qmllint cannot type `bar`, the
  // generic Process exit handler, or the delegate-scoped Repeater member
  // further down): a temporary region, deleted once Task 4 replaces the
  // view below with the Aranea one.
  // qmllint disable missing-property unqualified signal-handler-parameters
  // The parsed `omarchy-battery-status --shell` fields (percentage, time,
  // rate, size, cycles, threshold), or {} before the first poll.
  property var batteryInfo: ({})
  // The parsed `omarchy-system-stats` fields, or {} before the first poll.
  property var systemInfo: ({})
  // The power profile names from `omarchy-powerprofiles-list`, in order.
  property var profiles: []
  // The currently active power profile's name.
  property string activeProfile: ""
  // Index into profiles for keyboard navigation.
  property int profileIndex: 0
  // Whether keyboard/mouse navigation has placed a cursor on a profile yet.
  property bool cursorActive: false
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

  // Moves the profile picker cursor by delta, clamped to profiles.
  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  // Applies the profile under the keyboard cursor.
  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length)
      return
    setProfile(profiles[profileIndex])
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

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  // Whether current is actively flowing into the battery right now.
  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  // Fill color for the battery progress bar, falling back to Color.foreground
  // when there is no bar yet (the smoke test instantiates the panel without
  // one).
  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Color.foreground
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

  // The hero status line's text, before case transform.
  readonly property string heroStatusText: {
    if (fullyCharged)
      return "Fully charged"
    if (rotatingPhrases)
      return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  // Starts the battery, profiles and system-stats processes when a battery
  // is present and they aren't already running.
  function refresh() {
    if (!batteryPresent)
      return
    if (!batteryProc.running)
      batteryProc.running = true
    if (!profilesProc.running)
      profilesProc.running = true
    if (!systemProc.running)
      systemProc.running = true
  }

  // Parses a tab-separated key/value process reply into batteryInfo or
  // systemInfo, keeping the last known good data on an empty reply.
  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0)
      return
    if (targetName === "battery")
      batteryInfo = next
    else
      systemInfo = next
  }

  // Parses the power-profiles-list reply into profiles/activeProfile/
  // profileIndex, keeping the cursor on the active profile while the panel
  // is open and the user hasn't moved it.
  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0)
      return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0)
        profileIndex = idx
    }
  }

  // Sets the active power profile via omarchy-powerprofiles-set.
  function setProfile(profile) {
    if (!profile || actionProc.running)
      return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  // Flips showPercentage and persists it to the bar entry's inline settings.
  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, {
      showPercentage: !root.showPercentage
    })
    if (root.bar && root.bar.shell)
      root.bar.shell.updateEntryInline(root.moduleName, root.settings)
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
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent)
    close()

  // Smoke-safe accessors: the popup content below is created eagerly at
  // component completion (not deferred until the panel opens), and some
  // runtime contexts (this project's smoke test) instantiate the panel
  // with no bar at all.
  readonly property color safeForeground: bar ? bar.foreground : Color.foreground
  // See safeForeground.
  readonly property string safeFontFamily: bar ? bar.fontFamily : Style.font.family

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateKeyValue(text, "battery")
    }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateProfiles(text)
    }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateKeyValue(text, "system")
    }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
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
      target: heroStatus
      property: "opacity"
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
      target: heroStatus
      property: "opacity"
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
        heroStatus.opacity = 1.0
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

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dx !== 0)
          root.selectProfileByDelta(dx)
        else if (dy !== 0)
          root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive)
        root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function (direction) {
        root.switchPanel(direction)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.safeForeground
            font.family: root.safeFontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
              ColorAnimation {
                duration: 200
              }
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.safeForeground
              font.family: root.safeFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.safeForeground, 1.4)
              font.family: root.safeFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.batteryInfo.percentage || "—"
            color: root.safeForeground
            font.family: root.safeFontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
              ColorAnimation {
                duration: 200
              }
            }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.safeForeground.r, root.safeForeground.g, root.safeForeground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width {
              NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
              }
            }
            Behavior on color {
              ColorAnimation {
                duration: 220
              }
            }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation {
                from: 1.0
                to: 0.55
                duration: 950
                easing.type: Easing.InOutSine
              }
              NumberAnimation {
                from: 0.55
                to: 1.0
                duration: 950
                easing.type: Easing.InOutSine
              }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: "Battery size"
              value: root.batteryInfo.size || ""
            }
            InfoPair {
              label: "Charge cycles"
              value: root.batteryInfo.cycles || "—"
            }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.safeForeground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.safeForeground
            fontFamily: root.safeFontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0 ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.safeForeground
                fontFamily: root.safeFontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function (h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel {
      text: label
    }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue {
      text: value
    }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.safeForeground
    opacity: 0.6
    font.family: root.safeFontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.safeForeground
    font.family: root.safeFontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
