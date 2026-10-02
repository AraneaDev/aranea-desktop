// Aranea Network (araneadev.network, cloned from omarchy.network): the bar
// Wi-Fi/Ethernet icon and its dropdown. Stock logic (connection details,
// throughput/ping polling, Wi-Fi scanning and actions, DNS and band
// selection, the cursor model and IPC), plus the extras (link history,
// interfaces, saved profiles, a VPN status line); the Aranea view,
// NetworkDropdown, replaces the stock one. VPN control itself lives in
// araneadev.vpn, summoned from the status line's click.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "NetworkLogic.js" as NetworkLogic
import "../araneadev.shared/ShowcaseLogic.js" as Showcase
import "../araneadev.shared/CursorLogic.js" as CursorLogic
import "../araneadev.shared/GraphLogic.js" as GraphLogic
import "../araneadev.shared/VpnApps.js" as VpnApps
import "../araneadev.shared" as Aranea

Panel {
  id: root
  moduleName: "omarchy.network"
  ipcTarget: "omarchy.network"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the toggleNetwork method below.
  manageIpc: false

  // Centralized close so callers can't forget to drop the passphrase prompt.
  function close() {
    root.controller.hide()
    cancelPasswordPrompt()
  }

  // Clears the inline passphrase prompt's state.
  function cancelPasswordPrompt() {
    passwordSsid = ""
    passwordText = ""
    identityText = ""
  }

  // Live connection details from `ip` / /sys / iw.
  property var info: ({})  // { iface, type, ip, prefix, gateway, speed, duplex, ssid, signal, freq, bitrate, rx_bytes, tx_bytes, router_ping_ms, internet_ping_ms }

  // Throughput tracking. Rates are computed as deltas between successive
  // `omarchy-network-status --verbose` samples (~1.5s apart via detailsPoll).
  // We hold "prev" alongside a timestamp so the first sample after open or
  // after an interface switch doesn't manufacture a spike.
  property real prevRxBytes: 0
  // Bytes sent as of the last sample.
  property real prevTxBytes: 0
  // Wall-clock time of the last sample, in seconds.
  property real prevSampleTime: 0
  // Interface the last sample was taken on; a change resets the rate calc.
  property string prevIface: ""
  // Download rate in bytes/sec, derived from the last two samples.
  property real downloadRate: 0  // bytes/sec
  // Upload rate in bytes/sec, derived from the last two samples.
  property real uploadRate: 0    // bytes/sec
  // Interface the ping history was sampled on; a change resets the window.
  property string pingIface: ""
  // Recent router ping samples, newest last, windowed to pingHistoryWindow.
  property var routerPingSamples: []
  // Recent internet ping samples, newest last, windowed to pingHistoryWindow.
  property var internetPingSamples: []
  // Rolling average router ping latency in ms, or -1 before enough samples.
  property real routerPingLatency: -1
  // Rolling average internet ping latency in ms, or -1 before enough samples.
  property real internetPingLatency: -1
  // Percentage of the recent internet ping samples that were lost.
  property int internetPingPacketLoss: 0
  // How many ping samples routerPingSamples/internetPingSamples retain.
  readonly property int pingHistoryWindow: 24
  // How many of the most recent samples the rolling average is taken over.
  readonly property int pingAverageWindow: 5
  // Whether there is at least one internet ping sample to report on.
  readonly property bool hasInternetPing: internetPingSamples.length > 0
  // Every stat row stays mounted whether or not there is data behind it, so a
  // sample arriving late never reflows the grid. This says whether the numbers
  // are real yet or the row should read "--".
  readonly property bool hasTransferStats: info.rx_bytes !== undefined
  // Index into connectionPhrases for the rotating status phrase.
  property int connectionPhraseIndex: 0
  // Phrases that rotate through the header caption while connected.
  readonly property var connectionPhrases: ["Wiring bits", "Handling packets", "Sorting frames", "Hauling bytes", "Routing crumbs", "Counting collisions", "Bending light",]
  // The current rotating status phrase, derived from connectionPhraseIndex.
  readonly property string connectionPhrase: connectionPhrases[connectionPhraseIndex % connectionPhrases.length]
  // Whether the active Quickshell.Networking backend is NetworkManager.
  readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
  // All network devices NetworkManager reports, or [] before it's ready.
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  // The Wi-Fi device to drive, preferring one that's actually connected.
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  // Raw WifiNetwork objects from wifiDevice, or [] when there's no device.
  readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  // The currently connected Wi-Fi network, or null.
  readonly property var connectedWifiNetwork: findConnectedWifiNetwork()
  // Plain-object snapshots of wifiNetworkObjects for the row list, sorted for display.
  property var wifiNetworks: []
  // Whether a Wi-Fi scan triggered by this panel is in flight.
  property bool scanning: false
  // Whether a Wi-Fi device is present to scan and connect with.
  property bool wifiStationAvailable: false
  // The DNS provider currently in effect, as reported by omarchy-dns.
  property string dnsProvider: ""
  // The DNS provider a change is in flight for, until actionProc exits.
  property string pendingDnsProvider: ""
  // Wi-Fi band state from `omarchy-network-band`. `bandCurrent` is the band
  // the radio is actually on; `bandSelected` is the pinned choice ("auto" when
  // nothing is pinned), and the two differ whenever Auto is in effect.
  property string bandCurrent: ""
  // The pinned band choice, or "auto" when nothing is pinned.
  property string bandSelected: "auto"
  // Bands the current AP/radio can use, from omarchy-network-band.
  property var bandAvailable: []
  // The band a pin change is in flight for, until actionProc exits.
  property string pendingBand: ""

  // Per-row in-flight state. `actionSsid` flips on for the row whose action
  // is currently running so it can render "Connecting…" / "Disconnecting…" /
  // "Forgetting…". `passwordSsid` is the row currently expanded into
  // password-entry mode; we keep it open across refresh cycles so a slow scan
  // doesn't collapse the input the user is typing into. Rows must gate
  // comparisons on the matching `*Kind`/`*Reason` being non-empty so a
  // hidden-SSID row (ssid == "") doesn't collide with the "" defaults.
  property string actionSsid: ""
  // Which action is running, or "" when idle.
  property string actionKind: ""  // "connect" | "disconnect" | "forget"
  // The SSID the last action failed for, until cleared.
  property string failureSsid: ""
  // Human-readable reason the last action failed, until cleared.
  property string failureReason: ""
  // The SSID whose row is expanded into the passphrase prompt, or "".
  property string passwordSsid: ""
  // The passphrase text currently typed into the inline prompt.
  property string passwordText: ""
  // The 802.1X identity text typed into the inline prompt (enterprise networks).
  property string identityText: ""

  // ConnectionFailReason values as a plain object, so Model.js helpers stay
  // pure JS and Node-testable.
  readonly property var connectionFailReasons: ({
      NoSecrets: ConnectionFailReason.NoSecrets,
      WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
      WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
      WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
      WifiClientFailed: ConnectionFailReason.WifiClientFailed
    })

  // True while any wifi action is mid-flight. Rows
  // disable themselves on this so clicks on the other rows don't silently
  // no-op against runNetworkAction's serialized guard.
  readonly property bool busy: actionKind !== ""

  // Index into `wifiNetworks` for keyboard navigation. -1 = no selection.
  property int selectedIndex: -1
  // Whether the forget/action affordance on the selected row has keyboard focus.
  property bool wifiActionFocused: false
  // Whether keyboard/mouse navigation has placed a cursor anywhere yet.
  property bool cursorActive: false

  // Keyboard focus zone for the panel. j/k crosses row boundaries:
  // header actions ⇄ band ⇄ DNS row ⇄ Wi-Fi networks. h/l move
  // within header actions, band pills, or DNS providers.
  property string focusSection: "dns"  // "header" | "band" | "dns" | "wifi"
  // Index into the header action row (QR / speed test / Wi-Fi toggle) for keyboard nav.
  property int headerIndex: 0
  // Whether there's a connected Wi-Fi network to disconnect from.
  readonly property bool canDisconnect: !!connectedWifiNetwork
  // Kept for stock parity; the disconnect action lives on the row, not the header.
  readonly property bool headerHasDisconnect: false
  // Whether the connected Wi-Fi network can be shared via QR code.
  readonly property bool canShareWifi: info.type === "wifi" && canShareNetwork(connectedWifiNetwork)
  // The hero switch is the Wi-Fi radio, so it only exists when there is a
  // radio to switch. On a wired box it would otherwise sit there reading
  // "off" beside a perfectly live Ethernet connection.
  readonly property bool canToggleWifi: networkManagerAvailable && wifiStationAvailable
  // Header action slot for the QR button, or -1 when it isn't shown.
  readonly property int qrHeaderIndex: canShareWifi ? 0 : -1
  // Header action slot for the speed test button, or -1 when it isn't shown.
  readonly property int speedHeaderIndex: canRunSpeedTest ? (canShareWifi ? 1 : 0) : -1
  // Header action slot for the Wi-Fi power switch, or -1 when it isn't shown.
  readonly property int toggleHeaderIndex: canToggleWifi ? (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) : -1
  // How many header actions are currently shown.
  readonly property int headerActionCount: (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) + (canToggleWifi ? 1 : 0)
  // Whether the keyboard cursor is on the QR header action.
  readonly property bool qrHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === qrHeaderIndex
  // Whether the keyboard cursor is on the speed test header action.
  readonly property bool speedHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === speedHeaderIndex
  // Whether the keyboard cursor is on the Wi-Fi power header action.
  readonly property bool toggleHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === toggleHeaderIndex
  // Tooltip text for the Wi-Fi power switch.
  readonly property string toggleHint: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
  // The selectable DNS provider options, in display order.
  readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]
  // Index into dnsProviders for keyboard nav.
  property int dnsIndex: 0
  // ["2.4", "5", ...], or empty when there is nothing to choose between.
  // Wi-Fi only: on Ethernet the band of a secondary radio is not what the
  // panel is describing.
  // `bandBusy` keeps the section mounted across the reconnect a band change
  // causes: `kind` stops being "wifi" for a second or two in the middle of it,
  // and without this the whole segment would vanish and rebuild itself.
  // Worth showing when there is a real choice, or when a pin is in force even
  // though only one band answers right now -- otherwise the Automatic switch
  // vanishes and the pin becomes unclearable from the panel.
  readonly property bool canSelectBand: (kind === "wifi" || bandBusy) && (bandAvailable.length > 1 || bandPinned)
  // While a change is in flight, show the state that was asked for rather than
  // the one still in force, so the row answers the click immediately instead of
  // after the reconnect. actionProc puts it back if the change failed.
  readonly property string bandEffective: pendingBand !== "" ? pendingBand : bandSelected
  // Whether a specific band (not Automatic) is currently pinned.
  readonly property bool bandPinned: bandEffective !== "auto"
  // Under Automatic there is nothing to pick, so the pills collapse away and
  // the header states the live band instead.
  readonly property bool bandPillsVisible: canSelectBand && bandPinned
  // Header text for the band section: the live band, or the pinned one.
  readonly property string bandSectionTitle: Model.bandSectionTitle(bandEffective, bandCurrent)
  // Whether a band pin change is in flight.
  readonly property bool bandBusy: pendingBand !== ""
  // The speed test needs an interface to test, so its hero action only
  // appears once there is one.
  readonly property bool canRunSpeedTest: !!info.iface
  // Index into bandAvailable for keyboard nav within the band pills.
  property int bandIndex: 0
  // The band section has up to two cursor rows: the Automatic switch on the
  // header line, then the pills. Same shape as wifiActionFocused.
  property bool bandAutoFocused: true

  onHeaderActionCountChanged: clampHeaderIndex()

  // Availability shifts as scans land, so the option list can shrink out from
  // under the cursor. Clamp the index and evacuate the section before it
  // disappears, or the panel is left highlighting nothing.
  onBandAvailableChanged: {
    if (bandIndex > bandAvailable.length - 1)
      bandIndex = Math.max(0, bandAvailable.length - 1)
  }

  onCanSelectBandChanged: {
    if (!canSelectBand && focusSection === "band") {
      focusSection = "dns"
      bandAutoFocused = true
    }
  }

  // Collapsing the pills out from under the cursor would leave it pointing at
  // nothing, so send it up to the switch that is still on screen.
  onBandPillsVisibleChanged: {
    if (!bandPillsVisible)
      bandAutoFocused = true
  }

  // Keeps headerIndex within [0, headerActionCount - 1].
  function clampHeaderIndex() {
    var max = Math.max(0, headerActionCount - 1)
    if (headerIndex > max)
      headerIndex = max
    if (headerIndex < 0)
      headerIndex = 0
  }

  // Moves the header cursor by delta, clamped to the available actions.
  function selectHeaderByDelta(delta) {
    headerIndex = Math.max(0, Math.min(headerActionCount - 1, headerIndex + delta))
  }

  // Turns the Wi-Fi radio on or off via NetworkManager.
  function toggleNetwork() {
    if (!networkManagerAvailable)
      return
    Networking.wifiEnabled = !Networking.wifiEnabled
    Qt.callLater(function () {
      root.refresh(true)
    })
  }

  IpcHandler {
    target: "omarchy.network"

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
    function toggleNetwork() {
      root.toggleNetwork()
    }
    // Compat routes for configs that summon the centered cards through the
    // network target; both cards are their own plugins now.
    function showQr() {
      root.summonWifiQr(true)
    }
    function speedTest() {
      root.summonSpeedTest()
    }
    // Screenshot stand-ins (scripts/capture-screenshots): NAMESJSON, a JSON
    // array of strings, relabels the Wi-Fi, Saved and interface rows, the
    // VPN status line and the header until the dropdown closes; while it is closed the
    // answer is "closed" and nothing is set. Display only.
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

  // Runs whichever header action is under the keyboard cursor.
  function activateHeader() {
    if (headerIndex === qrHeaderIndex)
      summonWifiQr()
    else if (headerIndex === speedHeaderIndex)
      summonSpeedTest()
    else if (headerIndex === toggleHeaderIndex)
      toggleNetwork()
  }

  // Moves the keyboard cursor to a header action, from a mouse hover.
  function setHeaderCursor(index) {
    cursorActive = true
    focusSection = "header"
    headerIndex = index
  }

  // Moves the DNS provider cursor by delta, clamped to dnsProviders.
  function selectDnsByDelta(delta) {
    dnsIndex = Math.max(0, Math.min(dnsProviders.length - 1, dnsIndex + delta))
  }

  // Applies the DNS provider under the keyboard cursor.
  function activateDns() {
    if (dnsIndex < 0 || dnsIndex >= dnsProviders.length)
      return
    setDns(dnsProviders[dnsIndex])
  }

  // Moves the band pill cursor by delta, clamped to bandAvailable.
  function selectBandByDelta(delta) {
    bandIndex = Math.max(0, Math.min(bandAvailable.length - 1, bandIndex + delta))
  }

  // Applies the band pill or toggles Automatic, whichever is under the cursor.
  function activateBand() {
    if (bandAutoFocused) {
      toggleBandAuto()
      return
    }
    if (bandIndex < 0 || bandIndex >= bandAvailable.length)
      return
    setBand(bandAvailable[bandIndex])
  }

  // Switching Automatic off has to commit to something, so it pins whatever
  // band the radio already landed on -- the reading the pills are showing.
  function toggleBandAuto() {
    if (bandSelected !== "auto") {
      setBand("auto")
      return
    }
    if (bandCurrent === "")
      return
    setBand(bandCurrent)
  }

  // Park the cursor on the pinned band, so opening the panel highlights the
  // pill the user would expect. Under Automatic there are no pills, so the
  // cursor belongs on the switch.
  function syncBandIndex() {
    var idx = bandAvailable.indexOf(bandSelected)
    bandIndex = idx >= 0 ? idx : 0
    bandAutoFocused = !bandPillsVisible
  }

  // Display label for a band value, delegating to Model.js.
  function bandLabel(band) {
    return Model.bandLabel(band)
  }

  // Tooltip text for a band value, delegating to Model.js.
  function bandTooltip(band) {
    return Model.bandTooltip(band)
  }

  // Single cursor model: exactly one highlighted spot across the whole
  // panel, located via `focusSection` + (`headerIndex` | `dnsIndex` |
  // `selectedIndex`). Mouse hover and keyboard nav both mutate this state
  // at the root; items never read containsMouse for visuals. See
  // CursorSurface for the shared chrome shared by rows and pills.
  //
  // hoverFill and selectedFill fed stock's own rows and pills. The Aranea
  // view doesn't use them; they stay as stock wrote them so
  // tools/upstream-drift can line this file up with stock's.
  // qmllint disable missing-property
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  // Fill color for the row/pill the keyboard or mouse selection currently sits on.
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  // qmllint enable missing-property

  // scannerEnabled lives on the shared WifiDevice, which has no reference
  // counting, and a bar widget is instantiated once per monitor. Tracking the
  // device this instance turned scanning on for keeps the release correct when
  // the panel closes, the device is replaced, or the widget is destroyed —
  // without a closed instance ever claiming the scanner.
  property var scannerDevice: null

  // Turns the Wi-Fi scanner on or off for whichever device this panel owns scanning for.
  function setScannerEnabled(enabled) {
    var nextDevice = opened ? wifiDevice : null

    if (scannerDevice && scannerDevice !== nextDevice)
      scannerDevice.scannerEnabled = false

    scannerDevice = nextDevice

    if (scannerDevice)
      scannerDevice.scannerEnabled = enabled
  }

  Component.onDestruction: {
    if (scannerDevice)
      scannerDevice.scannerEnabled = false
  }

  // KeyboardPanel primes layer-shell focus whenever the panel opens. That's
  // what makes the SUPER+CTRL+W keybind land here with navigation ready.
  onOpenedChanged: {
    if (opened) {
      refresh(true)
      selectedIndex = wifiNetworks.length > 0 ? 0 : -1
      wifiActionFocused = false
      focusSection = wifiNetworks.length > 0 ? "wifi" : "dns"
      var idx = dnsProviders.indexOf(dnsProvider)
      dnsIndex = idx >= 0 ? idx : 0
      syncBandIndex()
      cursorActive = false
    } else {
      // Drop a restart armed by this open: without it a close/reopen inside
      // the 100ms window reuses the running timer and re-enables the scanner
      // almost immediately, undoing the deferral #6605 restored.
      scanRestart.stop()
      // Reset throughput tracking so the next open doesn't compute a fake
      // rate from a sample taken minutes ago.
      prevSampleTime = 0
      downloadRate = 0
      uploadRate = 0
      pingIface = ""
      routerPingSamples = []
      internetPingSamples = []
      routerPingLatency = -1
      internetPingLatency = -1
      internetPingPacketLoss = 0
      setScannerEnabled(false)
    }
  }

  // When the passphrase prompt closes (Esc / Cancel / success) restore
  // focus to the keyCatcher so j/k/Enter resume working without a click.
  // The KeyboardPanel's focusTarget covers initial popup-open; this handles
  // the inline-editor case where focus was handed off to a child.
  onPasswordSsidChanged: {
    if (passwordSsid === "" && opened) {
      passwordText = ""
      Qt.callLater(function () {
        if (keyCatcher)
          keyCatcher.forceActiveFocus()
      })
    }
  }

  // Keep selectedIndex valid as scans refresh the network list.
  // If the list empties (station gone, e.g. wifi off), bounce the cursor
  // back to the DNS row so the panel doesn't end up with no cursor at all.
  onWifiNetworksChanged: {
    if (wifiNetworks.length === 0) {
      selectedIndex = -1
      wifiActionFocused = false
      if (focusSection === "wifi")
        focusSection = "dns"
    } else if (passwordSsid !== "") {
      var passwordIndex = wifiIndexForSsid(passwordSsid)
      if (passwordIndex >= 0) {
        selectedIndex = passwordIndex
        focusSection = "wifi"
      }
    } else if (selectedIndex >= wifiNetworks.length) {
      selectedIndex = wifiNetworks.length - 1
    } else if (selectedIndex < 0 && opened) {
      selectedIndex = 0
    }

    if (selectedIndex < 0 || selectedIndex >= wifiNetworks.length || !canForgetNetwork(wifiNetworks[selectedIndex])) {
      wifiActionFocused = false
    }
  }

  onWifiDeviceChanged: {
    setScannerEnabled(true)
    syncWifiNetworks()
  }

  onWifiNetworkObjectsChanged: syncWifiNetworks()

  // Moves the Wi-Fi row selection by delta, clamped to wifiNetworks.
  function selectByDelta(delta) {
    if (wifiNetworks.length === 0) {
      selectedIndex = -1
      return
    }
    if (selectedIndex < 0)
      selectedIndex = delta > 0 ? 0 : wifiNetworks.length - 1
    else
      selectedIndex = Math.max(0, Math.min(wifiNetworks.length - 1, selectedIndex + delta))
    wifiActionFocused = false
  }

  // Whether net can be forgotten, delegating to Model.js.
  function canForgetNetwork(net) {
    return Model.canForgetNetwork(net)
  }

  // Whether net is connected and not an enterprise (802.1X) network, so it can be shared via QR.
  function canShareNetwork(net) {
    if (!net || !net.connected)
      return false
    return net.security !== WifiSecurityType.Wpa2Eap && net.security !== WifiSecurityType.WpaEap
  }

  // Moves focus onto/off of the selected row's forget action.
  function selectWifiActionByDelta(delta) {
    if (selectedIndex < 0 || selectedIndex >= wifiNetworks.length)
      return
    if (!canForgetNetwork(wifiNetworks[selectedIndex])) {
      wifiActionFocused = false
      return
    }
    if (delta > 0)
      wifiActionFocused = true
    else if (delta < 0)
      wifiActionFocused = false
  }

  // Enter/Space on the highlighted row. Mirrors row-click semantics:
  // connected → disconnect, credentials-required/unknown → prompt,
  // passwordless/known → connect.
  function activateSelected() {
    if (busy || selectedIndex < 0 || selectedIndex >= wifiNetworks.length)
      return
    var net = wifiNetworks[selectedIndex]
    if (!net)
      return
    if (wifiActionFocused && canForgetNetwork(net)) {
      forget(net)
      return
    }
    // Only act on a row that still resolves. disconnect() falls back to
    // connectedWifiNetwork when handed null, so a row left stale by scan churn
    // would otherwise tear down whatever is connected now instead.
    if (net.connected) {
      disconnectRow(net.ssid)
      return
    }
    if (requiresCredentials(net.security) && !net.known) {
      openPasswordPrompt(net.ssid)
      return
    }
    connectDirectly(net.ssid)
  }

  // Bar pill state, derived from the native NetworkManager service so the
  // icon reflects connection changes without polling. Wired is preferred
  // when both are up, matching the default-route device.
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  // The bar icon's connection kind: "ethernet" | "wifi" | "disconnected".
  readonly property string kind: {
    if (wiredDevice && wiredDevice.connected)
      return "ethernet"
    if (connectedWifiNetwork)
      return "wifi"
    return "disconnected"
  }
  // Connected Wi-Fi signal strength as a percentage, or -1 when not on Wi-Fi.
  readonly property int signalStrength: connectedWifiNetwork ? Math.round((connectedWifiNetwork.signalStrength || 0) * 100) : -1

  // Copies value to the clipboard via wl-copy.
  function copyToClipboard(value) {
    if (!value || !root.bar)
      return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  // The bar glyph for the current connection kind/signal, from Model.js.
  readonly property string icon: Model.connectionIcon(kind, signalStrength)

  // The share card is its own panel plugin (omarchy.wifiqr) so a replacement
  // design can take it over; summon() routes to whichever implementation is
  // enabled. The panel's own button pins the interface it is showing. The
  // IPC route forces self-detection instead: details polling stops while the
  // panel is closed, so its cached interface can be stale.
  function summonWifiQr(forceDetect) {
    controller.hide()
    cancelPasswordPrompt()
    var payload = {}
    if (!forceDetect && info.type === "wifi" && info.iface) {
      payload.iface = info.iface
      if (info.ssid)
        payload.ssid = info.ssid
    }
    // qmllint disable missing-property
    bar.shell.summon("omarchy.wifiqr", JSON.stringify(payload))
    // qmllint enable missing-property
  }

  // Re-polls connection details, DNS and band, and optionally kicks off a Wi-Fi scan.
  function refresh(scanWifi) {
    if (scanWifi === undefined)
      scanWifi = false
    if (!detailsProc.running)
      detailsProc.running = true
    if (!dnsProc.running) {
      dnsProc.command = ["bash", "-c", root.dnsCommand("")]
      dnsProc.running = true
    }
    if (!bandProc.running) {
      bandProc.command = ["omarchy-network-band"]
      bandProc.running = true
    }
    // A closed panel has no nearby-network list to fill, and bare refresh()
    // reaches here from action completion, timeouts and construction.
    if (opened && wifiDevice) {
      if (scanWifi) {
        scanning = true
        setScannerEnabled(false)
        scanRestart.start()
      } else {
        setScannerEnabled(true)
      }
    }
    syncWifiNetworks()
  }

  // Formats a link speed (Mbps) for the header detail, delegating to Model.js.
  function formatHeaderSpeed(mbps) {
    return Model.formatHeaderSpeed(mbps)
  }

  // Formats a Wi-Fi frequency (MHz) for the header detail, delegating to Model.js.
  function formatHeaderFreq(mhz) {
    return Model.formatHeaderFreq(mhz)
  }

  // The parenthetical header detail text (e.g. "2.5gbit"), delegating to Model.js.
  function headerDetail() {
    return Model.headerDetail(info)
  }

  // Applies a freshly parsed `omarchy-network-status --verbose` sample.
  function updateDetails(raw) {
    var next = Model.parseKeyValue(raw)

    // A band change tears the link down and brings it back, and the status
    // command reports nothing at all while there is no route. Publishing that
    // would blank every stat and unmount the whole section mid-toggle, so the
    // last good sample stands until the reconnect settles. A real disconnect is
    // still reported, because nothing is in flight then.
    if (bandBusy && !next.iface)
      return
    info = next
    updateThroughput(next)
    updatePingLatency(next)
    recordLinkSample()
  }

  // Recomputes download/upload rates from the latest sample.
  function updateThroughput(next) {
    var state = Model.throughputState({
      prevIface: prevIface,
      prevRxBytes: prevRxBytes,
      prevTxBytes: prevTxBytes,
      prevSampleTime: prevSampleTime,
      downloadRate: downloadRate,
      uploadRate: uploadRate
    }, next, Date.now() / 1000)

    prevIface = state.prevIface
    prevRxBytes = state.prevRxBytes
    prevTxBytes = state.prevTxBytes
    prevSampleTime = state.prevSampleTime
    downloadRate = state.downloadRate
    uploadRate = state.uploadRate
  }

  // Recomputes rolling ping latency/loss from the latest sample.
  function updatePingLatency(next) {
    var state = Model.pingLatencyState({
      pingIface: pingIface,
      routerPingSamples: routerPingSamples,
      internetPingSamples: internetPingSamples
    }, next, pingHistoryWindow, pingAverageWindow)

    pingIface = state.pingIface
    routerPingSamples = state.routerPingSamples
    internetPingSamples = state.internetPingSamples
    routerPingLatency = state.routerPingLatency
    internetPingLatency = state.internetPingLatency
    internetPingPacketLoss = state.internetPingPacketLoss
  }

  // Formats a byte count for display, delegating to Model.js.
  function formatBytes(bytes) {
    return Model.formatBytes(bytes)
  }

  // Formats a bytes/sec rate for display, delegating to Model.js.
  function formatRate(bytesPerSec) {
    return Model.formatRate(bytesPerSec)
  }

  // Formats a ping latency for display, delegating to Model.js.
  function formatPingLatency(ms) {
    return Model.formatPingLatency(ms, hasInternetPing)
  }

  // Formats a packet-loss percentage for display, delegating to Model.js.
  function formatPacketLoss(percent) {
    return Model.formatPacketLoss(percent, hasInternetPing)
  }

  // Prefer a connected device: a machine can expose several NICs of the
  // same type (e.g. an idle onboard port alongside the active adapter),
  // and the first-enumerated one may be carrierless.
  function findDevice(type) {
    var devices = networkDevices || []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type)
        continue
      if (device.connected)
        return device
      if (!fallback)
        fallback = device
    }
    return fallback
  }

  // The Wi-Fi network object NetworkManager reports as connected, or null.
  function findConnectedWifiNetwork() {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected)
        return networks[i]
    }
    return null
  }

  // Rebuilds wifiNetworks from the live WifiNetwork objects.
  function syncWifiNetworks() {
    var nets = []
    var networks = wifiNetworkObjects || []

    for (var i = 0; i < networks.length; i++) {
      var network = networks[i]
      if (!network)
        continue
      checkActionCompletion(network)
      var row = Model.wifiRow(network)
      if (row)
        nets.push(row)
    }
    wifiNetworks = Model.sortWifiRows(nets)
    wifiStationAvailable = !!wifiDevice
    scanning = false
  }

  // Section header text ("Connected"/"Known"/"Available") for a row index, delegating to Model.js.
  function wifiSectionTitle(index) {
    return Model.wifiSectionTitle(wifiNetworks, index)
  }

  // Signal-strength glyph for a row, delegating to Model.js.
  function wifiIconFor(strength) {
    return Model.wifiIconFor(strength)
  }

  // Applies the DNS provider reported by omarchy-dns.
  function updateDns(raw) {
    var value = String(raw || "").trim()
    dnsProvider = value || "DHCP"
  }

  // Applies a freshly parsed `omarchy-network-band` sample.
  function updateBand(raw) {
    var status = Model.parseBandStatus(raw)

    // Mid-reconnect there is no connected station, so the command reports
    // nothing. Publishing that would empty the option list and unmount the
    // section on every toggle -- same guard as updateDetails.
    if (bandBusy && status.available.length === 0)
      return
    bandCurrent = status.band
    bandSelected = status.selected
    bandAvailable = status.available
  }

  // Pinning a band reassociates, but the panel deliberately stays open: the
  // reconnect is the thing you want to watch, and the details rows above
  // report it as it happens.
  function setBand(band) {
    if (!band || actionProc.running)
      return
    root.pendingBand = band
    actionProc.command = ["omarchy-network-band", band]
    actionProc.running = true
  }

  // The speed test is its own panel plugin (omarchy.speedtest) so a
  // replacement design can take it over; summon() routes to whichever
  // implementation is enabled. The payload names the connection when this
  // panel knows it; the plugin looks it up itself otherwise.
  function summonSpeedTest() {
    controller.hide()
    cancelPasswordPrompt()
    var connection = ""
    if (info.type === "wifi")
      connection = info.ssid || "Wi-Fi"
    else if (info.type === "ethernet")
      connection = "Ethernet"
    // qmllint disable missing-property
    bar.shell.summon("omarchy.speedtest", connection ? JSON.stringify({
      connection: connection
    }) : "{}")
    // qmllint enable missing-property
  }

  // The status line's click: VPN control is its own panel plugin
  // (araneadev.vpn), summoned by id; this one closes first, as the other
  // summon actions do.
  function openVpnDropdown() {
    if (!root.bar)
      return
    controller.hide()
    cancelPasswordPrompt()
    // qmllint disable missing-property
    bar.shell.summon("araneadev.vpn")
    // qmllint enable missing-property
  }

  // Shell command to query or set the DNS provider.
  function dnsCommand(provider) {
    var command = "omarchy-dns"
    if (provider)
      command += " " + Util.shellQuote(provider)
    return command
  }

  // Sets the DNS provider, or opens a terminal for a custom one.
  function setDns(provider) {
    if (!root.bar || !provider || actionProc.running)
      return
    if (provider === "Custom") {
      var launcher = "omarchy-launch-floating-terminal-with-presentation"
      // qmllint disable missing-property
      root.bar.run(launcher + " " + Util.shellQuote(root.dnsCommand(provider)))
      // qmllint enable missing-property
      root.close()
      return
    }

    root.pendingDnsProvider = provider
    actionProc.command = ["bash", "-c", root.dnsCommand(provider)]
    actionProc.running = true
    root.close()
  }

  // Whether security needs a passphrase, delegating to Model.js.
  function requiresCredentials(security) {
    return Model.requiresCredentials(security, WifiSecurityType.Open, WifiSecurityType.Owe)
  }

  // Expands ssid's row into the inline passphrase prompt.
  function openPasswordPrompt(ssid) {
    if (passwordSsid !== ssid) {
      passwordText = ""
      identityText = ""
    }
    passwordSsid = ssid
  }

  // The live WifiNetwork object for ssid, or null.
  function networkForSsid(ssid) {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].name === ssid)
        return networks[i]
    }
    return null
  }

  // Index into wifiNetworks for ssid, or -1.
  function wifiIndexForSsid(ssid) {
    for (var i = 0; i < wifiNetworks.length; i++) {
      if (wifiNetworks[i] && wifiNetworks[i].ssid === ssid)
        return i
    }
    return -1
  }

  // Starts a tracked Wi-Fi action (connect/disconnect/forget) with a timeout safety net.
  function runNetworkAction(kind, network, callback) {
    if (actionKind !== "" || !network)
      return
    var ssid = network.name || ""
    actionSsid = ssid
    actionKind = kind
    failureSsid = ""
    failureReason = ""
    callback(network)
    // Safety net: if onExited never fires (process death, signal handler
    // throws, etc.), clear the busy state so the row doesn't get stuck on
    // "Connecting…" / "Disconnecting…" forever.
    actionTimeout.restart()
  }

  // Clears in-flight action state once it completes.
  function clearNetworkAction() {
    actionTimeout.stop()
    if (actionKind === "connect")
      passwordSsid = ""
    failureSsid = ""
    failureReason = ""
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  // Records a failed action's reason so the row can show it.
  function failNetworkAction(network, reason) {
    if (!network || actionKind === "" || actionSsid !== (network.name || ""))
      return
    actionTimeout.stop()
    failureSsid = actionSsid
    failureReason = networkFailureReason(reason, requiresCredentials(network.security))
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  // Human-readable failure reason for a ConnectionFailReason, delegating to Model.js.
  function networkFailureReason(reason, needsCredentials) {
    return Model.networkFailureReason(reason, needsCredentials, connectionFailReasons)
  }

  // Whether a failure should reopen the passphrase prompt, delegating to Model.js.
  function shouldRepromptPassphrase(reason, needsCredentials) {
    return Model.shouldRepromptPassphrase(reason, needsCredentials, connectionFailReasons)
  }

  // Clears the in-flight action once network reflects its outcome.
  function checkActionCompletion(network) {
    if (!network || actionKind === "" || actionSsid !== (network.name || ""))
      return
    if (actionKind === "connect" && network.connected)
      clearNetworkAction()
    else if (actionKind === "disconnect" && !network.connected && !network.stateChanging)
      clearNetworkAction()
    else if (actionKind === "forget" && !network.known && !network.stateChanging)
      clearNetworkAction()
  }

  // Connects to ssid without a passphrase.
  function connectDirectly(ssid) {
    runNetworkAction("connect", networkForSsid(ssid), function (network) {
      network.connect()
    })
  }

  // Connects to ssid using a PSK passphrase.
  function connectWithPassphrase(ssid, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function (network) {
      network.connectWithPsk(passphrase)
    })
  }

  // Connects to ssid using 802.1X identity/passphrase credentials.
  function connectEnterprise(ssid, identity, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function (network) {
      enterpriseConnect.secret = passphrase
      enterpriseConnect.command = ["bash", "-c", Model.enterpriseConnectScript, "nmcli-eap", ssid, identity]
      enterpriseConnect.running = true
    })
  }

  // Creates and activates the 802.1X profile (see Model.enterpriseConnectScript).
  // The password goes over stdin, never argv.
  Process {
    id: enterpriseConnect
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
  }

  // Disconnects network, or the currently connected network when network is null.
  function disconnect(network) {
    runNetworkAction("disconnect", network || connectedWifiNetwork, function (net) {
      net.disconnect()
    })
  }

  // Disconnect from a row's SSID. Rows are primitive snapshots that can outlive
  // their WifiNetwork, and disconnect()'s null fallback targets whatever is
  // connected now, so a stale row must do nothing rather than hit an unrelated
  // network. Callers that mean "drop the current connection" call disconnect().
  function disconnectRow(ssid) {
    var network = networkForSsid(ssid)
    if (network)
      disconnect(network)
  }

  // Forgets net's saved connection.
  function forget(net) {
    runNetworkAction("forget", net ? networkForSsid(net.ssid) : null, function (network) {
      network.forget()
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // Pulls everything we want about the active route's interface in one shot.
  Process {
    id: detailsProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDetails(text)
    }
  }

  Timer {
    id: scanRestart
    interval: 100
    repeat: false
    onTriggered: {
      if (root.opened && root.wifiDevice) {
        root.setScannerEnabled(true)
        scanDone.start()
      }
    }
  }

  Timer {
    id: scanDone
    interval: 1500
    repeat: false
    onTriggered: root.syncWifiNetworks()
  }

  Process {
    id: dnsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDns(text)
    }
  }

  Process {
    id: bandProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateBand(text)
    }
  }

  // Slower than detailsPoll on purpose: this shells out to nmcli several times,
  // and band availability only moves when a scan turns up a new BSSID.
  Timer {
    id: bandPoll
    interval: 4000
    repeat: true
    running: root.opened
    onTriggered: {
      if (bandProc.running)
        return
      bandProc.command = ["omarchy-network-band"]
      bandProc.running = true
    }
  }

  // Action runner for DNS provider changes. Wi-Fi actions use the
  // Quickshell.Networking NetworkManager backend directly.
  // qmllint disable signal-handler-parameters
  Process {
    id: actionProc
    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
    }
    onExited: function (exitCode) {
      if (root.pendingDnsProvider !== "") {
        if (exitCode === 0)
          root.dnsProvider = root.pendingDnsProvider
        root.pendingDnsProvider = ""
      }
      if (root.pendingBand !== "") {
        // A refused or reverted pin leaves bandSelected alone, so the pills
        // keep showing what is actually in force rather than what was asked.
        if (exitCode === 0)
          root.bandSelected = root.pendingBand
        root.pendingBand = ""
        // The panel stayed open through the reconnect, so pull fresh state now
        // instead of leaving stale readings until the next poll tick.
        root.refresh()
      }
    }
  }
  // qmllint enable signal-handler-parameters

  // Poll details while the panel is open so the IP/route header catches up
  // as soon as NetworkManager finishes activating a connection.
  Timer {
    id: detailsPoll
    interval: 1500
    repeat: true
    running: root.opened
    onTriggered: if (!detailsProc.running)
      detailsProc.running = true
  }

  Timer {
    id: connectionPhraseTimer
    interval: 2800
    running: root.opened && (root.info.type === "ethernet" || (root.info.type === "wifi" && root.canDisconnect))
    repeat: true
    onTriggered: connectionPhraseSwap.restart()
  }

  SequentialAnimation {
    id: connectionPhraseSwap
    PropertyAnimation {
      target: root
      property: "captionOpacity"
      to: 0.0
      duration: 180
      easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.connectionPhraseIndex = (root.connectionPhraseIndex + 1) % root.connectionPhrases.length
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
    function onInfoChanged() {
      if (!(root.info.type === "ethernet" || (root.info.type === "wifi" && root.canDisconnect))) {
        connectionPhraseSwap.stop()
        root.captionOpacity = 1.0
      }
    }
  }

  Timer {
    id: actionTimeout
    // Must outlast NetworkManager's 25s supplicant timeout: a wrong saved
    // PSK fails with WifiAuthTimeout at ~25s, and that failure has to land
    // while the action is still tracked to show "Wrong password" and reopen
    // the passphrase prompt.
    interval: 30000
    repeat: false
    onTriggered: {
      if (!root.actionKind)
        return
      var reason
      if (root.actionKind === "connect")
        reason = "Timed out connecting"
      else if (root.actionKind === "disconnect")
        reason = "Timed out disconnecting"
      else
        reason = "Timed out forgetting"
      root.failureSsid = root.actionSsid
      root.failureReason = reason
      root.actionSsid = ""
      root.actionKind = ""
      root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon

    onPressed: function (b) {
      if (root.opened)
        root.close()
      else
        // open() is enough: onOpenedChanged runs refresh(true), which defers the
        // PHY scan past the first frame. The bare refresh() that used to follow
        // took the no-scan branch and set scannerEnabled synchronously, undoing
        // that deferral and stalling the open on NetworkManager's AP flood.
        root.open()
    }
  }

  // ---------- Aranea additions: the extras, the view and the keyboard ----------

  // Stock's name for the item that takes keyboard focus back when the
  // passphrase prompt closes (onPasswordSsidChanged); here it's the frame's
  // key catcher.
  readonly property Item keyCatcher: panel.focusTarget
  // True while the keyboard drives the cursor; any pointer action clears it.
  // The view outlines the cursor only then, so the mouse never shows one.
  property bool keyboardCursor: false
  // The cursor's row in the Saved section.
  property int savedIndex: 0
  // Whether the cursor sits on the Saved row's forget button.
  property bool savedActionFocused: false
  // The SSID of the Wi-Fi row the cursor was deliberately put on (a move,
  // hover, click or open; never a keyboard reveal), so the cursor follows that
  // network when a scan re-sorts the list. Never adopted from a clamp: when
  // the network is gone it's "" and keyboard actions refuse until the user
  // picks a row (CursorLogic.followCursor).
  property string wifiCursorSsid: ""
  // The uuid of the Saved row the cursor was put on (see wifiCursorSsid).
  property string savedCursorKey: ""
  // The header action ("qr", "speed" or "toggle") the cursor was put on, so
  // an action appearing or vanishing never slides another under it.
  property string headerCursorKey: ""
  // The band control the cursor was put on: a pill's band, or "auto" for
  // the Automatic switch (see headerCursorKey).
  property string bandCursorKey: ""
  // The section the user last deliberately put the cursor in (a move,
  // hover, click, or "wifi" from open's row-0 placement; never a keyboard
  // reveal). An automatic move (a section emptying or hiding under the
  // cursor) changes focusSection but not this, so keyboard actions there
  // refuse until the user picks a row.
  property string cursorChosenSection: ""

  // The SSID of Wi-Fi row INDEX, or "" when there is none.
  function wifiSsidAt(index) {
    var net = wifiNetworks[index]
    return net ? net.ssid : ""
  }

  // Wi-Fi rows as {key} for the NetworkLogic cursor rules.
  function wifiKeyRows() {
    return wifiNetworks.map(function (n) {
      return {
        key: n ? n.ssid : ""
      }
    })
  }

  // The shown header actions as {key}, in headerIndex order.
  function headerKeyRows() {
    var rows = []
    if (canShareWifi)
      rows.push({
        key: "qr"
      })
    if (canRunSpeedTest)
      rows.push({
        key: "speed"
      })
    if (canToggleWifi)
      rows.push({
        key: "toggle"
      })
    return rows
  }

  // The band pills as {key}, in bandIndex order.
  function bandKeyRows() {
    return bandAvailable.map(function (b) {
      return {
        key: b
      }
    })
  }

  // SECTION's rows as {key}, or [] for a section without keyed rows.
  function sectionKeyRows(section) {
    if (section === "header")
      return headerKeyRows()
    if (section === "band")
      return bandKeyRows()
    if (section === "wifi")
      return wifiKeyRows()
    if (section === "saved")
      return savedRows
    return []
  }

  // The key SECTION's cursor was put on.
  function sectionKey(section) {
    if (section === "header")
      return headerCursorKey
    if (section === "band")
      return bandCursorKey
    if (section === "wifi")
      return wifiCursorSsid
    if (section === "saved")
      return savedCursorKey
    return ""
  }

  // Records KEY as the row SECTION's cursor was put on.
  function setSectionKey(section, key) {
    if (section === "header")
      headerCursorKey = key
    else if (section === "band")
      bandCursorKey = key
    else if (section === "wifi")
      wifiCursorSsid = key
    else if (section === "saved")
      savedCursorKey = key
  }

  // Puts SECTION's cursor key on whatever row (or band control) it now
  // shows and records SECTION as chosen: only for deliberate placements (a
  // move, hover or click).
  function chooseCursorRow(section) {
    cursorChosenSection = section
    if (section === "band" && bandAutoFocused) {
      bandCursorKey = "auto"
      return
    }
    var row = sectionKeyRows(section)[cursorIndexIn(section)]
    setSectionKey(section, row && typeof row.key === "string" ? row.key : "")
  }

  // Whether the keyboard may act on the cursor in SECTION: it's the section
  // the user chose, and the cursor still sits on the row (or band control)
  // they chose and can see (NetworkLogic.keyTargetConfirmed). DNS's pills
  // never move. Keyboard actions refuse otherwise, so a re-sort, a vanished
  // row or an automatic move never retargets a key press.
  function cursorRowConfirmed(section) {
    return NetworkLogic.keyTargetConfirmed(cursorTarget(section))
  }

  // The cursor's target in SECTION for NetworkLogic.keyTargetConfirmed and
  // pressOutcome: the section, the one last chosen, whether its controls
  // never move (DNS), and its rows, key and index.
  function cursorTarget(section) {
    var auto = section === "band" && bandAutoFocused
    return {
      section: section,
      chosen: cursorChosenSection,
      fixed: section === "dns",
      rows: auto ? [
        {
          key: "auto"
        }
      ] : sectionKeyRows(section),
      key: sectionKey(section),
      index: auto ? 0 : cursorIndexIn(section)
    }
  }
  // The header caption's opacity, which connectionPhraseSwap fades between
  // phrases. Passed to the view on its own, outside networkView, so the fade
  // never rebuilds the view object.
  property real captionOpacity: 1
  // Throughput samples for the Link graph, oldest first: [{iface, rx, tx}].
  // Cleared on close; pushSample restarts it on an interface change.
  property var linkHistory: []
  // NetworkManager devices from the extras poll (NetworkLogic.parseDevices).
  property var extraDevices: []
  // NetworkManager connection profiles from the extras poll
  // (NetworkLogic.parseConnections).
  property var extraConnections: []
  // Interface name -> IPv4 address from the extras poll (NetworkLogic.parseAddrs).
  property var extraAddrs: ({})
  // The same extras poll's `ip -j -4 -br addr` links, parsed for own-app VPN
  // detection (NetworkLogic.parseLinks, VpnApps.appState/appInterface).
  property var extraLinks: []
  // The parsed own-app VPN config: {apps, profiles} (VpnApps.parseAppsConfig).
  // Network only reads apps' name/label/detect for the status line; VPN
  // control (profiles, connect/disconnect) lives in araneadev.vpn.
  property var vpnAppsConfig: ({
      apps: [],
      profiles: {}
    })
  // The last apps-file error warned about, so each distinct one warns once.
  property string vpnAppsError: ""
  // Saved Wi-Fi profile uuid -> SSID, read on open and after a saved forget.
  property var ssidByUuid: ({})
  // Whether the next extras result should be followed by an SSID lookup.
  property bool ssidLookupPending: false
  // The Saved profile a forget is running for, until the next extras read
  // that started after it finished; "" otherwise.
  property string savedForgettingUuid: ""
  // The Saved profile whose last forget failed, for savedForgetFailedTimer's
  // 4 s ("Couldn't forget"), or "".
  property string savedForgetFailedUuid: ""
  // Whether another extras read was asked for while one ran.
  property bool extrasDirty: false
  // Row arrays kept by CursorLogic.keepRows, so an unchanged refresh hands
  // the view the same array and its Repeaters keep their delegates.
  property var rowCache: ({})

  // Records one Link graph sample from the rates stock just computed. Only
  // while open, so the occasional refresh of a closed panel adds nothing.
  function recordLinkSample() {
    if (!opened || !info.iface || !hasTransferStats)
      return
    linkHistory = GraphLogic.pushSample(linkHistory, {
      iface: info.iface,
      rx: downloadRate,
      tx: uploadRate
    }, 40)
  }

  // Applies the own-app VPN config file's text, or null when it's missing
  // (no apps). A file with any error is ignored as a whole
  // (VpnApps.appsToApply) and warns once per distinct error, as
  // araneadev.vpn does, so both panels read the same file the same way.
  function applyVpnAppsText(text) {
    var parsed = text === null ? null : VpnApps.parseAppsConfig(text)
    var error = parsed ? parsed.error : ""
    if (error !== "" && error !== vpnAppsError)
      console.warn("aranea network: ignoring " + Aranea.RuntimePaths.vpnAppsPath + ": " + error)
    vpnAppsError = error
    vpnAppsConfig = VpnApps.appsToApply(parsed)
  }

  // Starts the extras poll (devices, profiles, addresses), or marks it
  // dirty when one is running so it reads again afterwards.
  function runExtras() {
    if (extrasProc.running) {
      extrasDirty = true
    } else {
      // A read starting now covers every request so far.
      extrasDirty = false
      extrasProc.running = true
    }
  }

  // Applies the extras poll's output. Anything unparsable leaves empty
  // values; unchanged values aren't reassigned, so a quiet poll rebuilds
  // nothing.
  function updateExtras(raw) {
    var devices = []
    var connections = []
    var addrs = {}
    var links = []
    try {
      var parts = NetworkLogic.splitSections(raw)
      devices = NetworkLogic.parseDevices(parts[0])
      connections = NetworkLogic.parseConnections(parts[1])
      addrs = NetworkLogic.parseAddrs(parts[2])
      links = NetworkLogic.parseLinks(parts[2])
    } catch (e) {
      devices = []
      connections = []
      addrs = {}
      links = []
    }
    if (JSON.stringify(devices) !== JSON.stringify(extraDevices))
      extraDevices = devices
    if (JSON.stringify(connections) !== JSON.stringify(extraConnections))
      extraConnections = connections
    if (JSON.stringify(addrs) !== JSON.stringify(extraAddrs))
      extraAddrs = addrs
    if (JSON.stringify(links) !== JSON.stringify(extraLinks))
      extraLinks = links
    // A read that ran while a forget landed may predate it: read again,
    // and settle the forget and the SSID lookup only on a fresh read.
    var follow = NetworkLogic.extrasFollowUp(extrasDirty, savedForgetProc.running)
    extrasDirty = false
    if (follow.settle) {
      savedForgettingUuid = ""
      if (ssidLookupPending) {
        ssidLookupPending = false
        runSsidLookup()
      }
    }
    if (follow.rerun)
      extrasRerun.restart()
  }

  // Reads each saved Wi-Fi profile's SSID (its name can differ from it).
  function runSsidLookup() {
    if (ssidProc.running)
      return
    var uuids = []
    for (var i = 0; i < extraConnections.length; i++) {
      var c = extraConnections[i]
      if (c && c.type === "802-11-wireless" && c.uuid)
        uuids.push(c.uuid)
    }
    if (uuids.length === 0) {
      ssidByUuid = ({})
      return
    }
    // One line per uuid even when nmcli fails (an empty SSID, which
    // parseSsids skips), so a failure never glues two profiles together.
    ssidProc.command = ["bash", "-c", "for u; do printf '%s\\t%s\\n' \"$u\" \"$(nmcli -g 802-11-wireless.ssid connection show uuid \"$u\" 2>/dev/null)\"; done", "_"].concat(uuids)
    ssidProc.running = true
  }

  // Deletes the saved Wi-Fi profile on Saved row INDEX; the row breathes
  // ("Forgetting…") until the next extras read settles it.
  function forgetSaved(index) {
    var row = savedRows[index]
    if (!row || !row.key || savedForgetProc.running || savedForgettingUuid === row.key)
      return
    savedForgetFailedTimer.stop()
    savedForgetFailedUuid = ""
    savedForgettingUuid = row.key
    savedForgetProc.command = ["nmcli", "connection", "delete", "uuid", row.key]
    savedForgetProc.running = true
  }

  // Whether SECURITY is 802.1X (WPA/WPA2-EAP), stock's isEnterprise.
  function isEnterpriseSecurity(security) {
    return security === WifiSecurityType.Wpa2Eap || security === WifiSecurityType.WpaEap
  }

  // Connects the prompt's network with what was typed: stock's row
  // submitCredentials, moved to the root since the row is a pure view now.
  function submitCredentials() {
    var net = wifiNetworks[wifiIndexForSsid(passwordSsid)]
    if (!net || passwordSsid === "" || busy || passwordText.length === 0)
      return
    if (!isEnterpriseSecurity(net.security)) {
      connectWithPassphrase(net.ssid, passwordText)
      return
    }
    if (identityText.length > 0)
      connectEnterprise(net.ssid, identityText, passwordText)
  }

  // A Wi-Fi row's click (stock's NetworkRow semantics): connected
  // disconnects, secured and unknown opens the prompt, anything else
  // connects. Rows are disabled while an action runs.
  function wifiPrimary(index) {
    var net = wifiNetworks[index]
    if (!net || busy)
      return
    cursorActive = true
    focusSection = "wifi"
    selectedIndex = index
    wifiActionFocused = false
    chooseCursorRow("wifi")
    if (net.connected) {
      disconnectRow(net.ssid)
      return
    }
    if (requiresCredentials(net.security) && !net.known) {
      openPasswordPrompt(net.ssid)
      return
    }
    connectDirectly(net.ssid)
  }

  // Forgets Wi-Fi row INDEX when it's forgettable and nothing is running.
  function wifiForget(index) {
    var net = wifiNetworks[index]
    if (!net || busy || !canForgetNetwork(net))
      return
    forget(net)
  }

  // The view's interface rows (shown with two or more links).
  // With showcase names they take the names after the Wi-Fi and Saved
  // rows' (the offsets are read only then, so they never rebuild it).
  readonly property var interfaceRows: CursorLogic.keepRows(rowCache, "interfaces", Showcase.showcaseLabels(NetworkLogic.interfaceRows(extraDevices, extraAddrs), showcaseNames, "Network", showcaseNames.length > 0 ? wifiNetworks.length + savedRows.length : 0))
  // The view's Saved rows: saved Wi-Fi profiles not in the current scan;
  // showcase names after the Wi-Fi rows'.
  readonly property var savedRows: CursorLogic.keepRows(rowCache, "saved", Showcase.showcaseLabels(NetworkLogic.savedRows(extraConnections, ssidByUuid, wifiNetworks.map(function (n) {
    return n.ssid
  }), Date.now() / 1000), showcaseNames, "Network", wifiNetworks.length))
  // The view's Wi-Fi rows, from stock's wifiNetworks. Their own binding,
  // apart from networkView, so status, rates and the phrase never rebuild
  // them; a scan that changed nothing hands back the same array. Showcase
  // names relabel them in display order.
  readonly property var wifiViewRows: CursorLogic.keepRows(rowCache, "wifi", Showcase.showcaseLabels(wifiNetworks.map(function (net, i) {
    return {
      key: net.ssid,
      label: net.ssid,
      glyph: wifiIconFor(net.signal),
      title: wifiSectionTitle(i),
      secured: requiresCredentials(net.security),
      known: !!net.known,
      connected: !!net.connected,
      forgettable: canForgetNetwork(net),
      enterprise: isEnterpriseSecurity(net.security)
    }
  }), showcaseNames, "Network"))

  // Own-app VPN entries from the apps file (vpnAppsFile), for the status
  // line only: VPN control itself lives in araneadev.vpn.
  readonly property var vpnApps: vpnAppsConfig.apps || []
  // The names of VPNs currently up (VpnApps.upNames): activated
  // NetworkManager VPN/WireGuard connections from the extras poll, then
  // own-app entries, by name, whose detect.interface matches an up,
  // addressed link in extraLinks (no process polling here, so a
  // process-only or dual-detect app never shows as connected from Network).
  readonly property var vpnUpNames: VpnApps.upNames(extraConnections, vpnApps, extraLinks)
  // The VPN status line shown under the header, hidden ("") with nothing
  // up. With showcase names, the VPNs take stand-ins after the Wi-Fi,
  // Saved and interface rows' ("VPN N" past the list), never a real name.
  readonly property string vpnLine: VpnApps.statusLine(showcaseNames.length > 0 ? Showcase.showcaseLabels(vpnUpNames.map(function (name) {
    return {
      label: name
    }
  }), showcaseNames, "VPN", wifiNetworks.length + savedRows.length + interfaceRows.length).map(function (row) {
    return row.label
  }) : vpnUpNames)

  // The header title, as stock's heroSsid: "SSID (detail)", "Ethernet
  // (detail)", the interface, or "Disconnected" / "No connection". With
  // showcase names, the connected row's stand-in replaces the SSID.
  readonly property string heroTitle: {
    var title
    if (info.type === "wifi" && showcaseNames.length > 0)
      title = Showcase.connectedLabel(wifiViewRows) || "Wi-Fi"
    else if (info.type === "wifi")
      title = info.ssid || "Wi-Fi"
    else if (info.type === "ethernet")
      title = "Ethernet"
    else
      title = info.iface || (kind === "disconnected" ? "Disconnected" : "No connection")
    var detail = headerDetail()
    return detail !== "" ? title + " (" + detail + ")" : title
  }
  // The header caption, as stock's heroMeta: the rotating phrase while
  // connected, "NOT CONNECTED", or nothing.
  readonly property string heroCaption: {
    if (info.type === "wifi") {
      if (canDisconnect)
        return connectionPhrase.toUpperCase()
      if (kind === "disconnected")
        return "NOT CONNECTED"
      return ""
    }
    if (info.type === "ethernet")
      return connectionPhrase.toUpperCase()
    if (kind === "disconnected")
      return "NOT CONNECTED"
    return ""
  }
  // Tooltips for the DNS pills, as stock's.
  readonly property var dnsTooltips: ({
      DHCP: "Use DNS from DHCP",
      Cloudflare: "Set DNS to Cloudflare",
      Google: "Set DNS to Google",
      Custom: "Set custom DNS servers"
    })

  // The cursor's index within its section.
  function cursorIndexIn(section) {
    if (section === "header")
      return headerIndex
    if (section === "band")
      return bandIndex
    if (section === "dns")
      return dnsIndex
    if (section === "wifi")
      return selectedIndex
    if (section === "saved")
      return savedIndex
    return -1
  }

  // Everything the Aranea view draws (NetworkDropdown.view). Rates, the
  // graph, status, VPN state and the prompt are separate properties.
  readonly property var networkView: ({
      header: {
        glyph: icon,
        title: heroTitle,
        caption: heroCaption,
        canQr: canShareWifi,
        canSpeed: canRunSpeedTest,
        canToggle: canToggleWifi,
        wifiOn: Networking.wifiEnabled,
        toggleHint: toggleHint,
        scanning: scanning && wifiStationAvailable
      },
      interfaces: interfaceRows,
      vpnLine: vpnLine,
      band: {
        visible: canSelectBand,
        title: bandSectionTitle,
        auto: !bandPinned,
        currentLabel: bandLabel(bandCurrent),
        pillsVisible: bandPillsVisible,
        busy: bandBusy,
        options: bandAvailable.map(function (b) {
          return {
            key: b,
            label: bandLabel(b),
            tooltip: bandTooltip(b),
            selected: bandEffective === b
          }
        })
      },
      dns: {
        options: dnsProviders.map(function (p) {
          return {
            key: p,
            label: p,
            selected: dnsProvider === p,
            tooltip: dnsTooltips[p] || ""
          }
        })
      },
      wifi: {
        available: wifiStationAvailable,
        scanning: scanning,
        // Stock's rows were disabled while a Wi-Fi action runs.
        disabled: busy,
        rows: wifiStationAvailable ? wifiViewRows : []
      },
      saved: savedRows,
      cursor: {
        active: cursorActive && keyboardCursor,
        section: focusSection,
        index: cursorIndexIn(focusSection),
        action: focusSection === "wifi" ? wifiActionFocused : focusSection === "saved" ? savedActionFocused : false,
        bandAuto: bandAutoFocused
      },
      emptyText: networkManagerAvailable ? "" : "NetworkManager isn't running"
    })

  // The Link stats, formatted as stock's grid formats them
  // (NetworkLinkSection.stats).
  readonly property var statsView: ({
      visible: !!info.iface,
      receiving: hasTransferStats ? formatRate(downloadRate) : "--",
      sending: hasTransferStats ? formatRate(uploadRate) : "--",
      ping: formatPingLatency(internetPingLatency),
      loss: formatPacketLoss(internetPingPacketLoss),
      lossy: internetPingPacketLoss > 0,
      downloaded: hasTransferStats ? formatBytes(parseFloat(info.rx_bytes || "0")) : "--",
      uploaded: hasTransferStats ? formatBytes(parseFloat(info.tx_bytes || "0")) : "--",
      ip: info.ip || "--",
      gateway: info.gateway || "--"
    })

  // A Wi-Fi row's status, stock's NetworkRow statusText / isBusy / isFailed
  // keyed by SSID.
  function wifiStatusFor(net) {
    var ssid = net ? net.ssid : ""
    var isBusy = actionKind !== "" && actionSsid === ssid
    var isFailed = failureReason !== "" && failureSsid === ssid
    var isPasswordOpen = passwordSsid !== "" && passwordSsid === ssid
    var text = ""
    if (!net || isPasswordOpen)
      text = ""
    else if (isBusy && actionKind === "connect")
      text = "Connecting…"
    else if (isBusy && actionKind === "disconnect")
      text = "Disconnecting…"
    else if (isBusy && actionKind === "forget")
      text = "Forgetting…"
    else if (isFailed)
      text = failureReason || "Failed"
    else if (net.connected)
      text = "Connected"
    return {
      text: text,
      failed: isFailed,
      busy: isBusy
    }
  }

  // SSID -> {text, failed, busy} for every Wi-Fi row (NetworkDropdown.wifiStatus).
  readonly property var wifiStatusView: {
    var out = {}
    for (var i = 0; i < wifiNetworks.length; i++) {
      var net = wifiNetworks[i]
      if (net)
        out[net.ssid] = wifiStatusFor(net)
    }
    return out
  }

  // uuid -> {busy, failed, text} for the Saved rows
  // (NetworkDropdown.savedStatus, NetworkLogic.savedStatusMap).
  readonly property var savedStatusView: NetworkLogic.savedStatusMap(savedForgettingUuid, savedForgetFailedUuid)

  // The passphrase prompt (NetworkDropdown.prompt); ssid "" while closed.
  readonly property var promptView: {
    var net = passwordSsid !== "" ? wifiNetworks[wifiIndexForSsid(passwordSsid)] : null
    return {
      ssid: passwordSsid,
      enterprise: !!net && isEnterpriseSecurity(net.security),
      busy: passwordSsid !== "" && actionKind !== "" && actionSsid === passwordSsid,
      failed: passwordSsid !== "" && failureReason !== "" && failureSsid === passwordSsid,
      passphrase: passwordText,
      identity: identityText
    }
  }

  // Scrolls the keyboard cursor's row into the view's Wi-Fi/Saved scroll
  // area. Pointer moves leave the scroll position alone.
  function ensureCursorVisible() {
    if (!opened || !cursorActive || !keyboardCursor)
      return
    dropdown.ensureVisible(focusSection, cursorIndexIn(focusSection))
  }

  // Moves the cursor one row up (DY < 0) or down through header, band,
  // DNS, Wi-Fi and Saved, skipping whatever isn't on screen.
  function moveVerticalBy(dy) {
    var next = NetworkLogic.moveVertical({
      section: focusSection,
      index: cursorIndexIn(focusSection),
      bandAuto: bandAutoFocused
    }, dy, {
      header: headerActionCount,
      band: canSelectBand,
      bandPills: bandPillsVisible,
      wifi: wifiNetworks.length,
      saved: savedRows.length
    })
    if (next.section === "header" && focusSection !== "header")
      headerIndex = 0
    else if (next.section === "wifi")
      selectedIndex = next.index
    else if (next.section === "saved")
      savedIndex = next.index
    bandAutoFocused = next.bandAuto
    wifiActionFocused = false
    savedActionFocused = false
    focusSection = next.section
    // A keyboard move is a deliberate choice of the row it lands on.
    chooseCursorRow(next.section)
  }

  // Moves the cursor sideways within its section, with stock's helpers. A
  // pick in the header, band pills or DNS is a deliberate choice of what it
  // lands on (NetworkLogic.sidewaysChooses).
  function moveHorizontalBy(dx) {
    var section = focusSection
    var bandAuto = bandAutoFocused
    if (section === "header")
      selectHeaderByDelta(dx)
    else if (section === "band") {
      if (!bandAuto)
        selectBandByDelta(dx)
    } else if (section === "dns")
      selectDnsByDelta(dx)
    else if (section === "wifi")
      selectWifiActionByDelta(dx)
    else if (section === "saved" && savedIndex < savedRows.length)
      savedActionFocused = dx > 0
    if (NetworkLogic.sidewaysChooses(section, bandAuto))
      chooseCursorRow(section)
  }

  // Enter: activates whatever the cursor sits on, refusing a row that isn't
  // the one the user chose and can see. On Saved, Enter only moves onto the
  // forget action; on a Wi-Fi forget action it forgets, never anything else
  // (NetworkLogic.enterDecision).
  function activateCursor() {
    if (!cursorRowConfirmed(focusSection))
      return
    if (focusSection === "wifi") {
      var wifiDecision = NetworkLogic.enterDecision("wifi", wifiActionFocused, canForgetNetwork(wifiNetworks[selectedIndex]))
      if (wifiDecision === "forget")
        wifiForget(selectedIndex)
      else if (wifiDecision === "activate")
        activateSelected()
      else
        wifiActionFocused = false
    } else if (focusSection === "saved") {
      if (NetworkLogic.enterDecision("saved", savedActionFocused, true) === "forget")
        forgetSaved(savedIndex)
      else
        savedActionFocused = true
    } else if (focusSection === "header")
      activateHeader()
    else if (focusSection === "band")
      activateBand()
    else if (focusSection === "dns")
      activateDns()
  }

  // 'x': forgets the cursor's Wi-Fi row (when forgettable) or Saved row,
  // refusing a row the user didn't choose.
  function deleteCursor() {
    if (!cursorRowConfirmed(focusSection))
      return
    if (focusSection === "wifi")
      wifiForget(selectedIndex)
    else if (focusSection === "saved")
      forgetSaved(savedIndex)
  }

  // Whether a pointer action ARG ({index, key}) still names the row it was
  // reported for in ROWS (CursorLogic.rowKeyMatches).
  function pointerRowMatches(rows, arg) {
    return !!arg && CursorLogic.rowKeyMatches(rows, arg.index, arg.key)
  }

  // Carries out one NetworkDropdown action. Pointer actions hand the cursor
  // back from the keyboard; the prompt's own actions (typing, Enter, Esc)
  // are keyboard input and leave it alone.
  function handleAction(name, arg) {
    var promptKey = name === "promptSubmit" || name === "promptCancel" || name === "passphraseEdited" || name === "identityEdited"
    if (!promptKey)
      keyboardCursor = false
    if (name === "hover") {
      handleHover(arg)
      return
    }
    if (name === "qr")
      summonWifiQr()
    else if (name === "speed")
      summonSpeedTest()
    else if (name === "toggleWifi")
      toggleNetwork()
    else if (name === "copy")
      copyToClipboard(arg.value)
    else if (name === "openVpn")
      openVpnDropdown()
    else if (name === "bandAuto")
      toggleBandAuto()
    else if (name === "band")
      setBand(arg.key)
    else if (name === "dns")
      setDns(arg.key)
    else if (name === "wifiPrimary") {
      if (pointerRowMatches(wifiKeyRows(), arg))
        wifiPrimary(arg.index)
    } else if (name === "wifiForget") {
      if (pointerRowMatches(wifiKeyRows(), arg))
        wifiForget(arg.index)
    } else if (name === "savedForget") {
      if (pointerRowMatches(savedRows, arg))
        forgetSaved(arg.index)
    } else if (name === "promptSubmit" || name === "promptConnect")
      submitCredentials()
    else if (name === "promptCancel")
      cancelPasswordPrompt()
    else if (name === "passphraseEdited") {
      if (passwordSsid !== "" && arg.text !== passwordText)
        passwordText = arg.text
    } else if (name === "identityEdited") {
      if (passwordSsid !== "" && arg.text !== identityText)
        identityText = arg.text
    }
  }

  // A pointer hover: moves the cursor there, as stock's rows and pills did.
  // Leaving a forget button only drops the action focus on that row.
  function handleHover(arg) {
    if (arg.leave) {
      if (arg.section === "wifi" && focusSection === "wifi" && selectedIndex === arg.index)
        wifiActionFocused = false
      else if (arg.section === "saved" && focusSection === "saved" && savedIndex === arg.index)
        savedActionFocused = false
      return
    }
    if (arg.section === "header") {
      setHeaderCursor(arg.index)
      chooseCursorRow("header")
      return
    }
    cursorActive = true
    if (arg.section === "band") {
      if (arg.auto)
        bandAutoFocused = true
      else {
        bandIndex = arg.index
        bandAutoFocused = false
      }
    } else if (arg.section === "dns") {
      dnsIndex = arg.index
    } else if (arg.section === "wifi") {
      selectedIndex = arg.index
      wifiActionFocused = !!arg.action
    } else if (arg.section === "saved") {
      savedIndex = arg.index
      savedActionFocused = !!arg.action
    }
    focusSection = arg.section
    chooseCursorRow(arg.section)
  }

  // Additions to stock's open handler: a fresh open starts with the mouse's
  // (outline-free) cursor and asks for the saved SSIDs; a close drops the
  // Link history. When rows change, every keyed cursor follows the
  // network, profile, action or band it was put on
  // (CursorLogic.followCursor); when that's gone, the index is clamped
  // but the key dropped, so keyboard actions refuse rather than hit the
  // row that slid into its place.
  Connections {
    target: root
    function onOpenedChanged() {
      root.keyboardCursor = false
      root.savedActionFocused = false
      // Stand-in names never carry over into an open or past a close.
      root.showcaseNames = []
      if (root.opened) {
        root.ssidLookupPending = true
        // Stock's open handler puts the Wi-Fi cursor on row 0, a deliberate
        // placement, so that row is chosen (NetworkLogic.openChoice); with
        // no Wi-Fi rows nothing is until the user moves, hovers or clicks.
        // A keyboard reveal never chooses. Saved starts on its first row
        // too, followed until the user picks; the header and band take
        // theirs on a move, hover or click.
        var open = NetworkLogic.openChoice(root.wifiKeyRows())
        root.cursorChosenSection = open.chosen
        root.wifiCursorSsid = open.key
        root.savedIndex = 0
        root.savedCursorKey = root.savedRows.length > 0 ? root.savedRows[0].key : ""
        root.bandCursorKey = ""
        root.headerCursorKey = ""
      } else {
        root.linkHistory = []
      }
    }
    function onWifiNetworksChanged() {
      if (root.wifiNetworks.length === 0) {
        root.wifiCursorSsid = ""
        return
      }
      // An open prompt pins its own row, as stock's handler does.
      var key = root.passwordSsid !== "" ? root.passwordSsid : root.wifiCursorSsid
      var next = CursorLogic.followCursor(root.wifiKeyRows(), key, root.selectedIndex)
      root.selectedIndex = next.index
      root.wifiCursorSsid = next.key
      // A lost row, or one that can no longer be forgotten, drops the
      // forget focus, so Enter can't turn into a disconnect.
      if (!next.confirmed || !root.canForgetNetwork(root.wifiNetworks[next.index]))
        root.wifiActionFocused = false
    }
    function onSavedRowsChanged() {
      var next = CursorLogic.followCursor(root.savedRows, root.savedCursorKey, root.savedIndex)
      root.savedIndex = Math.max(0, next.index)
      root.savedCursorKey = next.key
      if (!next.confirmed)
        root.savedActionFocused = false
      if (root.focusSection === "saved" && root.savedRows.length === 0) {
        var fallback = NetworkLogic.savedEmptyFallback(root.wifiNetworks.length)
        root.focusSection = fallback.section
        if (fallback.section === "wifi") {
          root.selectedIndex = fallback.index
          root.wifiCursorSsid = fallback.key
          root.wifiActionFocused = false
        }
      }
    }
    function onBandAvailableChanged() {
      if (root.bandCursorKey === "auto")
        return
      var next = CursorLogic.followCursor(root.bandKeyRows(), root.bandCursorKey, root.bandIndex)
      if (next.index >= 0)
        root.bandIndex = next.index
      root.bandCursorKey = next.key
    }
    function onCanShareWifiChanged() {
      root.followHeaderCursor()
    }
    function onCanRunSpeedTestChanged() {
      root.followHeaderCursor()
    }
    function onCanToggleWifiChanged() {
      root.followHeaderCursor()
    }
  }

  // Keeps the header cursor on the action it was put on as actions appear
  // and vanish (stock only clamps the index).
  function followHeaderCursor() {
    var next = CursorLogic.followCursor(headerKeyRows(), headerCursorKey, headerIndex)
    if (next.index >= 0)
      headerIndex = next.index
    headerCursorKey = next.key
  }

  // Stock's per-row NetworkManager hooks, moved out of the stock row (the
  // Aranea rows are pure views): a failed connect from this panel reports
  // its reason and may reopen the prompt; state changes complete actions.
  Instantiator {
    model: root.wifiNetworks
    delegate: Connections {
      required property var modelData
      target: root.networkForSsid(modelData.ssid)
      function onConnectionFailed(reason) {
        // Background auto-connect retries fire this too; only reprompt for
        // the connect started from this panel. Checked before
        // failNetworkAction, which clears the action state.
        var ours = root.actionKind === "connect" && root.actionSsid === (modelData.ssid || "")
        root.failNetworkAction(root.networkForSsid(modelData.ssid), reason)
        if (ours && root.shouldRepromptPassphrase(reason, root.requiresCredentials(modelData.security)))
          root.openPasswordPrompt(modelData.ssid)
      }
      function onConnectedChanged() {
        root.checkActionCompletion(root.networkForSsid(modelData.ssid))
      }
      function onKnownChanged() {
        root.checkActionCompletion(root.networkForSsid(modelData.ssid))
      }
      function onStateChangingChanged() {
        root.checkActionCompletion(root.networkForSsid(modelData.ssid))
      }
    }
  }

  // Stock's row failureTimer: "Wrong password" shows for 2 s on the open
  // prompt, then the fields come back (and the passphrase takes focus).
  Timer {
    interval: 2000
    running: root.failureReason !== "" && root.passwordSsid !== "" && root.failureSsid === root.passwordSsid
    onTriggered: {
      root.failureSsid = ""
      root.failureReason = ""
    }
  }

  // Devices, connection profiles and IPv4 addresses in one shot, for the
  // Interfaces, VPN and Saved sections. Prints nothing without nmcli. A
  // request that arrived after the output was applied (a forget finishing
  // before the exit) only marked it dirty: the exit reads again.
  // qmllint disable signal-handler-parameters
  Process {
    id: extrasProc
    command: ["bash", "-c", "command -v nmcli >/dev/null 2>&1 || exit 0; nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device; echo ---; nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE,TIMESTAMP,STATE connection show; echo ---; ip -j -4 -br addr"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateExtras(text)
    }
    onExited: {
      if (NetworkLogic.extrasExitFollowUp(root.extrasDirty))
        extrasRerun.restart()
    }
  }
  // qmllint enable signal-handler-parameters

  // Re-reads the extras once the read that was running when another was
  // asked for has finished (see updateExtras).
  Timer {
    id: extrasRerun
    interval: 50
    onTriggered: {
      if (extrasProc.running)
        restart()
      else
        root.runExtras()
    }
  }

  // Polls extrasProc every 4 s while open (and once on open).
  Timer {
    interval: 4000
    repeat: true
    triggeredOnStart: true
    running: root.opened
    onTriggered: root.runExtras()
  }

  // Each saved Wi-Fi profile's SSID, as "uuid<TAB>ssid" lines.
  Process {
    id: ssidProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ssidByUuid = NetworkLogic.parseSsids(text)
    }
  }

  // The optional own-app VPN config file, read only for the status line
  // (root.vpnLine); a missing file reads as no apps. The directory is
  // watched too, since a FileView can't watch a file that doesn't exist yet
  // (araneadev.vpn does the same).
  FileView {
    id: vpnAppsFile
    path: Aranea.RuntimePaths.vpnAppsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyVpnAppsText(vpnAppsFile.text())
    onLoadFailed: root.applyVpnAppsText(null)
    onFileChanged: vpnAppsFile.reload()
  }
  FileView {
    path: Aranea.RuntimePaths.araneaConfigRoot
    watchChanges: true
    printErrors: false
    onFileChanged: vpnAppsFile.reload()
  }

  // Deletes a saved Wi-Fi profile, then re-reads profiles and SSIDs; a read
  // already running is followed by a fresh one (runExtras, extrasDirty). A
  // failed delete reads "Couldn't forget" on its row for 4 s.
  // qmllint disable signal-handler-parameters
  Process {
    id: savedForgetProc
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.savedForgetFailedUuid = root.savedForgettingUuid
        root.savedForgettingUuid = ""
        savedForgetFailedTimer.restart()
      }
      root.ssidLookupPending = true
      root.runExtras()
    }
  }
  // qmllint enable signal-handler-parameters

  // Clears a Saved forget failure after 4 s.
  Timer {
    id: savedForgetFailedTimer
    interval: 4000
    onTriggered: root.savedForgetFailedUuid = ""
  }

  // The Aranea view in the shared keyboard frame. The view pins the header
  // through DNS and scrolls Wi-Fi and Saved itself, so the frame only sizes
  // to it.
  Aranea.KeyboardPanelFrame {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(dropdown.implicitHeight)
    // Freeze the cursor model while the inline passphrase prompt is open;
    // its fields own input until Esc or Enter.
    blocked: root.passwordSsid !== ""
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      dropdown.disarmPointer()
      root.keyboardCursor = true
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      dropdown.disarmPointer()
      // The first key after opening or after mouse use only reveals the
      // cursor where it is; stock lets an upward first press move as well.
      var revealing = !root.cursorActive || !root.keyboardCursor
      root.cursorActive = true
      root.keyboardCursor = true
      // A reveal only shows the outline: it never chooses a row.
      if (!revealing || dy < 0) {
        if (dy !== 0)
          root.moveVerticalBy(dy)
        if (dx !== 0)
          root.moveHorizontalBy(dx)
      }
      Qt.callLater(root.ensureCursorVisible)
    }
    // Enter and x act only on a cursor the keyboard is showing; on one the
    // pointer placed (no outline) they only reveal it, as arrows do, and
    // the reveal chooses nothing. A row the user didn't choose is refused
    // (NetworkLogic.pressOutcome).
    onActivateRequested: {
      dropdown.disarmPointer()
      var outcome = NetworkLogic.pressOutcome(root.cursorTarget(root.focusSection), root.cursorActive, root.keyboardCursor)
      if (outcome === "ignore")
        return
      root.keyboardCursor = true
      if (outcome === "act")
        root.activateCursor()
      Qt.callLater(root.ensureCursorVisible)
    }
    onDeleteRequested: {
      dropdown.disarmPointer()
      var outcome = NetworkLogic.pressOutcome(root.cursorTarget(root.focusSection), root.cursorActive, root.keyboardCursor)
      if (outcome === "ignore")
        return
      root.keyboardCursor = true
      if (outcome === "act")
        root.deleteCursor()
      Qt.callLater(root.ensureCursorVisible)
    }
    onTextKey: function (t) {
      dropdown.disarmPointer()
      if (t === "r" || t === "R") {
        root.keyboardCursor = true
        root.refresh()
      } else if (t === "w" || t === "W") {
        root.keyboardCursor = true
        root.toggleNetwork()
      }
    }

    Item {
      anchors.fill: parent
      clip: true

      NetworkDropdown {
        id: dropdown
        width: parent.width
        captionOpacity: root.captionOpacity
        view: root.networkView
        stats: root.statsView
        graph: root.linkHistory
        wifiStatus: root.wifiStatusView
        savedStatus: root.savedStatusView
        prompt: root.promptView
        onAction: function (name, arg) {
          root.handleAction(name, arg)
        }
      }
    }
  }
}
