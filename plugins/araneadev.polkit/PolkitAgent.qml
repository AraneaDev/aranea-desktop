// Aranea polkit prompt. Forked from Omarchy's polkit agent
// (shell/plugins/polkit): the flow handling, fingerprint mode, lid check and
// failure shake are stock; the card is Aranea's — mark, request, context line
// with the polkit action's own description, and details on Tab.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "PolkitLogic.js" as PolkitLogic

Item {
  id: root

  property string fontFamily: Style.font.menuFamily
  // Bound to the central [polkit] section in shell.toml via Color.qml.
  property color accent: Color.polkit.accent
  property color background: Color.polkit.background
  property color foreground: Color.polkit.text
  property color border: Color.polkit.border
  property color borderError: Color.polkit.borderError
  property var borderSpec: Border.surfaceSpec("polkit", errorFlash ? "border-error" : "border", errorFlash ? borderError : border, Math.max(1, Style.space(2)), "border-alpha")
  // Lock-grade dim: at least 0.72, whatever the theme's scrim alpha is.
  readonly property color scrim: Qt.rgba(Color.polkit.scrim.r, Color.polkit.scrim.g, Color.polkit.scrim.b, Math.max(Color.polkit.scrim.a, 0.72))
  readonly property color dim: Util.alpha(foreground, 0.58)
  readonly property real letterSpacing: 0.20
  readonly property string glyphSource: "file://" + (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/omarchy/current/theme/branding/marks/aranea-glyph.svg"
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int fieldHeight: Math.max(Style.space(42), Style.spacing.controlHeight)

  property bool closing: false
  property bool submitted: false
  property string currentMessage: ""
  property string currentPrompt: ""
  property string currentSupplementary: ""
  property bool supplementaryIsError: false
  property bool responseRequired: false
  property bool responseVisible: false
  property bool failed: false
  property bool errorFlash: false
  // pam_fprintd appears in the polkit PAM stack (a sensor is enrolled).
  property bool fingerprintConfigured: false
  // Lid shut right now — the reader is physically unreachable, so we fall back
  // to the password even when a sensor is enrolled. Refreshed per request.
  property bool laptopClosed: false
  property int shakeOffset: 0

  // Context for the current request.
  property string currentActionId: ""
  property string actionDescription: ""
  property string actionVendor: ""
  property string identityText: ""
  property string identityCount: ""
  property bool detailsOpen: false
  // The pkaction lookup in flight belongs to this cookie; a request that
  // starts while one is running waits for it (lookupQueued).
  property string lookupCookie: ""
  property bool lookupQueued: false

  readonly property bool dialogVisible: polkitAgent.isActive || closing
  // We show one method at a time. Fingerprint owns the dialog while PAM is
  // waiting on the reader (lid open, sensor enrolled); the moment PAM asks for
  // a password — including immediately when the lid is shut and the clamshell
  // gate skips pam_fprintd — we switch to the password field instead.
  readonly property bool fingerprintMode: fingerprintConfigured && !laptopClosed && dialogVisible && !responseRequired && !submitted && !errorFlash
  readonly property int cardWidth: Math.min(Style.space(380), Math.max(Style.space(260), panel.width - Style.gapsOut * 2))

  function loadPamConfig(raw) {
    fingerprintConfigured = PolkitLogic.fingerprintConfiguredFromPamConfig(raw)
  }

  function refreshLidState() {
    if (!laptopClosedProc.running) laptopClosedProc.running = true
  }

  function resetSnapshot() {
    currentMessage = ""
    currentPrompt = ""
    currentSupplementary = ""
    supplementaryIsError = false
    responseRequired = false
    responseVisible = false
    failed = false
    errorFlash = false
    submitted = false
    currentActionId = ""
    actionDescription = ""
    actionVendor = ""
    identityText = ""
    identityCount = ""
    detailsOpen = false
    passwordInput.text = ""
  }

  function syncIdentity() {
    var flow = polkitAgent.flow
    if (!flow) {
      identityText = ""
      identityCount = ""
      return
    }
    identityText = PolkitLogic.identityLabel(flow.selectedIdentity)
    identityCount = PolkitLogic.identityPosition(flow.identities, flow.selectedIdentity)
  }

  function syncFromFlow() {
    var flow = polkitAgent.flow
    if (!flow) return

    currentMessage = String(flow.message || "Authentication is needed...")
    currentPrompt = String(flow.inputPrompt || "")
    currentSupplementary = String(flow.supplementaryMessage || "")
    supplementaryIsError = !!flow.supplementaryIsError
    currentActionId = String(flow.actionId || "")
    responseRequired = !!flow.isResponseRequired
    responseVisible = !!flow.responseVisible
    failed = !!flow.failed
    syncIdentity()

    if (responseRequired) submitted = false
  }

  function startActionLookup() {
    if (actionLookup.running) {
      lookupQueued = true
      return
    }
    lookupQueued = false
    var flow = polkitAgent.flow
    var id = flow ? String(flow.actionId || "") : ""
    if (!flow || !PolkitLogic.validActionId(id)) return
    lookupCookie = String(flow.cookie || "")
    actionLookup.command = ["timeout", "2", "pkaction", "--action-id", id, "--verbose"]
    actionLookup.running = true
  }

  function beginFlow() {
    closeTimer.stop()
    closing = false
    submitted = false
    passwordInput.text = ""
    detailsOpen = false
    actionDescription = ""
    actionVendor = ""
    refreshLidState()
    syncFromFlow()
    startActionLookup()
    if (motionEnabled) openAnimation.restart()
    Qt.callLater(refocus)
  }

  function refocus() {
    if (!dialogVisible) return
    // In fingerprint mode there is no field to type into — park focus on the
    // key catcher so Escape still cancels; otherwise focus the password field.
    if (fingerprintMode) keyCatcher.forceActiveFocus()
    else passwordInput.forceActiveFocus()
  }

  function toggleDetails() {
    detailsOpen = !detailsOpen
    Qt.callLater(refocus)
  }

  function cycleIdentity() {
    var flow = polkitAgent.flow
    if (!flow || !flow.identities || flow.identities.length < 2) return
    var next = PolkitLogic.nextIdentityIndex(flow.identities.length, PolkitLogic.indexOfIdentity(flow.identities, flow.selectedIdentity))
    if (next >= 0) flow.selectedIdentity = flow.identities[next]
  }

  // One key map for every focus holder (field, key catcher, details text).
  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      cancelRequest()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (responseRequired) submitResponse()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab) {
      toggleDetails()
      event.accepted = true
    } else if (event.key === Qt.Key_Backtab) {
      cycleIdentity()
      event.accepted = true
    }
  }

  function submitResponse() {
    var flow = polkitAgent.flow
    if (!flow || !flow.isResponseRequired) return
    submitted = true
    errorFlash = false
    flow.submit(passwordInput.text)
    passwordInput.text = ""
    keyCatcher.forceActiveFocus()
  }

  function cancelRequest() {
    var flow = polkitAgent.flow
    passwordInput.text = ""
    submitted = false
    closing = true
    closeTimer.restart()
    if (flow) flow.cancelAuthenticationRequest()
  }

  function triggerFailureFeedback() {
    submitted = false
    errorFlash = true
    passwordInput.text = ""
    errorTimer.restart()
    shakeAnimation.restart()
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

  SequentialAnimation {
    id: shakeAnimation
    NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
  }

  // Lock-like entrance (scrim fade, card fade + slight scale), unless Aranea
  // motion is off (`off` in ~/.local/state/aranea/motion, or
  // ARANEA_REDUCED_MOTION=1).
  property bool motionEnabled: Quickshell.env("ARANEA_REDUCED_MOTION") !== "1"
  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/aranea/motion"
    watchChanges: true
    printErrors: false
    onLoaded: root.motionEnabled = String(text() || "").trim() !== "off"
    onFileChanged: reload()
  }
  ParallelAnimation {
    id: openAnimation
    NumberAnimation { target: scrimRect; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
    NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    NumberAnimation { target: card; property: "scale"; from: 0.97; to: 1; duration: 180; easing.type: Easing.OutCubic }
  }

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
    stdout: StdioCollector { id: laptopClosedOut; waitForEnd: true }
    onExited: root.laptopClosed = String(laptopClosedOut.text || "").trim() === "closed"
  }

  // The polkit action's own description and vendor. Never waited on: until
  // it answers (or when it fails) the context line shows the identity only.
  Process {
    id: actionLookup
    stdout: StdioCollector { id: actionLookupOut; waitForEnd: true }
    onExited: function(exitCode) {
      var flow = polkitAgent.flow
      // A result belongs to one request: drop it for a finished or newer one.
      if (flow && exitCode === 0 && String(flow.cookie || "") === root.lookupCookie) {
        var info = PolkitLogic.parseActionInfo(actionLookupOut.text)
        root.actionDescription = info.description
        root.actionVendor = info.vendor
      }
      if (root.lookupQueued) Qt.callLater(root.startActionLookup)
    }
  }

  PolkitAgent {
    id: polkitAgent
    path: "/org/omarchy/PolkitAgent"

    onAuthenticationRequestStarted: root.beginFlow()
    onIsActiveChanged: {
      if (isActive) root.syncFromFlow()
      else if (!root.closing) root.resetSnapshot()
    }
    onIsRegisteredChanged: {
      if (isRegistered) console.log("aranea polkit agent registered")
      else console.warn("aranea polkit agent is not registered; another agent may be running")
    }
  }

  Connections {
    target: polkitAgent.flow

    function onIsResponseRequiredChanged() {
      root.syncFromFlow()
      if (!polkitAgent.flow || !polkitAgent.flow.isResponseRequired) passwordInput.text = ""
      Qt.callLater(root.refocus)
    }

    function onInputPromptChanged() { root.syncFromFlow() }
    function onResponseVisibleChanged() { root.syncFromFlow() }
    function onSupplementaryMessageChanged() { root.syncFromFlow() }
    function onSupplementaryIsErrorChanged() { root.syncFromFlow() }
    function onSelectedIdentityChanged() { root.syncIdentity() }
    function onFailedChanged() { root.syncFromFlow() }

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

  PanelWindow {
    id: panel
    visible: root.dialogVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: scrimRect
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.refocus()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(content.implicitHeight + card.contentTopInset + card.contentBottomInset, panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.shakeOffset
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: root.refocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }
      }

      ColumnLayout {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.space(10)

        // Header: the mark says this is the system asking.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          Image {
            Layout.preferredWidth: Style.space(22)
            Layout.preferredHeight: Style.space(22)
            source: root.glyphSource
            sourceSize: Qt.size(44, 44)
            fillMode: Image.PreserveAspectFit
            smooth: true
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: "AUTHENTICATION REQUIRED"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.weight: Font.Medium
              font.letterSpacing: root.letterSpacing
              elide: Text.ElideRight
            }
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: "SYSTEM // PRIVILEGED"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
              font.letterSpacing: root.letterSpacing
              elide: Text.ElideRight
            }
          }
        }

        // The request, command in the accent colour (polkit text escaped).
        Text {
          Layout.fillWidth: true
          textFormat: Text.StyledText
          text: PolkitLogic.requestMarkup(root.currentMessage, root.accent.toString())
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        // What polkit says the action is, and who is authenticating.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: PolkitLogic.contextLine(root.actionDescription, root.identityText, root.identityCount)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            text: (root.detailsOpen ? "▴" : "▾") + " DETAILS"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            font.letterSpacing: root.letterSpacing
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleDetails()
            }
          }
        }

        // Details: raw polkit data, selectable, hidden rows when empty.
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.detailsOpen
          spacing: Style.space(4)
          Repeater {
            model: PolkitLogic.detailRows(root.currentActionId, root.actionVendor, PolkitLogic.commandFromMessage(root.currentMessage), root.currentMessage)
            delegate: RowLayout {
              id: detailRow
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(10)
              Text {
                Layout.preferredWidth: Style.space(64)
                Layout.alignment: Qt.AlignTop
                textFormat: Text.PlainText
                text: detailRow.modelData.key
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
                font.letterSpacing: root.letterSpacing
              }
              TextEdit {
                Layout.fillWidth: true
                textFormat: TextEdit.PlainText
                text: detailRow.modelData.value
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: root.foreground
                selectionColor: Util.alpha(root.accent, 0.45)
                selectedTextColor: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) { root.handleKey(event) }
              }
            }
          }
        }

        // Password field (or the sensor in fingerprint mode).
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: root.fieldHeight
          radius: root.cornerRadius
          color: Util.alpha(root.foreground, 0.04)
          border.width: 1
          border.color: root.errorFlash ? Color.polkit.textError : Util.alpha(root.foreground, passwordInput.activeFocus ? 0.22 : 0.10)

          Row {
            visible: root.fingerprintMode
            anchors.centerIn: parent
            spacing: Style.space(10)
            OpticalGlyph {
              width: Math.round(root.fieldHeight * 0.55)
              height: width
              text: "󰈷"
              fontFamily: root.fontFamily
              fontSize: Math.round(root.fieldHeight * 0.55)
              color: root.errorFlash ? Color.polkit.textError : root.accent
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "TOUCH THE SENSOR"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
              font.letterSpacing: root.letterSpacing
            }
          }

          Row {
            visible: !root.fingerprintMode
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(10)

            Text {
              text: ""
              color: root.errorFlash ? Color.polkit.textError : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              width: Style.space(20)
              height: root.fieldHeight
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }

            Item {
              width: parent.width - Style.space(30)
              height: root.fieldHeight

              TextInput {
                id: passwordInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                activeFocusOnPress: true
                clip: true
                selectionColor: Util.alpha(root.accent, 0.45)
                selectedTextColor: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
                echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                color: root.errorFlash ? Color.polkit.textError : root.foreground
                cursorVisible: activeFocus && !root.submitted && !root.errorFlash
                readOnly: root.submitted || root.errorFlash
                enabled: root.dialogVisible
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) { root.handleKey(event) }
              }

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.errorFlash ? "Wrong" : (root.submitted ? "Checking..." : PolkitLogic.promptPlaceholder(root.currentPrompt))
                color: root.errorFlash ? Color.polkit.textError : root.foreground
                opacity: root.errorFlash ? 1 : 0.36
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                elide: Text.ElideRight
                visible: passwordInput.text.length === 0
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: passwordInput.forceActiveFocus()
              }
            }
          }
        }

        // PAM's own messages ("Sorry, try again", fingerprint hints).
        Text {
          Layout.fillWidth: true
          visible: root.currentSupplementary.length > 0
          textFormat: Text.PlainText
          text: root.currentSupplementary
          color: root.supplementaryIsError ? Color.polkit.textError : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Util.alpha(root.foreground, 0.10)
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.fingerprintMode ? "TAB DETAILS · ESC CANCEL" : "ENTER AUTHORIZE · TAB DETAILS · ESC CANCEL"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          font.letterSpacing: root.letterSpacing
          elide: Text.ElideRight
        }
      }
    }
  }
}
