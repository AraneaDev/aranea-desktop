// Aranea lock service: the plugin's "service" entry point (manifest.json),
// kept loaded by the Omarchy shell. A copy of Omarchy's own
// plugins/lock/Service.qml that renders LockView.qml instead of the stock
// view. Owns the Wayland session lock, password and fingerprint PAM, display
// blanking/waking, stranded-lock recovery after a shell restart, the lock
// preview window, and the "lock" IPC target (lock, isLocked, status,
// preview, hidePreview).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Plugin shell API, injected by the host after loading; not used in this file.
  property var shell: null
  // Omarchy install path for plugins that need it; not used in this file.
  property string omarchyPath: ""

  // User home directory ($HOME).
  readonly property string home: Quickshell.env("HOME")
  // ~/.local/state (fixed; $XDG_STATE_HOME is not consulted here).
  readonly property string stateHome: home + "/.local/state"
  // User that PAM authenticates ($USER, else $LOGNAME).
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  // Symlink to the current Omarchy wallpaper; resolved by refreshBackground().
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  // True from beginLock() until unlock: the shell wants the session locked.
  property bool lockRequested: false
  // True while a requested lock waits for screens to settle or appear before the session lock is taken.
  property bool pendingSessionLock: false
  // True while password PAM is checking a submitted password.
  property bool authenticatingPassword: false
  // True while fingerprint PAM is running.
  property bool fingerprintAuthenticating: false
  // Whether /etc/pam.d/omarchy-lock-password exists; locking is refused without it.
  property bool passwordPamConfigured: false
  // Whether the fingerprint PAM file exists and fprintd lists an enrolled finger for the user.
  property bool fingerprintConfigured: false
  // Whether the lock preview overlay (IPC preview) is shown; any click hides it.
  property bool previewVisible: false
  // Text currently typed into the lock view's field.
  property string enteredPassword: ""
  // Password submitted to PAM, answered on its prompt and cleared when the check ends.
  property string pendingPassword: ""
  // Error shown in the lock view after a failed password attempt; empty otherwise.
  property string failureMessage: ""
  // Failed password attempts since the lock began.
  property int failedAttempts: 0
  // Resolved path of the current wallpaper.
  property string backgroundPath: ""
  // Incremented whenever backgroundPath changes, to cache-bust the view's image.
  property int backgroundVersion: 0
  // Last lifecycle event logged by logEvent() (reported by IPC status).
  property string lastEvent: "init"
  // ISO timestamp of lastEvent.
  property string lastEventAt: ""
  // True when Hyprland reports a session lock this shell did not take (left over from a previous shell).
  property bool strandedLock: false
  // True once the stranded-lock check has a definitive answer; stops further checks.
  property bool strandedLockResolved: false

  // True when a lock is requested or the Wayland session lock is locked or secure.
  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  // True while either password or fingerprint authentication is running.
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating

  // Counts screens that have a name and a non-zero size (ignores placeholder outputs).
  function realScreenCount(): int {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0)
        count += 1
    }

    return count
  }

  // Returns true when at least one real screen exists.
  function hasRealScreen(): bool {
    return realScreenCount() > 0
  }

  // Marks the lock pending and (re)starts the stabilize and retry timers that call requestSessionLock().
  function queueSessionLock(): void {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running)
      logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running)
      pendingSessionLockTimer.start()
  }

  // Takes the Wayland session lock once a lock is requested, screens have stabilized and a real screen
  // exists; otherwise leaves it pending for the retry timer.
  function requestSessionLock(): void {
    if (!lockRequested || sessionLock.locked || sessionLock.secure)
      return
    if (sessionLockStabilizeTimer.running)
      return
    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen")
        logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running)
        pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  function checkStrandedLock(): void {
    if (strandedLockResolved || strandedLockCheckProc.running)
      return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  // Re-locks with this shell when a stranded lock was found, nothing is locked yet and PAM is ready.
  function recoverStrandedLock(): void {
    if (!strandedLock || locked || !passwordPamConfigured)
      return
    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  // Starts resolving the wallpaper symlink (updates backgroundPath when it changed).
  function refreshBackground(): void {
    if (!readlinkProc.running)
      readlinkProc.running = true
  }

  // Starts the check for fingerprint PAM plus an enrolled finger (updates fingerprintConfigured).
  function refreshFingerprintStatus(): void {
    if (!fingerprintCheckProc.running)
      fingerprintCheckProc.running = true
  }

  // Records event as lastEvent with a timestamp and logs it to the console.
  function logEvent(event: string): void {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  // Clears password, error and attempt state, stops fingerprint retries and aborts any active PAM.
  function resetAuthenticationState(): void {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintRetryTimer.stop()
    if (passwordPam.active)
      passwordPam.abort()
    if (fingerprintPam.active)
      fingerprintPam.abort()
  }

  // Starts a lock: refuses without password PAM, resets auth state, arms blanking, queues the session
  // lock and refreshes wallpaper and fingerprint status. Returns false if refused.
  function beginLock(): bool {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    resetAuthenticationState()
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function () {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  // Ends the lock after successful authentication: clears lock and auth state, releases the session
  // lock and wakes the display. No-op when not locked.
  function finishUnlock(): void {
    if (!root.locked && !lockRequested)
      return
    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
  }

  // Restarts the 5 s idle timer that blanks keyboard and display backlights, noting when it was armed.
  function armBlankTimer(): void {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  // Runs omarchy-system-wake and, while locked, re-arms the blank timer.
  function runWake(): void {
    if (!wakeProcess.running)
      wakeProcess.running = true
    if (lockRequested)
      armBlankTimer()
  }

  // Turns keyboard and display brightness off.
  function runBlank(): void {
    if (!blankProcess.running)
      blankProcess.running = true
  }

  // Starts password PAM for value while locked and idle; the password is answered on PAM's prompt.
  function submitPassword(value: string): void {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0)
      return
    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  // Answers the pending password when password PAM is active and asking for a response.
  function respondToPasswordPrompt(): void {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired)
      return
    passwordPam.respond(pendingPassword)
  }

  // Records a failed password attempt: clears the password, bumps failedAttempts, sets the message
  // and wakes the display.
  function handlePasswordFailure() {
    if (!lockRequested)
      return
    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  // Starts fingerprint PAM once the session lock is secure and a fingerprint is enrolled.
  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured)
      return
    if (fingerprintPam.active || fingerprintAuthenticating)
      return
    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  // Handles a finished fingerprint PAM run: unlocks on success, else retries after 250 ms if
  // fingerprint is still configured.
  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested)
      return
    if (result === PamResult.Success) {
      finishUnlock()
    } else if (fingerprintConfigured) {
      fingerprintRetryTimer.restart()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        passwordText: root.enteredPassword
        onPasswordTextEdited: function (password) {
          root.enteredPassword = password
        }
        onSubmitPassword: function (password) {
          root.submitPassword(password)
        }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
      }
    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      passwordText: ""
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function (result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested)
        return
      if (result === PamResult.Success)
        root.finishUnlock()
      else
        root.handlePasswordFailure()
    }

    onError: function (error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function (result) {
      root.handleFingerprintFinished(result)
    }

    onError: function (error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured)
        fingerprintRetryTimer.restart()
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector {
      id: fingerprintCheckStdout
      waitForEnd: true
    }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured)
        root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active)
        fingerprintPam.abort()
    }
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    onExited: function (exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2)
        return
      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword)
        root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved)
        remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested)
      return
    if (authenticatingPassword)
      idleBlankTimer.stop()
    else
      armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured)
      return
    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured)
        return "missing-pam"
      if (!root.locked && !root.beginLock())
        return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
