// Aranea Bluetooth (araneadev.bluetooth, cloned from omarchy.bluetooth): the
// bar Bluetooth icon and its dropdown. Stock logic (discovery, pending
// actions, the audio hand-off, the cursor model and IPC); the Aranea view,
// BluetoothDropdown, replaces the stock one.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "BluetoothLogic.js" as BluetoothLogic
import "../araneadev.shared/ShowcaseLogic.js" as Showcase
import "../araneadev.shared" as Aranea

Panel {
  id: root
  moduleName: "omarchy.bluetooth"
  ipcTarget: "omarchy.bluetooth"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the toggleBluetooth method below.
  manageIpc: false

  // Address -> "connecting" | "disconnecting" | "forgetting".
  // The actual Bluetooth sequencing lives in bin/omarchy-bluetooth-device;
  // this map only keeps the panel responsive while BlueZ catches up.
  property var pendingActions: ({})
  // Address -> the action ("connect", "disconnect" or "forget") asked for
  // while that device was busy, run once it goes idle; the last one wins
  // (BluetoothLogic.deviceClick / takeReady).
  property var deviceQueue: ({})
  // Addresses whose "connecting" entry has seen BlueZ's connecting state,
  // so a fall back to disconnected ends it (BluetoothLogic.settleConnecting).
  property var connectingSeen: ({})
  // The pending power change (BluetoothLogic.powerClick / powerEcho): the
  // switch shows the new state at once and pulses until BlueZ's Powered
  // echoes it; clicks while it waits are queued, the last one wins.
  property var powerPending: BluetoothLogic.powerIdle()
  // The address a keyboard Forget is removing (deleteSelected arms it), read
  // by BluetoothLogic.followForget so the cursor lands on the neighbour once
  // the device leaves the remembered lists; "" for none.
  property string pendingRemovalKey: ""
  // The forgotten row's last stop index (BluetoothLogic.forgetStops).
  property int pendingRemovalIndex: -1

  // The default Bluetooth adapter, or null when none.
  // qmllint disable unresolved-type
  readonly property var adapter: Bluetooth.defaultAdapter
  // qmllint enable unresolved-type

  // True while this instance owes BlueZ a StopDiscovery: set when it starts
  // discovery (or opens onto a session already running) and cleared once
  // discovery is confirmed down after close. Ownership, not state — BlueZ's
  // Discovering property also reflects sessions other clients hold, which are
  // never this panel's to stop.
  property bool owesDiscoveryStop: false
  // All known BlueZ devices, or [] before the service is ready.
  // qmllint disable unresolved-type
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
  // qmllint enable unresolved-type
  // All Pipewire nodes, or [] before the service is ready.
  readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  // The device awaiting its Pipewire sink to switch audio output to, or null.
  property var pendingAudioOutputDevice: null
  // Retries spent waiting for pendingAudioOutputDevice's sink to appear.
  property int pendingAudioOutputAttempts: 0

  // The device's display label, delegating to Model.js.
  function deviceLabel(device) {
    return Model.deviceLabel(device)
  }

  // Whether value looks like a Bluetooth service UUID.
  function isUuidLike(value) {
    return Model.isUuidLike(value)
  }

  // Whether value looks like a MAC address.
  function isAddressLike(value) {
    return Model.isAddressLike(value)
  }

  // Whether device has a name beyond its UUID or address.
  function hasHumanName(device) {
    return Model.hasHumanName(device)
  }

  // devices split into connected/known/discovered lists.
  readonly property var deviceGroups: Model.deviceLists(devices)
  // Devices BlueZ reports connected.
  readonly property var connectedDevices: deviceGroups.connected || []
  // Paired, bonded or trusted devices that are not connected.
  readonly property var knownDevices: deviceGroups.known || []
  // Unremembered devices seen while scanning.
  readonly property var discoveredDevices: deviceGroups.discovered || []

  // The bar icon: reflects adapter-off/connected/idle state.
  readonly property string icon: {
    if (!adapter)
      return ""
    if (!adapter.enabled)
      return String.fromCodePoint(0xf00b2)
    if (connectedDevices.length > 0)
      return String.fromCodePoint(0xf00b1)
    return String.fromCodePoint(0xf00af)
  }

  // Index into activePhrases for the rotating hero status line.
  property int phraseIndex: 0
  // Playful phrases shown in the hero status while Bluetooth is on.
  readonly property var activePhrases: ["Untangling wires", "Streaming vikings", "Pairing mysteries", "Herding headsets", "Taming radios", "Summoning speakers", "Wrangling codecs", "Polishing packets"]
  // The hero caption's opacity, which phraseSwap fades between phrases.
  // Passed to the view on its own, outside bluetoothView, so the fade never
  // rebuilds the view object.
  property real captionOpacity: 1
  // Whether the hero status should rotate through activePhrases.
  readonly property bool rotatingPhrases: adapter && adapter.enabled
  // The hero status line: adapter state, or a rotating phrase.
  readonly property string heroStatusText: {
    if (!adapter)
      return "No adapter"
    if (!adapter.enabled)
      return "Turned Off"
    return activePhrases[phraseIndex % activePhrases.length]
  }

  // Single cursor model shared by keyboard and mouse. Sections:
  //   "connected"  — currently connected devices; Enter disconnects.
  //   "known"      — remembered devices; Enter connects.
  //   "discovered" — unremembered devices visible while scanning; Enter connects.
  // The outline comes from this cursor (hasCursor), never from the
  // pointer: hover only draws the rows' own fill and never moves it.
  property string focusSection: "connected"
  // Row index within focusSection.
  property int selectedIndex: 0
  // Whether the cursor sits on a row's trailing action (forget) rather than the row itself.
  property bool actionFocused: false
  // Whether the keyboard cursor is visible (vs. idle, mouse-only).
  property bool cursorActive: false
  // True while the keyboard drives the cursor; any pointer action clears it.
  // The view outlines the cursor only then, so the mouse never shows one.
  property bool keyboardCursor: false
  // Upper-case address -> RSSI (dBm) for devices seen while scanning, read
  // from BlueZ by rssiProc. Quickshell's BluetoothDevice has no RSSI.
  property var rssiByAddress: ({})

  // Stable identity for the focused device. Devices move between sections as
  // they connect, disconnect, pair, or get forgotten, so follow the BlueZ
  // address across section changes instead of preserving a stale row index.
  property string focusedDeviceAddress: ""

  // What the power switch shows ({on, busy}, BluetoothLogic.powerView).
  readonly property var powerShown: BluetoothLogic.powerView(root.powerPending, !!root.adapter && root.adapter.enabled)

  // "header" is a virtual section for the hero Bluetooth on/off toggle; it
  // sits above the device sections so the adapter can be toggled by keyboard
  // even when it is off and no device rows exist.
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  // Tooltip text for the hero power switch.
  readonly property string toggleHint: root.powerShown.on ? "Turn Bluetooth off" : "Turn Bluetooth on"

  // hoverFill, selectedFill, scrollRowIndex and scrollSectionTitle fed
  // stock's own rows and ListView. The Aranea view doesn't use them; they
  // stay as stock wrote them so tools/upstream-drift can line this file up
  // with stock's.
  // qmllint disable missing-property
  // Row fill color under mouse hover.
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  // Row fill color for the keyboard-selected row.
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  // qmllint enable missing-property

  // Number of devices in a section.
  function sectionCount(section) {
    if (section === "connected")
      return connectedDevices.length
    if (section === "known")
      return knownDevices.length
    if (section === "discovered")
      return discoveredDevices.length
    return 0
  }

  // Whether a section should render (discovered needs active scanning).
  function sectionVisible(section) {
    if (section === "connected")
      return connectedDevices.length > 0
    if (section === "known")
      return knownDevices.length > 0
    if (section === "discovered")
      return adapter && adapter.discovering && discoveredDevices.length > 0
    return false
  }

  // Sections with content, in display order.
  readonly property var visibleSections: {
    return Model.visibleSections(deviceGroups, adapter && adapter.discovering)
  }

  // The devices belonging to a section.
  function devicesForSection(section) {
    return Model.sectionDevices(deviceGroups, section)
  }

  // The scrollable half of the panel (remembered devices, then whatever the
  // scan turned up) flattened into one list of primitive rows. Each entry
  // carries the section it came from and its index there, which is how the
  // view's Paired and Available rows and the cursor stay section-relative.
  readonly property var scrollRows: {
    var rows = []
    for (var k = 0; k < knownDevices.length; k++)
      rows.push({
        dev: Model.deviceRow(knownDevices[k]),
        section: "known",
        indexInSection: k
      })
    if (sectionVisible("discovered"))
      for (var d = 0; d < discoveredDevices.length; d++)
        rows.push({
          dev: Model.deviceRow(discoveredDevices[d]),
          section: "discovered",
          indexInSection: d
        })
    return rows
  }

  // Connected devices render above the scroll area; same primitives-only
  // projection so those delegates never hold Device QObject wrappers either.
  readonly property var connectedRows: {
    var rows = []
    for (var i = 0; i < connectedDevices.length; i++)
      rows.push(Model.deviceRow(connectedDevices[i]))
    return rows
  }

  // Live BlueZ device behind a row. Rows carry primitives only, so actions
  // resolve the backend object here rather than holding a wrapper that can
  // dangle mid-incubation. `devices` is already the raw device array (see the
  // property declaration), so it is iterated directly.
  function deviceFor(row) {
    if (!row || !row.dev)
      return null
    var addr = row.dev.address || ""
    var devs = devices || []
    for (var i = 0; i < devs.length; i++) {
      if ((devs[i].address || "") === addr)
        return devs[i]
    }
    return null
  }

  // Flat position of the keyboard cursor, or -1 while it sits on the hero or
  // in the connected list (both of which live outside the scroll area).
  readonly property int scrollRowIndex: {
    if (focusSection !== "known" && focusSection !== "discovered")
      return -1
    for (var i = 0; i < scrollRows.length; i++)
      if (scrollRows[i].section === focusSection && scrollRows[i].indexInSection === selectedIndex)
        return i
    return -1
  }

  // A row opens a section when it is the first of its kind in the flat list.
  function scrollSectionTitle(index) {
    var rows = scrollRows
    if (index < 0 || index >= rows.length)
      return ""
    if (index > 0 && rows[index - 1].section === rows[index].section)
      return ""
    return rows[index].section === "known" ? "PAIRED" : "AVAILABLE"
  }

  // Non-stream Pipewire sink nodes (candidate audio outputs).
  function audioSinks() {
    var sinks = []
    for (var i = 0; i < pipewireNodes.length; i++) {
      var node = pipewireNodes[i]
      if (node && node.isSink && !node.isStream)
        sinks.push(node)
    }
    return sinks
  }

  // The Pipewire sink backing a given Bluetooth device, if any.
  function bluetoothAudioSink(device) {
    var sinks = audioSinks()
    for (var i = 0; i < sinks.length; i++) {
      if (Model.bluetoothSinkMatchesDevice(sinks[i], device))
        return sinks[i]
    }
    return null
  }

  // Makes sink the system default audio output.
  function setDefaultAudioSink(sink) {
    if (!sink)
      return
    Pipewire.preferredDefaultAudioSink = sink
    if (sink.id !== undefined && sink.name) {
      Quickshell.execDetached(["omarchy-audio-output-set-default", String(sink.id), String(sink.name)])
    }
  }

  // Arranges to switch default audio output to device once its sink appears.
  function scheduleAudioOutputSwitch(device) {
    pendingAudioOutputDevice = {
      address: device && device.address ? device.address : "",
      name: device && device.name ? device.name : "",
      deviceName: device && device.deviceName ? device.deviceName : ""
    }
    pendingAudioOutputAttempts = 0
    audioSwitchTimer.restart()
  }

  // Retries the pending audio output switch until the sink appears or attempts run out.
  function switchPendingAudioOutput() {
    if (!pendingAudioOutputDevice)
      return
    var sink = bluetoothAudioSink(pendingAudioOutputDevice)
    if (sink) {
      setDefaultAudioSink(sink)
      pendingAudioOutputDevice = null
      audioSwitchTimer.stop()
      return
    }

    pendingAudioOutputAttempts += 1
    if (pendingAudioOutputAttempts >= 8) {
      pendingAudioOutputDevice = null
      return
    }
    audioSwitchTimer.restart()
  }

  // The device at index within a section, or null.
  function deviceAt(section, index) {
    var list = devicesForSection(section)
    return index >= 0 && index < list.length ? list[index] : null
  }

  // A shallow copy of a pending-actions map.
  function cloneMap(map) {
    return Model.cloneMap(map)
  }

  // The pending action for a device address, if any.
  function pendingAction(address) {
    return Model.pendingAction(pendingActions, address)
  }

  // Records (or clears) the pending action for a device address.
  function setPendingAction(address, action) {
    if (!address)
      return
    pendingActions = Model.withPendingAction(pendingActions, address, action)
    if (action)
      pendingTimeout.restart()
  }

  // The omarchy-bluetooth-device argv for an action on an address.
  function deviceCommand(action, address) {
    return ["omarchy-bluetooth-device", action, address]
  }

  // Marks a device pending and runs its BlueZ action detached.
  function runDeviceAction(device, action, pending) {
    if (!device || !device.address)
      return
    setPendingAction(device.address, pending)
    Quickshell.execDetached(deviceCommand(action, device.address))
  }

  // The action DEVICE is busy with (BluetoothLogic.inFlightIntent), "" when
  // idle.
  function deviceInFlight(device) {
    if (!device)
      return ""
    return BluetoothLogic.inFlightIntent(pendingAction(device.address || ""), device.state !== undefined ? device.state : -1, device.pairing === true)
  }

  // Asks for INTENT ("connect", "disconnect" or "forget") on DEVICE: run at
  // once when it is idle, else queued until it is (the last one wins; one
  // equal to the action in flight is dropped).
  function requestDeviceAction(device, intent) {
    if (!device || !device.address)
      return
    var r = BluetoothLogic.deviceClick(root.deviceQueue, device.address, intent, root.deviceInFlight(device))
    root.deviceQueue = r.queue
    if (r.run !== "")
      root.runIntent(device, r.run)
  }

  // Runs INTENT on DEVICE through stock's own action functions.
  function runIntent(device, intent) {
    if (intent === "connect")
      connectDevice(device)
    else if (intent === "disconnect")
      disconnectDevice(device)
    else if (intent === "forget")
      forgetDevice(device)
  }

  // Runs the queued actions whose device went idle; a device that is gone
  // drops its entry.
  function drainDeviceQueue() {
    if (Object.keys(root.deviceQueue).length === 0)
      return
    var busy = {}
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].address)
        busy[devices[i].address] = root.deviceInFlight(devices[i])
    var r = BluetoothLogic.takeReady(root.deviceQueue, busy)
    root.deviceQueue = r.queue
    for (var j = 0; j < r.run.length; j++)
      for (var k = 0; k < devices.length; k++)
        if (devices[k] && devices[k].address === r.run[j].key)
          root.runIntent(devices[k], r.run[j].intent)
  }

  // Connects (or pairs, if never paired) a device.
  function connectDevice(device) {
    if (!device || device.connected)
      return
    if (device.paired || device.bonded || device.trusted)
      runDeviceAction(device, "connect", "connecting")
    else
      runDeviceAction(device, "pair", "connecting")
  }

  // Disconnects a connected device.
  function disconnectDevice(device) {
    if (!device || !device.address)
      return
    if (!device.connected)
      return
    setPendingAction(device.address, "disconnecting")
    if (device.disconnect)
      device.disconnect()
    Quickshell.execDetached(deviceCommand("disconnect", device.address))
  }

  // Forgets (unpairs) a device.
  function forgetDevice(device) {
    if (!device || !device.address)
      return
    runDeviceAction(device, "forget", "forgetting")
  }

  // Ends a connect that failed fast: a "connecting" entry whose device went
  // from BlueZ's connecting state back to disconnected is cleared, so its
  // pulse stops and the queue can drain (BluetoothLogic.settleConnecting).
  function settleConnectingActions() {
    var states = {}
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].address)
        states[devices[i].address] = devices[i].state !== undefined ? devices[i].state : -1
    var r = BluetoothLogic.settleConnecting(root.pendingActions, root.connectingSeen, states)
    root.connectingSeen = r.seen
    if (r.changed)
      root.pendingActions = r.pending
  }

  // Clears pending actions whose BlueZ state has caught up.
  function syncPendingActions() {
    settleConnectingActions()
    var next = cloneMap(pendingActions)
    var changed = false

    for (var address in next) {
      var action = next[address]
      var found = null

      for (var i = 0; i < devices.length; i++) {
        var d = devices[i]
        if (d && d.address === address) {
          found = d
          break
        }
      }

      var finishedConnecting = action === "connecting" && found && found.connected
      if (finishedConnecting || (action === "disconnecting" && found && !found.connected) || (action === "forgetting" && (!found || (!found.paired && !found.bonded && !found.trusted)))) {
        if (finishedConnecting)
          scheduleAudioOutputSwitch(found)
        delete next[address]
        changed = true
      }
    }

    if (changed)
      pendingActions = next
  }

  // j/k navigates the hero toggle ("header") and the device sections
  // row-by-row.
  function moveCursor(delta) {
    var sections = visibleSections
    if (focusSection === "header") {
      if (delta > 0 && sections && sections.length > 0) {
        focusSection = sections[0]
        selectedIndex = 0
        actionFocused = false
      }
      return
    }
    if (!sections || sections.length === 0) {
      focusSection = "header"
      actionFocused = false
      return
    }
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = 0
      actionFocused = false
      return
    }

    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1

    if (delta > 0) {
      if (idx < max) {
        selectedIndex = idx + 1
        actionFocused = false
        return
      }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = 0
        actionFocused = false
      }
    } else {
      if (idx > 0) {
        selectedIndex = idx - 1
        actionFocused = false
        return
      }
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        selectedIndex = sectionCount(focusSection) - 1
        actionFocused = false
      } else {
        focusSection = "header"
        actionFocused = false
      }
    }
  }

  // Moves the keyboard cursor onto the hero power toggle.
  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    actionFocused = false
  }

  // h/l switches the cursor between a row and its trailing (forget) action.
  function moveCursorH(delta) {
    if (!cursorActive) {
      cursorActive = true
      return
    }
    if (focusSection !== "known" && focusSection !== "connected")
      return
    var dev = deviceAt(focusSection, selectedIndex)
    if (!dev || !dev.address)
      return
    if (delta > 0)
      actionFocused = true
    else if (delta < 0)
      actionFocused = false
  }

  // Enter: activates whatever the cursor currently sits on.
  function activateCursor() {
    if (focusSection === "header") {
      toggleBluetooth()
      return
    }
    if (actionFocused) {
      deleteSelected()
      return
    }

    if (focusSection === "connected" || focusSection === "known") {
      var dev = deviceAt(focusSection, selectedIndex)
      if (!dev)
        return
      requestDeviceAction(dev, BluetoothLogic.rowIntent("primary", !!dev.connected, focusSection))
      return
    }
    if (focusSection === "discovered") {
      var d = discoveredDevices[selectedIndex]
      if (!d)
        return
      requestDeviceAction(d, BluetoothLogic.rowIntent("primary", !!d.connected, "discovered"))
    }
  }

  // 'x' forgets remembered devices. For connected devices this first
  // disconnects, then removes the BlueZ pairing record via omarchy-bluetooth-device.
  // Arms pendingRemovalKey, so the cursor stays shown on the neighbour once
  // the device has left the remembered lists (followForget).
  function deleteSelected() {
    if (focusSection !== "known" && focusSection !== "connected")
      return
    var dev = deviceAt(focusSection, selectedIndex)
    if (!dev)
      return
    var stops = root.forgetStops()
    for (var i = 0; i < stops.length; i++)
      if (stops[i].key === dev.address) {
        root.pendingRemovalKey = dev.address
        root.pendingRemovalIndex = i
      }
    requestDeviceAction(dev, "forget")
  }

  // The keyboard cursor's stops for following a Forget
  // (BluetoothLogic.forgetStops), read from deviceGroups itself: the three
  // per-section lists update one after another, so a sibling read from
  // them could still be stale.
  function forgetStops() {
    var addr = function (list) {
      return (list || []).map(function (d) {
        return d ? (d.address || "") : ""
      })
    }
    var groups = deviceGroups || {}
    return BluetoothLogic.forgetStops(addr(groups.connected), addr(groups.known), sectionVisible("discovered") ? addr(groups.discovered) : [])
  }

  // After the device lists changed: lands the cursor on the neighbour once a
  // keyboard-forgotten device has left the remembered lists
  // (BluetoothLogic.followForget), else re-finds the focused device by
  // address as stock did.
  function followDevices() {
    var r = BluetoothLogic.followForget(root.forgetStops(), root.pendingRemovalKey, root.pendingRemovalIndex)
    root.pendingRemovalKey = r.pendingKey
    root.pendingRemovalIndex = r.lastIndex
    if (!r.follow) {
      reselectFocusedDevice()
      return
    }
    actionFocused = false
    focusSection = r.section
    if (r.index >= 0)
      selectedIndex = r.index
    updateFocusedAddress()
  }

  onOpenedChanged: {
    if (opened) {
      // Adopt a discovery session that is already running — a popout handoff
      // from another monitor, or one leaked by an instance that could not
      // finish its own stop — so this close settles it either way.
      if (adapter !== null && adapter.discovering)
        owesDiscoveryStop = true
      if (connectedDevices.length > 0) {
        focusSection = "connected"
        selectedIndex = 0
      } else if (knownDevices.length > 0) {
        focusSection = "known"
        selectedIndex = 0
      } else if (discoveredDevices.length > 0) {
        focusSection = "discovered"
        selectedIndex = 0
      } else {
        focusSection = "header"
      }
      actionFocused = false
      cursorActive = false
    }
    pendingRemovalKey = ""
    pendingRemovalIndex = -1
  }

  // Another per-monitor instance of this widget whose panel is open, if any.
  // All instances share the default adapter, and switching the popout to a
  // different monitor closes one instance as it opens the next, so the
  // closing side has to leave the scan alone for the side still on screen.
  // qmllint disable missing-property
  function openSibling() {
    if (!bar || typeof bar.moduleWidgets !== "function")
      return null
    var items = bar.moduleWidgets(moduleName)
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i] !== root && items[i].opened === true)
        return items[i]
    }
    return null
  }
  // qmllint enable missing-property

  // Refreshes focusedDeviceAddress from the current cursor position.
  function updateFocusedAddress() {
    var d = deviceAt(focusSection, selectedIndex)
    focusedDeviceAddress = d ? (d.address || "") : ""
  }

  // Re-finds the focused device by address after the device lists change.
  function reselectFocusedDevice() {
    if (focusedDeviceAddress === "") {
      clampCursor()
      return
    }

    var sections = ["connected", "known", "discovered"]
    for (var s = 0; s < sections.length; s++) {
      var section = sections[s]
      if (!sectionVisible(section))
        continue
      var list = devicesForSection(section)
      for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].address === focusedDeviceAddress) {
          focusSection = section
          selectedIndex = i
          clampCursor()
          return
        }
      }
    }

    clampCursor()
  }

  onSelectedIndexChanged: updateFocusedAddress()
  onFocusSectionChanged: updateFocusedAddress()
  // One device change updates the three lists one after another; the
  // follow runs once, after all of them, so a forgotten device counts as
  // gone only when it has left every remembered list.
  onConnectedDevicesChanged: {
    Qt.callLater(root.followDevices)
    syncPendingActions()
  }
  onKnownDevicesChanged: {
    Qt.callLater(root.followDevices)
    syncPendingActions()
  }
  onDiscoveredDevicesChanged: {
    Qt.callLater(root.followDevices)
    syncPendingActions()
  }
  onVisibleSectionsChanged: clampCursor()
  // A device's pending action cleared: run what was queued for it.
  onPendingActionsChanged: Qt.callLater(root.drainDeviceQueue)
  // A row's busy state may have cleared with BlueZ's own state.
  // A fast-failing connect is caught here too (settleConnectingActions).
  onConnectedViewRowsChanged: {
    Qt.callLater(root.settleConnectingActions)
    Qt.callLater(root.drainDeviceQueue)
  }
  // (see onConnectedViewRowsChanged)
  onKnownViewRowsChanged: {
    Qt.callLater(root.settleConnectingActions)
    Qt.callLater(root.drainDeviceQueue)
  }
  // (see onConnectedViewRowsChanged)
  onDiscoveredViewRowsChanged: {
    Qt.callLater(root.settleConnectingActions)
    Qt.callLater(root.drainDeviceQueue)
  }

  // Keeps the cursor within the current sections/rows after they change.
  function clampCursor() {
    var sections = visibleSections
    // "header" is virtual and never appears in visibleSections, so it has to
    // be let through: toggling the adapter empties and refills the device
    // lists, and clamping would knock the cursor off the hero switch every
    // time it is used.
    if (focusSection === "header")
      return
    if (!sections || !sections.length) {
      selectedIndex = 0
      return
    }
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = 0
      return
    }
    var count = sectionCount(focusSection)
    if (count === 0) {
      // Section emptied out — bounce to the previous visible one.
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = Math.max(0, sectionCount(focusSection) - 1)
      return
    }
    if (selectedIndex > count - 1)
      selectedIndex = count - 1
    if (selectedIndex < 0)
      selectedIndex = 0
  }

  visible: adapter !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // BlueZ rejects StartDiscovery while the adapter is still powering up, and
  // discovery can also time out on its own. While the panel is open, keep
  // nudging it back on so an enabled adapter is always scanning.
  Timer {
    id: discoveryRetry
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.opened && root.adapter !== null && root.adapter.enabled && !root.adapter.discovering
    onTriggered: {
      root.owesDiscoveryStop = true
      root.adapter.discovering = true
    }
  }

  // The way back down. The BlueZ discovery session behind adapter.discovering
  // is held by quickshell's D-Bus connection, so nothing ends it at close:
  // without this timer, one visit to the panel left the radio in inquiry
  // until the next shell restart, starving A2DP audio on the same controller
  // into stutters.
  //
  // A timer bound to the confirmed state rather than a write at close time:
  // quickshell only forwards a discovering write that differs from the last
  // state BlueZ reported, so a stop issued while a just-fired StartDiscovery
  // is still awaiting confirmation would be swallowed and leak the session.
  // Binding to adapter.discovering means a confirmation landing at any point
  // after close re-arms the stop, and a reopen inside the first interval
  // keeps the scan running uninterrupted. Attempts are bounded so a session
  // some other BlueZ client keeps up cannot draw StopDiscovery fire forever.
  Timer {
    id: discoveryStop
    interval: 1000
    repeat: true
    property int attempts: 0
    running: !root.opened && root.owesDiscoveryStop && root.adapter !== null && root.adapter.discovering === true
    onRunningChanged: if (running)
      attempts = 0
    onTriggered: {
      // The scan now serves the open panel, so the debt moves with it — B may
      // have opened before BlueZ confirmed A's start, in which case B's own
      // open-time adoption saw nothing to adopt.
      var sibling = root.openSibling()
      if (sibling) {
        sibling.owesDiscoveryStop = true
        root.owesDiscoveryStop = false
        return
      }
      attempts += 1
      if (attempts > 3) {
        root.owesDiscoveryStop = false
        return
      }
      root.adapter.discovering = false
    }
  }

  // The debt is settled the moment BlueZ reports discovery down — whether
  // because the stop above landed or the session ended some other way — so a
  // stale claim never touches a scan another client starts later. While the
  // panel is open, discoveryRetry re-incurs it as it restarts the scan.
  Connections {
    target: root.adapter
    function onDiscoveringChanged() {
      if (!root.adapter.discovering)
        root.owesDiscoveryStop = false
    }
  }

  // A destroyed instance cannot wait for BlueZ confirmations, so it hands any
  // debt to a surviving sibling — whose declarative stop catches even a start
  // confirmed after this object is gone — and only writes the stop directly
  // when it is the last one standing.
  // qmllint disable missing-property
  Component.onDestruction: {
    if (!owesDiscoveryStop)
      return
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i] !== root) {
        items[i].owesDiscoveryStop = true
        return
      }
    }
    if (adapter !== null && adapter.discovering)
      adapter.discovering = false
  }
  // qmllint enable missing-property

  Timer {
    id: pendingTimeout
    interval: 20000
    repeat: false
    onTriggered: {
      root.pendingActions = ({})
      root.connectingSeen = ({})
      root.pendingRemovalKey = ""
      // A queued action never outlives the pending it waited on.
      root.deviceQueue = BluetoothLogic.queueAfter("timeout", root.deviceQueue)
    }
  }

  // Gives up on a power change BlueZ never echoed: the switch shows the
  // adapter's state again.
  Timer {
    id: powerTimeout
    interval: 5000
    onTriggered: root.powerPending = BluetoothLogic.powerIdle()
  }

  // BlueZ echoed a power change (or something else changed it).
  Connections {
    target: root.adapter
    function onEnabledChanged() {
      root.applyPower(BluetoothLogic.powerEcho(root.powerPending, root.adapter.enabled))
    }
  }

  Timer {
    id: audioSwitchTimer
    interval: 500
    repeat: false
    onTriggered: root.switchPendingAudioOutput()
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    // With motion off the phrase just steps, without the fade.
    onTriggered: {
      if (Aranea.DesignTokens.motionEnabled)
        phraseSwap.restart()
      else
        root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
  }

  // Stock's caption fade, on captionOpacity rather than stock's own Text.
  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: root
      property: "captionOpacity"
      to: 0.0
      duration: 180
      easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: root
      property: "captionOpacity"
      to: 1.0
      duration: 260
      easing.type: Easing.InQuad
    }
  }

  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        root.captionOpacity = 1.0
      }
    }
  }

  // Reads every BlueZ device's RSSI in one D-Bus call, for the Available
  // rows' signal glow.
  Process {
    id: rssiProc
    command: ["busctl", "--json=short", "call", "org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"]
    stdout: StdioCollector {
      waitForEnd: true
      // Only a changed reading is assigned, so a quiet poll doesn't rebuild
      // the view every 2 s.
      onStreamFinished: {
        if (!root.opened)
          return
        var next = BluetoothLogic.parseRssi(text)
        if (BluetoothLogic.rssiChanged(root.rssiByAddress, next))
          root.rssiByAddress = next
      }
    }
  }

  // Polls rssiProc only while the open panel is scanning with something to
  // show under Available; closed, nothing runs.
  Timer {
    interval: 2000
    repeat: true
    triggeredOnStart: true
    running: root.opened && root.adapter !== null && root.adapter.enabled && root.adapter.discovering && root.discoveredDevices.length > 0
    onTriggered: if (!rssiProc.running)
      rssiProc.running = true
  }

  // Additions to stock's open/cursor handlers: a fresh open starts with the
  // mouse's (outline-free) cursor and a close drops the RSSI readings; a
  // keyboard move scrolls its row into view.
  Connections {
    target: root
    function onOpenedChanged() {
      root.keyboardCursor = false
      // Stand-in names never carry over into an open or past a close.
      root.showcaseNames = []
      if (!root.opened) {
        root.rssiByAddress = ({})
        // A queued action or power click never runs with the panel closed;
        // a power change in flight finishes.
        root.deviceQueue = BluetoothLogic.queueAfter("close", root.deviceQueue)
        root.powerPending = BluetoothLogic.powerAfter("close", root.powerPending)
      }
    }
    function onFocusSectionChanged() {
      Qt.callLater(root.ensureCursorVisible)
    }
    function onSelectedIndexChanged() {
      Qt.callLater(root.ensureCursorVisible)
    }
    function onKeyboardCursorChanged() {
      Qt.callLater(root.ensureCursorVisible)
    }
  }

  // A row's status line, the same rules stock's DeviceRow used: pending
  // action first, then the battery of a connected device, then BlueZ's
  // connecting/disconnecting states.
  function rowStatusText(dev, section) {
    if (!dev)
      return ""
    var action = pendingAction(dev.address || "")
    var devState = dev.state !== undefined ? dev.state : -1
    if (action === "forgetting")
      return "Forgetting…"
    if (action === "disconnecting" || devState === 2)
      return "Disconnecting…"
    if (dev.connected) {
      if (dev.batteryAvailable)
        return Math.round(dev.battery * 100) + "%"
      return section === "connected" ? "" : "Connected"
    }
    if (action === "connecting" || devState === 3 || dev.pairing === true)
      return "Connecting…"
    return ""
  }

  // One view row from a stock primitive row (Model.deviceRow) and the live
  // device behind it, which supplies the type icon deviceRow doesn't carry.
  function viewRow(dev, device, section) {
    var state = dev && dev.state !== undefined ? dev.state : -1
    return {
      key: dev ? dev.address : "",
      label: deviceLabel(dev) || "Device",
      glyph: BluetoothLogic.deviceGlyph(device ? device.icon : "", !!(dev && dev.connected)),
      detail: rowStatusText(dev, section),
      busy: !!dev && (pendingAction(dev.address || "") !== "" || state === 2 || state === 3 || dev.pairing === true),
      forgettable: section !== "discovered"
    }
  }

  // View rows for SECTION ("known" or "discovered") out of scrollRows.
  function scrollViewRows(section) {
    var rows = []
    for (var i = 0; i < scrollRows.length; i++) {
      var r = scrollRows[i]
      if (r.section === section)
        rows.push(viewRow(r.dev, deviceAt(section, r.indexInSection), section))
    }
    return rows
  }

  // The view's Connected rows. These row arrays are their own bindings, apart
  // from bluetoothView, so RSSI and the rotating phrase never rebuild them.
  // Showcase names relabel Connected, Paired, then Available in display
  // order; the offsets are read only then, so they never rebuild a section.
  readonly property var connectedViewRows: Showcase.showcaseLabels(connectedRows.map(function (dev, i) {
    return viewRow(dev, connectedDevices[i], "connected")
  }), showcaseNames, "Device")
  // The view's Paired rows (see connectedViewRows).
  readonly property var knownViewRows: Showcase.showcaseLabels(scrollViewRows("known"), showcaseNames, "Device", showcaseNames.length > 0 ? connectedRows.length : 0)
  // The view's Available rows (see connectedViewRows).
  readonly property var discoveredViewRows: Showcase.showcaseLabels(scrollViewRows("discovered"), showcaseNames, "Device", showcaseNames.length > 0 ? connectedRows.length + knownDevices.length : 0)
  // Address -> signal level (0..3) behind each Available row's node glow.
  readonly property var deviceSignals: {
    var out = {}
    for (var i = 0; i < discoveredViewRows.length; i++) {
      var key = discoveredViewRows[i].key
      out[key] = BluetoothLogic.signalLevel(rssiByAddress[String(key).toUpperCase()])
    }
    return out
  }

  // Everything the Aranea view draws (BluetoothDropdown.view).
  readonly property var bluetoothView: ({
      glyph: icon,
      caption: heroStatusText,
      enabled: !!adapter && adapter.enabled,
      hasAdapter: !!adapter,
      toggleHint: toggleHint,
      headerCursor: headerHasCursor && keyboardCursor,
      power: powerShown,
      scanning: !!adapter && adapter.enabled && adapter.discovering,
      open: opened,
      cursor: {
        active: cursorActive && keyboardCursor,
        section: focusSection,
        index: selectedIndex,
        action: actionFocused
      },
      connected: connectedViewRows,
      known: knownViewRows,
      discovered: discoveredViewRows,
      signals: deviceSignals,
      emptyText: BluetoothLogic.emptyText(!!adapter, !!adapter && adapter.enabled, connectedRows.length > 0 || scrollRows.length > 0)
    })

  // The live device behind the view's row INDEX in SECTION, resolved the
  // way stock's rows did: through deviceFor on the section's primitive row.
  function viewDevice(section, index) {
    if (section === "connected")
      return deviceFor({
        dev: connectedRows[index]
      })
    for (var i = 0; i < scrollRows.length; i++)
      if (scrollRows[i].section === section && scrollRows[i].indexInSection === index)
        return deviceFor(scrollRows[i])
    return null
  }

  // Carries out one BluetoothDropdown action. Every action comes from the
  // pointer, so each one hands the cursor back from the keyboard. A hover
  // is only the rows' own fill: it never moves the cursor or hides the
  // outline.
  function handleAction(name, arg) {
    if (name === "hover")
      return
    keyboardCursor = false
    if (name === "toggleBluetooth") {
      toggleBluetooth()
      return
    }
    // Pointer use spends a keyboard Forget's follow.
    pendingRemovalKey = ""
    // Keyed: the row must still carry the address the view saw there.
    if (!BluetoothLogic.rowKeyMatches(viewRowsFor(arg.section), arg.index, arg.key))
      return
    var dev = viewDevice(arg.section, arg.index)
    if (!dev || dev.address !== arg.key)
      return
    requestDeviceAction(dev, BluetoothLogic.rowIntent(name, !!dev.connected, arg.section))
  }

  // The view rows SECTION shows ("connected", "known" or "discovered").
  function viewRowsFor(section) {
    if (section === "connected")
      return connectedViewRows
    if (section === "known")
      return knownViewRows
    if (section === "discovered")
      return discoveredViewRows
    return []
  }

  // Scrolls the keyboard cursor's row into the view's Paired/Available
  // scroll area. Pointer moves leave the scroll position alone.
  function ensureCursorVisible() {
    if (!opened || !cursorActive || !keyboardCursor)
      return
    dropdown.ensureVisible(focusSection, selectedIndex)
  }

  // Not adapter.enabled: that writes BlueZ's Powered, which nothing persists, so
  // the adapter came back on at the next boot. omarchy-bluetooth-power moves the
  // rfkill soft block instead, which systemd-rfkill restores across reboots.
  // Powered still follows the block, so the switch and icon read it as before.
  //
  // Asking for a direction rather than a toggle: the helper runs detached and the
  // switch only moves once BlueZ catches up, so a second click inside that window
  // would re-read the old state and undo the first.
  //
  // The switch shows the new state at once and pulses until Powered echoes
  // it; clicks while it waits queue (the last one wins), and powerTimeout
  // falls back to the real state (BluetoothLogic.powerClick).
  function toggleBluetooth() {
    if (!adapter)
      return
    // Every power path spends a keyboard Forget's follow.
    root.pendingRemovalKey = ""
    applyPower(BluetoothLogic.powerClick(root.powerPending, adapter.enabled))
  }

  // Applies a power step RESULT ({state, send}, BluetoothLogic.powerClick or
  // powerEcho): stores the state, then sends the direction, if any.
  function applyPower(result) {
    root.powerPending = result.state
    if (result.send !== null)
      Quickshell.execDetached(["omarchy-bluetooth-power", result.send ? "on" : "off"])
    if (root.powerPending.target === null)
      powerTimeout.stop()
    else if (result.send !== null)
      powerTimeout.restart()
  }

  IpcHandler {
    target: "omarchy.bluetooth"

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
    function toggleBluetooth() {
      root.toggleBluetooth()
    }
    // Screenshot stand-ins (scripts/capture-screenshots): NAMESJSON, a JSON
    // array of strings, relabels every device row until the dropdown
    // closes; while it is closed the answer is "closed" and nothing is set.
    // Display only.
    function showcase(namesJson: string): string {
      var call = Showcase.showcaseCall(root.opened, namesJson)
      if (call.names !== null)
        root.showcaseNames = call.names
      return call.answer
    }
  }

  // Stand-in names for README screenshots (the showcase IPC method); empty
  // outside a capture, and cleared whenever the dropdown closes.
  property var showcaseNames: []

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: function (b) {
      root.keyboardCursor = false
      if (b === Qt.RightButton)
        root.toggleBluetooth()
      else
        root.toggle()
    }
  }

  // The Aranea view in the shared keyboard frame. The view pins the header
  // and Connected and scrolls Paired and Available itself, so the frame only
  // sizes to it; stock's 400 px list cap becomes the view's scroll cap.
  Aranea.KeyboardPanelFrame {
    id: panel
    refined: true
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(dropdown.implicitHeight)
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      dropdown.disarmPointer()
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      dropdown.disarmPointer()
      // Moving on spends a keyboard Forget's follow.
      root.pendingRemovalKey = ""
      // The first key after opening or after mouse use only reveals the
      // cursor where it is.
      if (!root.cursorActive || !root.keyboardCursor) {
        root.cursorActive = true
        root.keyboardCursor = true
        return
      }
      if (dy !== 0)
        root.moveCursor(dy)
      else if (dx !== 0)
        root.moveCursorH(dx)
    }
    // Enter and x, like any first key, only reveal a hidden cursor; they
    // act only on the outlined row.
    onActivateRequested: {
      dropdown.disarmPointer()
      if (!root.cursorActive || !root.keyboardCursor) {
        root.cursorActive = true
        root.keyboardCursor = true
        return
      }
      root.activateCursor()
    }
    onDeleteRequested: {
      dropdown.disarmPointer()
      if (!root.cursorActive || !root.keyboardCursor) {
        root.cursorActive = true
        root.keyboardCursor = true
        return
      }
      root.deleteSelected()
    }
    onTextKey: function (t) {
      dropdown.disarmPointer()
      if (t === "b" || t === "B") {
        root.keyboardCursor = true
        root.toggleBluetooth()
      }
    }

    Item {
      anchors.fill: parent
      clip: true

      BluetoothDropdown {
        id: dropdown
        width: parent.width
        maxScrollHeight: Style.space(400)
        captionOpacity: root.captionOpacity
        view: root.bluetoothView
        onAction: function (name, arg) {
          root.handleAction(name, arg)
        }
      }
    }
  }
}
