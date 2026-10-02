// Aranea VPN bar widget (araneadev.vpn): the bar VPN icon and its dropdown.
// The root logic lives here: reading NetworkManager's VPN profiles
// (nmcli), the own-app VPNs file (~/.config/aranea/vpn-apps.json) and
// their links and processes, sessions, uptimes and traffic rates; the
// connect/disconnect processes and the credential prompt (secrets go to
// nmcli on stdin only); the keyed keyboard cursor; and IPC. The pure view,
// VpnDropdown, draws it in the shared keyboard frame. Every decision is a
// VpnLogic.js / VpnApps.js / CursorLogic.js rule, tested under Node.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "VpnLogic.js" as VpnLogic
import "../araneadev.shared/VpnApps.js" as VpnApps
import "../araneadev.shared/CursorLogic.js" as CursorLogic
import "../araneadev.shared/GraphLogic.js" as GraphLogic
import "../araneadev.shared/ShowcaseLogic.js" as Showcase
import "../araneadev.shared" as Aranea

Panel {
  id: root
  moduleName: "araneadev.vpn"
  ipcTarget: "aranea.vpn"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits, for the showcase methods below.
  manageIpc: false

  // Centralized close so callers can't forget to drop the prompt.
  function close() {
    root.controller.hide()
    cancelPrompt()
  }

  // ---------- State read from the system ----------

  // NetworkManager VPN and WireGuard profiles (VpnLogic.parseVpnConnections).
  property var conns: []
  // Whether the last connection read succeeded (nmcli present and
  // NetworkManager running).
  property bool nmOk: true
  // Whether a connection read has finished since the shell started.
  property bool listSeen: false
  // The parsed apps file: {apps, profiles} (VpnApps.parseAppsConfig).
  property var appsConfig: ({
      apps: [],
      profiles: {}
    })
  // The last apps-file error warned about, so each distinct one warns once.
  property string appsError: ""
  // Links from `ip -j addr` (VpnLogic.parseLinkOutput).
  property var links: []
  // Running process names among the apps' detect.process names.
  property var procs: []
  // Whether a link read has finished since the shell started.
  property bool linksSeen: false
  // uuid -> {ip, server, vpnType} (VpnLogic.parseSession), read on change.
  property var sessions: ({})
  // uuid -> whether it was connected at the last session check
  // (VpnLogic.sessionsToFetch).
  property var sessionSeen: ({})
  // uuids waiting for sessionProc, in order.
  property var sessionQueue: []
  // Row key -> when it came up (ms), or -1 for "since before open"
  // (VpnLogic.trackUptime).
  property var upSince: ({})
  // Whether the first full read (profiles, and links when apps exist) has
  // been synced; until then nothing is tracked.
  property bool synced: false
  // The keys connected at the last sync, for drop detection.
  property var prevConnectedKeys: []
  // Keys being turned off from the dropdown, so their disconnect isn't
  // taken for a drop; cleared once a sync shows them down.
  property var intentionalDown: []
  // The current time (ms) for uptimes, ticked while open.
  property real nowMs: Date.now()

  // ---------- Rates ----------

  // The last byte-counter reading (VpnLogic.parseCounters), or null.
  property var prevCounters: null
  // When prevCounters was read (ms).
  property real prevCountersAt: 0
  // Row key -> rate samples, oldest first (GraphLogic.pushSample, 40).
  // Cleared on close.
  property var graphs: ({})

  // ---------- The running action and failures ----------

  // The row key the running action is for, or "".
  property string actionKey: ""
  // "connecting" or "disconnecting" while an action runs.
  property string actionPhase: ""
  // When the running action started (ms), for the push-2FA text.
  property real actionStarted: 0
  // How long the running action has waited (ms), ticked while connecting.
  property real actionWaited: 0
  // Whether the running connect passes secrets on stdin.
  property bool actionWithSecrets: false
  // Whether the running action's process has started.
  property bool actionStartedOk: false
  // The secrets text (VpnLogic.secretsStdin) copied from the prompt at
  // submit for the running secrets connect, written to nmcli's stdin as it
  // starts and cleared right after; "" otherwise.
  property string actionSecret: ""
  // The row whose last action failed, for failedTimer's 4 s, or "".
  property string failedKey: ""
  // The failure's VpnLogic.statusText phase ("failedUp", "failedDown",
  // "failedOpen").
  property string failedPhase: ""
  // Whether the bar icon reads urgent (a failed connect or a drop, 4 s).
  property bool alertActive: false
  // The app row whose open command is being checked, or "".
  property string openingKey: ""
  // The argv the checked app opens with.
  property var openingArgv: []

  // ---------- The credential prompt ----------

  // The row key the prompt is open for, or "" while closed.
  property string promptKey: ""
  // The profile's username, shown read-only.
  property string promptUsername: ""
  // The password being typed. Cleared the moment the connect starts.
  property string promptPassword: ""
  // The optional 2FA code being typed. Cleared with the password.
  property string promptCode: ""
  // Whether the prompt's connect is running.
  property bool promptBusy: false
  // Whether the prompt shows its failure ("Couldn't connect, check password or code", 2 s).
  property bool promptFailed: false
  // The uuid the username read is for, or "".
  property string usernameKey: ""

  // ---------- Cursor ----------

  // Whether a cursor has been placed (a key press or a hover).
  property bool cursorActive: false
  // True while the keyboard drives the cursor; any pointer action clears
  // it. The view outlines the cursor only then.
  property bool keyboardCursor: false
  // The cursor's index across Connected then Available.
  property int cursorFlat: 0
  // The key of the row the cursor was deliberately put on (a move or a
  // hover; never a reveal or an open), followed across re-sorts and moves
  // between sections (CursorLogic.followCursor). "" refuses Enter.
  property string cursorKey: ""

  // ---------- Showcase ----------

  // Stand-in names for README screenshots (the showcase IPC method).
  property var showcaseNames: []
  // Fixture rows for README screenshots (the showcaseFixture IPC method),
  // or null; display-only, and actions are refused while it's set.
  property var fixture: null

  // ---------- Derived rows ----------

  // Row arrays kept by CursorLogic.keepRows, so an unchanged refresh hands
  // the view the same array and its Repeaters keep their delegates.
  property var rowCache: ({})
  // The apps from the apps file.
  readonly property var apps: appsConfig.apps || []
  // Whether NetworkManager has VPN profiles.
  readonly property bool hasProfiles: conns.length > 0
  // Whether the apps file lists any app.
  readonly property bool hasApps: apps.length > 0
  // Whether the bar icon shows at all.
  readonly property bool shown: hasProfiles || hasApps
  // The apps' detect.process names, for linkCommand.
  readonly property var processNames: {
    var out = []
    for (var i = 0; i < apps.length; i++) {
      var p = apps[i].detect ? apps[i].detect.process : ""
      if (p && out.indexOf(p) === -1)
        out.push(p)
    }
    return out
  }
  // App name -> VpnApps.appState.
  readonly property var appStates: {
    var out = {}
    for (var i = 0; i < apps.length; i++)
      out[apps[i].name] = VpnApps.appState(apps[i], links, procs)
    return out
  }
  // App name -> its matched interface (VpnApps.appInterface).
  readonly property var appInterfaces: {
    var out = {}
    for (var i = 0; i < apps.length; i++)
      out[apps[i].name] = VpnApps.appInterface(apps[i], links)
    return out
  }
  // App name -> the IPv4 address on its interface.
  readonly property var appIps: {
    var out = {}
    for (var name in appInterfaces)
      out[name] = VpnLogic.linkAddress(links, appInterfaces[name])
    return out
  }
  // Connected and Available, before labelling (VpnLogic.vpnRows).
  readonly property var builtRows: VpnLogic.vpnRows(conns, apps, appStates)
  // The real Connected rows (VpnLogic.viewRows).
  readonly property var connectedRows: CursorLogic.keepRows(rowCache, "connected", VpnLogic.viewRows(builtRows.connected, conns, sessions))
  // The real Available rows (VpnLogic.viewRows).
  readonly property var availableRows: CursorLogic.keepRows(rowCache, "available", VpnLogic.viewRows(builtRows.available, conns, sessions))
  // The rows the view and the cursor use: the fixture's while one is shown.
  readonly property var shownConnected: fixture ? fixture.connected : connectedRows
  // See shownConnected.
  readonly property var shownAvailable: fixture ? fixture.available : availableRows
  // Connected then Available, the cursor's flat order.
  readonly property var flatRows: shownConnected.concat(shownAvailable)
  // Row key -> interface for each connected row with one (rates, graphs).
  readonly property var rowIfaces: VpnLogic.rowInterfaces(connectedRows, conns, sessions, links, appInterfaces)
  // The interfaces rates are read for.
  readonly property var rateIfaces: {
    var out = []
    for (var k in rowIfaces)
      if (out.indexOf(rowIfaces[k]) === -1)
        out.push(rowIfaces[k])
    return out
  }
  // The bar icon's state (VpnLogic.iconState).
  readonly property string iconState: VpnLogic.iconState(connectedRows.length > 0, alertActive)

  // ---------- The view ----------

  // The cursor's section and row (VpnLogic.cursorPlace).
  readonly property var cursorAt: VpnLogic.cursorPlace(cursorFlat, shownConnected.length)
  // The cursor row's kind, for the key hint.
  readonly property string cursorKind: {
    var row = flatRows[cursorFlat]
    return row ? row.kind : ""
  }
  // Everything the view draws apart from the fast-changing properties.
  readonly property var vpnView: ({
      header: {
        glyph: String.fromCodePoint(0xf0582),
        caption: VpnLogic.headerCaption(shownConnected.length, flatRows.length),
        iconState: fixture ? VpnLogic.iconState(shownConnected.length > 0, false) : iconState
      },
      connected: shownConnected,
      available: shownAvailable,
      cursor: {
        active: cursorActive && keyboardCursor && flatRows.length > 0,
        section: cursorAt.section,
        index: cursorAt.index
      },
      emptyText: VpnLogic.emptyText(nmOk, flatRows.length),
      keyHint: VpnLogic.hintFor(promptKey !== "", cursorAt.section, cursorKind, flatRows.length > 0, cursorActive && CursorLogic.cursorConfirmed(flatRows, cursorKey, cursorFlat))
    })
  // Row key -> {text, busy, failed} (VpnLogic.statusMap).
  readonly property var statusView: fixture ? ({}) : VpnLogic.statusMap({
    key: actionKey,
    phase: actionPhase,
    waited: actionWaited
  }, {
    key: failedKey,
    phase: failedPhase,
    name: appFor(failedKey) ? appFor(failedKey).name : ""
  })
  // Row key -> {ip, server, up} (VpnLogic.sessionDetails).
  readonly property var sessionsView: fixture ? fixture.sessions : VpnLogic.sessionDetails(connectedRows, sessions, appIps, upSince, nowMs)
  // The credential prompt (VpnDropdown.prompt).
  readonly property var promptView: ({
      key: promptKey,
      username: promptUsername,
      password: promptPassword,
      code: promptCode,
      busy: promptBusy,
      failed: promptFailed,
      failedText: "Couldn't connect, check password or code"
    })

  // ---------- Reading ----------

  // Starts a connection read unless one is running.
  function runList() {
    if (!listProc.running)
      listProc.running = true
  }

  // Starts a link and process read unless one is running.
  function runLinks() {
    if (linkProc.running)
      return
    linkProc.command = VpnLogic.linkCommand(processNames)
    linkProc.running = true
  }

  // One poll: the connections, plus links when apps need detecting or an
  // open dropdown needs the tunnels' addresses.
  function poll() {
    runList()
    if (hasApps || (opened && hasProfiles))
      runLinks()
  }

  // Applies the apps file's text, or null when it's missing (no apps). A
  // file with any error is ignored as a whole (no apps, no profiles) and
  // warns once per distinct error.
  function applyAppsText(text) {
    var parsed = text === null ? null : VpnApps.parseAppsConfig(text)
    var error = parsed ? parsed.error : ""
    if (error !== "" && error !== appsError)
      console.warn("aranea vpn: ignoring " + Aranea.RuntimePaths.vpnAppsPath + ": " + error)
    appsError = error
    // Any error ignores the whole file (VpnApps.appsToApply, shared with
    // Network's status line).
    var next = VpnApps.appsToApply(parsed)
    if (JSON.stringify(next) !== JSON.stringify(appsConfig)) {
      appsConfig = next
      poll()
    }
  }

  // Reads the next queued session, if any.
  function runSessions() {
    if (sessionProc.running || sessionQueue.length === 0)
      return
    var uuid = sessionQueue[0]
    sessionQueue = sessionQueue.slice(1)
    sessionProc.uuid = uuid
    sessionProc.command = VpnLogic.sessionCommand(uuid)
    sessionProc.running = true
  }

  // After rows or connections change: queues session reads, tracks
  // uptimes, flags drops and keeps the prompt on a row that still needs it.
  function sync() {
    if (!listSeen || (hasApps && !linksSeen))
      return
    var fetch = VpnLogic.sessionsToFetch(sessionSeen, conns)
    sessionSeen = fetch.seen
    if (fetch.fetch.length > 0) {
      sessionQueue = sessionQueue.concat(fetch.fetch)
      runSessions()
    }
    var keys = connectedRows.map(function (r) {
      return r.key
    })
    var now = Date.now()
    nowMs = now
    upSince = VpnLogic.trackUptime(upSince, keys, now, !synced)
    if (synced && VpnLogic.droppedKeys(prevConnectedKeys, connectedRows, availableRows, intentionalDown).length > 0)
      raiseAlert()
    synced = true
    prevConnectedKeys = keys
    intentionalDown = intentionalDown.filter(function (k) {
      return keys.indexOf(k) !== -1
    })
    // The prompt closes once its row is up or gone.
    if (promptKey !== "" && !promptBusy && rowIndex(availableRows, promptKey) < 0)
      cancelPrompt()
  }

  // ROWS' index of KEY, or -1.
  function rowIndex(rows, key) {
    for (var i = 0; i < rows.length; i++)
      if (rows[i].key === key)
        return i
    return -1
  }

  // The real row for KEY in either section, or null.
  function rowFor(key) {
    var i = rowIndex(connectedRows, key)
    if (i >= 0)
      return connectedRows[i]
    i = rowIndex(availableRows, key)
    return i >= 0 ? availableRows[i] : null
  }

  // The NetworkManager profile behind KEY, or null.
  function connFor(key) {
    for (var i = 0; i < conns.length; i++)
      if (conns[i].uuid === key)
        return conns[i]
    return null
  }

  // The app behind row KEY ("app:" + name), or null.
  function appFor(key) {
    for (var i = 0; i < apps.length; i++)
      if ("app:" + apps[i].name === key)
        return apps[i]
    return null
  }

  // Turns the bar icon urgent for 4 s.
  function raiseAlert() {
    alertActive = true
    alertTimer.restart()
  }

  // Shows PHASE's failure text on row KEY for 4 s.
  function fail(key, phase) {
    failedKey = key
    failedPhase = phase
    failedTimer.restart()
  }

  // ---------- Actions ----------

  // Whether any action is running (one at a time, as in Network).
  readonly property bool busy: actionProc.running || usernameProc.running || whichProc.running

  // Runs nmcli ARGV as the action for KEY in PHASE.
  function startAction(key, phase, argv, withSecrets) {
    failedTimer.stop()
    failedKey = ""
    actionKey = key
    actionPhase = phase
    actionStarted = Date.now()
    actionWaited = 0
    actionWithSecrets = withSecrets
    actionStartedOk = false
    actionProc.stdinEnabled = withSecrets
    actionProc.command = argv
    actionProc.running = true
  }

  // Connects or disconnects NetworkManager row KEY.
  function toggleRow(key) {
    var conn = connFor(key)
    if (!conn || busy || fixture)
      return
    if (rowIndex(connectedRows, key) >= 0) {
      intentionalDown = intentionalDown.concat([key])
      startAction(key, "disconnecting", VpnLogic.disconnectCommand(key), false)
    } else {
      startAction(key, "connecting", VpnLogic.connectCommand(key, false), false)
    }
  }

  // Opens app row KEY's app once its binary is confirmed on PATH.
  function openAppRow(key) {
    var app = appFor(key)
    if (!app || busy || fixture || app.open.length === 0)
      return
    openingKey = key
    openingArgv = app.open
    whichProc.command = VpnLogic.whichCommand(app.open[0])
    whichProc.running = true
  }

  // Activates the row KEY: NetworkManager rows toggle, app rows open.
  function activateKey(key) {
    var row = rowFor(key)
    if (!row)
      return
    if (row.kind === "app")
      openAppRow(key)
    else
      toggleRow(key)
  }

  // Opens the prompt for KEY with USERNAME.
  function openPrompt(key, username) {
    promptKey = key
    promptUsername = username
    promptPassword = ""
    promptCode = ""
    promptBusy = false
    promptFailed = false
  }

  // Closes the prompt and drops whatever was typed.
  function cancelPrompt() {
    promptKey = ""
    promptUsername = ""
    promptPassword = ""
    promptCode = ""
    promptBusy = false
    promptFailed = false
    promptFailedTimer.stop()
  }

  // Connects the prompt's profile with the typed secrets (on stdin, see
  // actionProc.onStarted).
  // nmcli starts only with a non-empty password copied into actionSecret;
  // the prompt's fields are cleared at once, so the copy is the only one.
  function submitPrompt() {
    var conn = connFor(promptKey)
    if (!conn || busy || promptBusy || promptFailed || fixture || !VpnLogic.canStartSecrets(promptPassword))
      return
    promptBusy = true
    actionSecret = VpnLogic.secretsStdin(promptPassword, promptCode, VpnLogic.otpMode(appsConfig.profiles, conn.name))
    promptPassword = ""
    promptCode = ""
    startAction(promptKey, "connecting", VpnLogic.connectCommand(promptKey, true), true)
  }

  // Whether pointer action ARG ({index, key}) still names a row in either
  // section (CursorLogic.rowKeyMatches).
  function pointerRowMatches(arg) {
    return !!arg && (CursorLogic.rowKeyMatches(shownConnected, arg.index, arg.key) || CursorLogic.rowKeyMatches(shownAvailable, arg.index, arg.key))
  }

  // Carries out one VpnDropdown action. Pointer actions hand the cursor
  // back from the keyboard; the prompt's typing, Enter and Esc are
  // keyboard input and leave it alone.
  function handleAction(name, arg) {
    var promptKeyInput = name === "promptSubmit" || name === "promptCancel" || name === "passwordEdited" || name === "codeEdited"
    if (!promptKeyInput)
      keyboardCursor = false
    if (name === "hover") {
      if (!arg || !CursorLogic.rowKeyMatches(arg.section === "connected" ? shownConnected : shownAvailable, arg.index, arg.key))
        return
      cursorActive = true
      cursorFlat = arg.section === "connected" ? arg.index : shownConnected.length + arg.index
      cursorKey = arg.key
    } else if (name === "toggle" || name === "openApp") {
      // A click aimed at a row that changed underneath is refused.
      if (fixture || !pointerRowMatches(arg))
        return
      if (name === "toggle")
        toggleRow(arg.key)
      else
        openAppRow(arg.key)
    } else if (name === "promptSubmit" || name === "promptConnect") {
      submitPrompt()
    } else if (name === "promptCancel") {
      cancelPrompt()
    } else if (name === "passwordEdited") {
      if (promptKey !== "" && arg.text !== promptPassword)
        promptPassword = arg.text
    } else if (name === "codeEdited") {
      if (promptKey !== "" && arg.text !== promptCode)
        promptCode = arg.text
    }
  }

  // ---------- Keyboard ----------

  // Moves the cursor DY rows across Connected then Available; a move is a
  // deliberate choice of the row it lands on.
  function moveCursor(dy) {
    var next = VpnLogic.moveFlat(cursorFlat, dy, flatRows.length)
    if (next < 0)
      return
    cursorFlat = next
    cursorKey = flatRows[next].key
  }

  // Scrolls the keyboard cursor's row into view (Available only).
  function ensureCursorVisible() {
    if (!opened || !cursorActive || !keyboardCursor)
      return
    dropdown.ensureVisible(cursorAt.section, cursorAt.index)
  }

  // ---------- Lifecycle ----------

  onOpenedChanged: {
    keyboardCursor = false
    cursorActive = false
    // An open chooses nothing: Enter is refused until a move or hover.
    cursorFlat = 0
    cursorKey = ""
    // Stand-ins never carry over into an open or past a close.
    showcaseNames = []
    fixture = null
    if (opened) {
      nowMs = Date.now()
      poll()
    } else {
      cancelPrompt()
      graphs = ({})
      prevCounters = null
    }
  }

  // The keyboard cursor follows the row it was put on, across re-sorts and
  // between sections; a lost row drops the key, so Enter refuses.
  onFlatRowsChanged: {
    var next = CursorLogic.followCursor(flatRows, cursorKey, cursorFlat)
    cursorFlat = Math.max(0, next.index)
    cursorKey = next.key
    Qt.callLater(root.sync)
  }

  // Focus goes back to the key catcher when the prompt closes or starts
  // its connect (its fields hide), so arrows and Esc work without a click.
  onPromptKeyChanged: {
    if (promptKey === "" && opened)
      Qt.callLater(function () {
        if (panel.focusTarget)
          panel.focusTarget.forceActiveFocus()
      })
  }
  onPromptBusyChanged: {
    if (promptBusy && opened)
      Qt.callLater(function () {
        if (panel.focusTarget)
          panel.focusTarget.forceActiveFocus()
      })
  }

  Component.onCompleted: runList()

  // ---------- Processes ----------

  // The VPN profiles. `exec` keeps nmcli's own command line; a missing
  // nmcli exits 127.
  // qmllint disable signal-handler-parameters
  Process {
    id: listProc
    command: ["bash", "-c", "command -v nmcli >/dev/null 2>&1 || exit 127; exec nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE,STATE connection show"]
    stdout: StdioCollector {
      id: listOut
      waitForEnd: true
    }
    onExited: function (exitCode) {
      var ok = exitCode === 0
      var next = ok ? VpnLogic.parseVpnConnections(listOut.text) : []
      root.nmOk = ok
      if (JSON.stringify(next) !== JSON.stringify(root.conns))
        root.conns = next
      root.listSeen = true
      Qt.callLater(root.sync)
    }
  }

  // Links and running processes for the own-app VPNs (VpnLogic.linkCommand).
  Process {
    id: linkProc
    stdout: StdioCollector {
      id: linkOut
      waitForEnd: true
    }
    onExited: {
      var out = VpnLogic.parseLinkOutput(linkOut.text)
      if (JSON.stringify(out.links) !== JSON.stringify(root.links))
        root.links = out.links
      if (JSON.stringify(out.procs) !== JSON.stringify(root.procs))
        root.procs = out.procs
      root.linksSeen = true
      Qt.callLater(root.sync)
    }
  }

  // One profile's session fields (VpnLogic.sessionCommand), then the next.
  Process {
    id: sessionProc
    // The uuid being read.
    property string uuid: ""
    stdout: StdioCollector {
      id: sessionOut
      waitForEnd: true
    }
    onExited: function (exitCode) {
      var next = {}
      for (var k in root.sessions)
        next[k] = root.sessions[k]
      if (exitCode === 0)
        next[sessionProc.uuid] = VpnLogic.parseSession(sessionOut.text)
      root.sessions = next
      Qt.callLater(root.runSessions)
    }
  }

  // The prompt's username (vpn.data's username=, VpnLogic.parseUsername).
  Process {
    id: usernameProc
    stdout: StdioCollector {
      id: usernameOut
      waitForEnd: true
    }
    // The dropdown closing meanwhile leaves nowhere to prompt: the connect
    // reads as failed on its row and the bar icon (VpnLogic.promptOrFail).
    onExited: function (exitCode) {
      var key = root.usernameKey
      root.usernameKey = ""
      if (key === "")
        return
      if (VpnLogic.promptOrFail(root.opened, !!root.connFor(key)) === "prompt") {
        root.openPrompt(key, exitCode === 0 ? VpnLogic.parseUsername(usernameOut.text) : "")
      } else {
        root.fail(key, "failedUp")
        root.raiseAlert()
      }
    }
  }

  // Connects or disconnects one profile. A secrets connect always writes
  // the copy taken at submit (actionSecret) to nmcli's stdin (passwd-file
  // /dev/stdin) as it starts, clears it and only then closes stdin, so a
  // started nmcli always gets the submitted password; the secrets are
  // never in argv, logs or files. Closing the prompt or the dropdown in the
  // meantime doesn't cancel it: the connect goes ahead and its outcome
  // shows on the row (and the bar icon).
  Process {
    id: actionProc
    stderr: StdioCollector {
      id: actionErr
      waitForEnd: true
    }
    onStarted: {
      root.actionStartedOk = true
      if (!root.actionWithSecrets)
        return
      write(root.actionSecret)
      root.actionSecret = ""
      stdinEnabled = false
    }
    // A process that fails to start never emits exited.
    onRunningChanged: {
      if (!running && !root.actionStartedOk && root.actionKey !== "")
        root.finishAction(-1)
    }
    onExited: function (exitCode) {
      root.finishAction(exitCode)
    }
  }

  // Whether an app's open binary is on PATH (VpnLogic.whichCommand).
  Process {
    id: whichProc
    onExited: function (exitCode) {
      var key = root.openingKey
      root.openingKey = ""
      if (exitCode === 0)
        Quickshell.execDetached(root.openingArgv)
      else
        root.fail(key, "failedOpen")
    }
  }

  // The rates' byte counters (VpnLogic.countersCommand).
  Process {
    id: countersProc
    stdout: StdioCollector {
      id: countersOut
      waitForEnd: true
    }
    onExited: root.applyCounters(countersOut.text)
  }
  // qmllint enable signal-handler-parameters

  // Settles the running action with EXITCODE (-1: it never started).
  function finishAction(exitCode) {
    var key = actionKey
    var phase = actionPhase
    var withSecrets = actionWithSecrets
    var stderr = exitCode === -1 ? "" : actionErr.text
    // A secrets connect's secrets never outlive its process, whatever
    // happened; any other action leaves a half-typed password alone.
    if (VpnLogic.finishClearsSecrets(withSecrets, key, promptKey)) {
      promptPassword = ""
      promptCode = ""
    }
    actionKey = ""
    actionPhase = ""
    actionWithSecrets = false
    // The copy never outlives the process (one that never started included).
    actionSecret = ""
    if (phase === "disconnecting") {
      if (exitCode !== 0) {
        intentionalDown = intentionalDown.filter(function (k) {
          return k !== key
        })
        fail(key, "failedDown")
        raiseAlert()
      }
    } else {
      var outcome = VpnLogic.connectOutcome(exitCode, stderr, withSecrets)
      if (outcome === "ok") {
        if (promptKey === key)
          cancelPrompt()
      } else if (outcome === "prompt" && opened) {
        usernameKey = key
        usernameProc.command = VpnLogic.sessionCommand(key)
        usernameProc.running = true
      } else if (outcome === "wrong" && promptKey === key) {
        promptBusy = false
        promptFailed = true
        promptFailedTimer.restart()
        raiseAlert()
      } else {
        if (promptKey === key)
          cancelPrompt()
        fail(key, "failedUp")
        raiseAlert()
      }
    }
    runList()
  }

  // Turns a counters reading into rates and graph samples.
  function applyCounters(text) {
    if (!opened)
      return
    var counters = VpnLogic.parseCounters(text)
    var now = Date.now()
    var rates = VpnLogic.counterRates(prevCounters, counters, (now - prevCountersAt) / 1000)
    prevCounters = counters
    prevCountersAt = now
    var next = {}
    for (var key in rowIfaces) {
      var iface = rowIfaces[key]
      var rate = rates[iface]
      var hist = graphs[key] || []
      next[key] = rate ? GraphLogic.pushSample(hist, {
        iface: iface,
        rx: rate.rx,
        tx: rate.tx
      }, 40) : hist
    }
    graphs = next
  }

  // ---------- Timers ----------

  // The poll: every 2 s open, 5 s closed, stopped closed with nothing to
  // watch (VpnLogic.pollInterval).
  Timer {
    readonly property int every: VpnLogic.pollInterval(root.opened, root.hasProfiles, root.hasApps)
    interval: Math.max(1, every)
    repeat: true
    triggeredOnStart: true
    running: every > 0
    onTriggered: root.poll()
  }

  // While nothing is watched, a slow re-check notices a newly imported
  // profile or a newly created apps file.
  Timer {
    interval: 60000
    repeat: true
    running: VpnLogic.pollInterval(root.opened, root.hasProfiles, root.hasApps) === 0
    onTriggered: {
      root.runList()
      appsFile.reload()
    }
  }

  // Rates every 1.5 s while open, for the connected rows with an interface.
  Timer {
    interval: 1500
    repeat: true
    triggeredOnStart: true
    running: root.opened && root.rateIfaces.length > 0
    onTriggered: {
      if (countersProc.running)
        return
      countersProc.command = VpnLogic.countersCommand(root.rateIfaces)
      countersProc.running = true
    }
  }

  // Uptimes tick while open.
  Timer {
    interval: 15000
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  // The push-2FA text: how long the running connect has waited.
  Timer {
    interval: 1000
    repeat: true
    running: root.actionPhase === "connecting"
    onTriggered: root.actionWaited = Date.now() - root.actionStarted
  }

  // Clears a row's failure after 4 s.
  Timer {
    id: failedTimer
    interval: 4000
    onTriggered: root.failedKey = ""
  }

  // Clears the bar icon's alert after 4 s.
  Timer {
    id: alertTimer
    interval: 4000
    onTriggered: root.alertActive = false
  }

  // "Couldn't connect, check password or code" shows for 2 s, then the fields come back.
  Timer {
    id: promptFailedTimer
    interval: 2000
    onTriggered: root.promptFailed = false
  }

  // ---------- The apps file ----------

  // The optional apps file. A missing file reads as no apps; the
  // directory watch below notices it being created.
  FileView {
    id: appsFile
    path: Aranea.RuntimePaths.vpnAppsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyAppsText(appsFile.text())
    onLoadFailed: root.applyAppsText(null)
    onFileChanged: appsFile.reload()
  }

  // FileView can't watch a file that doesn't exist yet, so the directory
  // is watched too.
  FileView {
    path: Aranea.RuntimePaths.araneaConfigRoot
    watchChanges: true
    printErrors: false
    onFileChanged: appsFile.reload()
  }

  // ---------- IPC ----------

  IpcHandler {
    target: "aranea.vpn"

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
    // Screenshot stand-ins (scripts/capture-screenshots): NAMESJSON, a JSON
    // array of strings, relabels every row until the dropdown closes;
    // while it is closed the answer is "closed" and nothing is set.
    // Display only.
    function showcase(namesJson: string): string {
      var call = Showcase.showcaseCall(root.opened, namesJson)
      if (call.names !== null)
        root.showcaseNames = call.names
      return call.answer
    }
    // Screenshot fixture rows: ROWSJSON, a JSON array of {name, label,
    // kind, connected, ip, server, upMinutes}, replaces the rows until the
    // dropdown closes, so a capture works without real VPNs. Accepted only
    // while open; display only, and every action is refused meanwhile.
    function showcaseFixture(rowsJson: string): string {
      if (!root.opened)
        return "closed"
      var parsed = VpnLogic.parseFixture(rowsJson)
      if (parsed === null)
        return "invalid"
      root.cancelPrompt()
      root.fixture = parsed
      return "ok"
    }
  }

  // ---------- The bar icon and the dropdown ----------

  // Hidden (zero width) with no profiles and no apps; it stays laid out
  // while open so an IPC open still has an anchor.
  visible: shown || opened
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xf0582)
    foreground: root.iconState === "alert" ? Aranea.DesignTokens.urgent : root.iconState === "up" ? Aranea.DesignTokens.accent : Util.alpha(root.barForeground, 0.55)
    onPressed: {
      root.keyboardCursor = false
      root.toggle()
    }
  }

  Aranea.KeyboardPanelFrame {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(dropdown.implicitHeight)
    // The prompt's fields own input until Esc or Enter; once its connect
    // runs they hide, and the frame takes the keys back.
    blocked: root.promptKey !== "" && !root.promptBusy
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      dropdown.disarmPointer()
      root.keyboardCursor = true
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      dropdown.disarmPointer()
      // The first key after opening or after mouse use only reveals the
      // cursor where it is; a reveal never chooses a row.
      var revealing = !root.cursorActive || !root.keyboardCursor
      root.cursorActive = true
      root.keyboardCursor = true
      if (!revealing && dy !== 0)
        root.moveCursor(dy)
      Qt.callLater(root.ensureCursorVisible)
    }
    // Enter acts only on a cursor the keyboard is showing, on the row the
    // user chose and still sees (CursorLogic.pressIntent, cursorConfirmed);
    // a pointer-placed cursor is only revealed. Fixture rows never act.
    onActivateRequested: {
      dropdown.disarmPointer()
      var intent = CursorLogic.pressIntent(root.cursorActive, root.keyboardCursor)
      if (intent === "ignore")
        return
      root.keyboardCursor = true
      if (intent === "act" && !root.fixture && CursorLogic.cursorConfirmed(root.flatRows, root.cursorKey, root.cursorFlat))
        root.activateKey(root.cursorKey)
      Qt.callLater(root.ensureCursorVisible)
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

      VpnDropdown {
        id: dropdown
        width: parent.width
        view: root.vpnView
        status: root.statusView
        sessions: root.sessionsView
        graphs: root.fixture ? ({}) : root.graphs
        prompt: root.promptView
        showcaseNames: root.showcaseNames
        onAction: function (name, arg) {
          root.handleAction(name, arg)
        }
      }
    }
  }
}
