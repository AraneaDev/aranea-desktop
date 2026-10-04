// Aranea polkit prompt. Forked from Omarchy's polkit agent
// (shell/plugins/polkit): the flow handling, fingerprint mode, lid check and
// failure shake are stock; the card is Aranea's: mark, request, context line
// with the polkit action's own description, and details on Tab.
// Loaded by the Omarchy shell as the always-loaded service entry point of the
// araneadev.polkit plugin (manifest.json); it registers the polkit agent at
// /org/omarchy/PolkitAgent and shows a full-screen overlay per request.

import QtQuick
import Quickshell.Io
import qs.Commons
import "../araneadev.shared" as Aranea
import "PolkitLogic.js" as PolkitLogic

Item {
  id: root

  // Font for the card's text (the shell's menu font).
  property string fontFamily: Style.font.menuFamily
  // Bound to the central [polkit] section in shell.toml via Color.qml.
  property color accent: Color.polkit.accent
  // Card fill colour.
  property color background: Color.polkit.background
  // Main text colour.
  property color foreground: Color.polkit.text
  // Card border colour in the normal state.
  property color border: Color.polkit.border
  // Card border colour while the failure flash is on.
  property color borderError: Color.polkit.borderError
  // Border spec handed to BorderSurface; switches to the error border during errorFlash.
  property var borderSpec: Border.surfaceSpec("polkit", errorFlash ? "border-error" : "border", errorFlash ? borderError : border, Aranea.DesignTokens.borderWidth, "border-alpha")
  // Lock-grade dim: at least 0.72, whatever the theme's scrim alpha is.
  readonly property color scrim: Qt.rgba(Color.polkit.scrim.r, Color.polkit.scrim.g, Color.polkit.scrim.b, Math.max(Color.polkit.scrim.a, 0.72))
  // Secondary text colour: foreground at 58% alpha.
  readonly property color dim: Util.alpha(foreground, 0.58)
  // Letter spacing for the uppercase labels.
  readonly property real letterSpacing: 0.20
  // file:// URL of the Aranea glyph from the current theme's branding, shown in the header.
  readonly property string glyphSource: Aranea.RuntimePaths.glyphUrl
  // Corner radius of the card and the password field.
  readonly property int cornerRadius: Aranea.DesignTokens.cornerRadius
  // Padding inside the card.
  property int contentMargin: Style.spacing.panelPadding
  // Height of the password field (at least the shell's control height).
  property int fieldHeight: Math.max(Style.space(42), Style.spacing.controlHeight)

  // True while the close delay runs after success or cancel; keeps the dialog visible until resetSnapshot.
  property bool closing: false
  // A response was submitted and PAM has not asked again yet; the field pulses busy and is read-only.
  property bool submitted: false
  // The flow's request message ("Authentication is needed..." when polkit gives none).
  property string currentMessage: ""
  // PAM's input prompt, turned into the field placeholder.
  property string currentPrompt: ""
  // PAM's supplementary message, shown under the field.
  property string currentSupplementary: ""
  // The supplementary message is an error (shown in the error colour).
  property bool supplementaryIsError: false
  // PAM is waiting for a response; Enter submits only then.
  property bool responseRequired: false
  // The response may be echoed (not a secret), so the field shows plain text.
  property bool responseVisible: false
  // Failure feedback is on (red border and text, "Wrong", read-only field); errorTimer clears it after 1.2 s.
  property bool errorFlash: false
  // pam_fprintd appears in the polkit PAM stack (a sensor is enrolled).
  property bool fingerprintConfigured: false
  // Lid shut right now: the reader is physically unreachable, so we fall back
  // to the password even when a sensor is enrolled. Refreshed per request.
  property bool laptopClosed: false
  // When the current request started (Date.now()), settling DETAILS clicks.
  property real requestStartedAt: 0
  // Horizontal offset of the card, animated by shakeAnimation on failure.
  property int shakeOffset: 0

  // Context for the current request.
  property string currentActionId: ""
  // The polkit action's description from pkaction, "" until the lookup answers.
  property string actionDescription: ""
  // The polkit action's vendor from pkaction, shown in the details.
  property string actionVendor: ""
  // Label of the identity being authenticated as.
  property string identityText: ""
  // " (n of m)" suffix when there are several identities, else "".
  property string identityCount: ""
  // Number of identities the request offers; the hint shows Shift+Tab when above one.
  property int identityTotal: 0
  // The details rows are shown (toggled with Tab or the DETAILS link).
  property bool detailsOpen: false
  // The pkaction lookup in flight belongs to this cookie; a request that
  // starts while one is running waits for it (lookupQueued).
  property string lookupCookie: ""
  // A new lookup was requested while one was running; it starts when that one exits.
  property bool lookupQueued: false

  // The overlay is shown: a request is active or the close delay is running.
  readonly property bool dialogVisible: root.agentActive || closing
  // We show one method at a time. Fingerprint owns the dialog while PAM is
  // waiting on the reader (lid open, sensor enrolled); the moment PAM asks for
  // a password (including immediately when the lid is shut and the clamshell
  // gate skips pam_fprintd) we switch to the password field instead.
  readonly property bool fingerprintMode: fingerprintConfigured && !laptopClosed && dialogVisible && !responseRequired && !submitted && !errorFlash

  // Whether to create the on-screen window (PolkitWindow.qml); tests switch it off.
  property bool windowEnabled: true
  // Whether to register the system-bus agent (PolkitAgentService.qml); tests
  // switch it off and set flow and agentActive themselves.
  property bool agentEnabled: true
  // The registered agent, once created; null in tests.
  property var agent: null
  // The window (or a test's fake view): password text, focus and animations.
  property var view: null
  // The authentication flow being answered (the agent's, or a test's fake).
  property var flow: root.agent ? root.agent.flow : null
  // Whether a request is active (the agent's state, or set by a test).
  property bool agentActive: root.agent ? root.agent.isActive : false
  // Who the command runs as, on its own line ("as root"); never elided.
  readonly property string targetText: PolkitLogic.targetLine(root.currentMessage)
  // Key hint line for the current mode and identities.
  readonly property string hintText: PolkitLogic.hintLine(root.fingerprintMode, root.identityTotal)

  // The typed password (empty without a view).
  function passwordValue(): string {
    return root.view ? root.view.passwordText() : ""
  }

  // Clears the typed password.
  function clearPassword(): void {
    if (root.view)
      root.view.clearPassword()
  }

  // Gives the password field the keyboard focus.
  function focusField(): void {
    if (root.view)
      root.view.focusField()
  }

  // Gives the key catcher the keyboard focus.
  function focusKeys(): void {
    if (root.view)
      root.view.focusKeys()
  }

  // Plays the entrance animation.
  function playOpen(): void {
    if (root.view)
      root.view.playOpen()
  }

  // Shakes the card after a failed attempt.
  function shakeCard(): void {
    if (root.view)
      root.view.shake()
  }

  // Creates the object of FILE (a component next to this one) with this
  // entry as its `root`, or null (with a warning) when it cannot load.
  function createPart(file: string): var {
    var component = Qt.createComponent(Qt.resolvedUrl(file))
    if (component.status !== Component.Ready) {
      console.warn("polkit: " + file + " failed to load:", component.errorString())
      return null
    }
    return component.createObject(root, {
      root: root
    })
  }

  Component.onCompleted: {
    if (root.windowEnabled)
      root.view = root.createPart("PolkitWindow.qml")
    if (root.agentEnabled)
      root.agent = root.createPart("PolkitAgentService.qml")
  }

  // Sets fingerprintConfigured from the contents of /etc/pam.d/polkit-1.
  function loadPamConfig(raw) {
    fingerprintConfigured = PolkitLogic.fingerprintConfiguredFromPamConfig(raw)
  }

  // Starts the lid check (omarchy-hw-laptop-closed) unless one is already running; the result lands in laptopClosed.
  function refreshLidState() {
    if (!laptopClosedProc.running)
      laptopClosedProc.running = true
  }

  // Clears the request fields shown on the card and the password text (the
  // pkaction lookup state and the closing flag are left as they are).
  function resetSnapshot() {
    currentMessage = ""
    currentPrompt = ""
    currentSupplementary = ""
    supplementaryIsError = false
    responseRequired = false
    responseVisible = false
    errorFlash = false
    submitted = false
    currentActionId = ""
    actionDescription = ""
    actionVendor = ""
    identityText = ""
    identityCount = ""
    identityTotal = 0
    detailsOpen = false
    root.clearPassword()
  }

  // Refreshes identityText and identityCount from the flow's selected identity.
  function syncIdentity() {
    var flow = root.flow
    if (!flow) {
      identityText = ""
      identityCount = ""
      identityTotal = 0
      return
    }
    identityText = PolkitLogic.identityLabel(flow.selectedIdentity)
    identityCount = PolkitLogic.identityPosition(flow.identities, flow.selectedIdentity)
    identityTotal = flow.identities ? flow.identities.length : 0
  }

  // Copies the flow's message, prompt, supplementary text and flags into the root properties; a new response request clears submitted.
  function syncFromFlow() {
    var flow = root.flow
    if (!flow)
      return
    currentMessage = String(flow.message || "Authentication is needed...")
    currentPrompt = String(flow.inputPrompt || "")
    currentSupplementary = String(flow.supplementaryMessage || "")
    supplementaryIsError = !!flow.supplementaryIsError
    currentActionId = String(flow.actionId || "")
    responseRequired = !!flow.isResponseRequired
    responseVisible = !!flow.responseVisible
    syncIdentity()

    if (responseRequired)
      submitted = false
  }

  // Runs `pkaction --action-id <id> --verbose` (2 s timeout) for the current flow's action, or queues it when a lookup is running; invalid ids are skipped.
  function startActionLookup() {
    if (actionLookup.running) {
      lookupQueued = true
      return
    }
    lookupQueued = false
    var flow = root.flow
    var id = flow ? String(flow.actionId || "") : ""
    if (!flow || !PolkitLogic.validActionId(id))
      return
    lookupCookie = String(flow.cookie || "")
    actionLookup.command = ["timeout", "2", "pkaction", "--action-id", id, "--verbose"]
    actionLookup.running = true
  }

  // Prepares the dialog for a new request: resets state, checks the lid, syncs the flow, looks up the action, plays the open animation and focuses.
  function beginFlow() {
    requestStartedAt = Date.now()
    closeTimer.stop()
    closing = false
    submitted = false
    root.clearPassword()
    detailsOpen = false
    actionDescription = ""
    actionVendor = ""
    refreshLidState()
    syncFromFlow()
    startActionLookup()
    if (motionEnabled)
      root.playOpen()
    Qt.callLater(refocus)
  }

  // Puts keyboard focus on the password field, or on the key catcher in fingerprint mode; no-op when hidden.
  function refocus() {
    if (!dialogVisible)
      return
    // In fingerprint mode there is no field to type into; park focus on the
    // key catcher so Escape still cancels; otherwise focus the password field.
    if (fingerprintMode)
      root.focusKeys()
    else
      root.focusField()
  }

  // Shows or hides the details rows, then restores focus.
  function toggleDetails() {
    detailsOpen = !detailsOpen
    Qt.callLater(refocus)
  }

  // Selects the next identity of the flow (wrapping); no-op with fewer than two.
  function cycleIdentity() {
    var flow = root.flow
    if (!flow || !flow.identities || flow.identities.length < 2)
      return
    var next = PolkitLogic.nextIdentityIndex(flow.identities.length, PolkitLogic.indexOfIdentity(flow.identities, flow.selectedIdentity))
    if (next >= 0)
      flow.selectedIdentity = flow.identities[next]
  }

  // One key map for every focus holder (field, key catcher, details text).
  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      cancelRequest()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      authorize()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab) {
      toggleDetails()
      event.accepted = true
    } else if (event.key === Qt.Key_Backtab) {
      cycleIdentity()
      event.accepted = true
    }
  }

  // Enter (from the key map or the password field's own Enter): submits
  // only while PAM waits for a response.
  function authorize() {
    if (responseRequired)
      submitResponse()
  }

  // Sends the typed password to the flow when PAM wants a response, clears
  // the field and parks focus on the key catcher; an empty field only nudges
  // (an empty attempt would count toward faillock).
  function submitResponse() {
    var flow = root.flow
    if (!flow || !flow.isResponseRequired)
      return
    if (root.passwordValue().length === 0) {
      root.nudge()
      return
    }
    submitted = true
    errorFlash = false
    flow.submit(root.passwordValue())
    root.clearPassword()
    root.focusKeys()
  }

  // A small shake that says "type something first"; none when motion is off.
  function nudge() {
    if (root.motionEnabled && root.view)
      root.view.nudge()
  }

  // Cancels the request and starts the close delay.
  function cancelRequest() {
    var flow = root.flow
    root.clearPassword()
    submitted = false
    closing = true
    closeTimer.restart()
    if (flow)
      flow.cancelAuthenticationRequest()
  }

  // Shows a failed attempt: error flash, cleared field, shake, then refocus.
  function triggerFailureFeedback() {
    submitted = false
    errorFlash = true
    root.clearPassword()
    errorTimer.restart()
    root.shakeCard()
    Qt.callLater(refocus)
  }

  Timer {
    id: closeTimer
    interval: 300
    repeat: false
    onTriggered: {
      closing = false
      resetSnapshot()
    }
  }

  Timer {
    id: errorTimer
    interval: 1200
    repeat: false
    onTriggered: root.errorFlash = false
  }

  // Lock-like entrance (scrim fade, card fade + slight scale), unless Aranea
  // motion is off (shared Aranea.MotionState).
  property bool motionEnabled: Aranea.MotionState.motionEnabled

  FileView {
    path: "/etc/pam.d/polkit-1"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPamConfig(text())
    onLoadFailed: root.fingerprintConfigured = false
    onFileChanged: reload()
  }

  Process {
    id: laptopClosedProc
    command: ["bash", "-c", "omarchy-hw-laptop-closed && echo closed || echo open"]
    stdout: StdioCollector {
      id: laptopClosedOut
      waitForEnd: true
    }
    onExited: root.laptopClosed = String(laptopClosedOut.text || "").trim() === "closed"
  }

  // The polkit action's own description and vendor. Never waited on: until
  // it answers (or when it fails) the context line shows the identity only.
  Process {
    id: actionLookup
    stdout: StdioCollector {
      id: actionLookupOut
      waitForEnd: true
    }
    onExited: function (exitCode) {
      var flow = root.flow
      // A result belongs to one request: drop it for a finished or newer one.
      if (flow && exitCode === 0 && String(flow.cookie || "") === root.lookupCookie) {
        var info = PolkitLogic.parseActionInfo(actionLookupOut.text)
        root.actionDescription = info.description
        root.actionVendor = info.vendor
        // The details rows were rebuilt; a clicked value that held focus is
        // gone, so hand focus back to the field or key catcher.
        if (root.detailsOpen)
          Qt.callLater(root.refocus)
      }
      if (root.lookupQueued)
        Qt.callLater(root.startActionLookup)
    }
  }

  Connections {
    target: root.flow

    function onIsResponseRequiredChanged() {
      root.syncFromFlow()
      if (!root.flow || !root.flow.isResponseRequired)
        root.clearPassword()
      Qt.callLater(root.refocus)
    }

    function onInputPromptChanged() {
      root.syncFromFlow()
    }
    function onResponseVisibleChanged() {
      root.syncFromFlow()
    }
    function onSupplementaryMessageChanged() {
      root.syncFromFlow()
    }
    function onSupplementaryIsErrorChanged() {
      root.syncFromFlow()
    }
    function onSelectedIdentityChanged() {
      root.syncIdentity()
    }
    function onFailedChanged() {
      root.syncFromFlow()
    }

    function onAuthenticationFailed() {
      root.syncFromFlow()
      root.triggerFailureFeedback()
    }

    function onAuthenticationSucceeded() {
      root.closing = true
      closeTimer.restart()
    }

    function onAuthenticationRequestCancelled() {
      root.closing = true
      closeTimer.restart()
    }
  }
}
