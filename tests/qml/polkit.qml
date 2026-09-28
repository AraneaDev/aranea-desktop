// Behaviour of the polkit prompt's non-visual entry (PolkitAgent.qml) with
// no window and no system-bus agent: a fake request (flow) and a fake view
// record what the prompt does. Keys go through handleKey like the window's:
// empty Enter nudges without submitting, Enter sends the typed password,
// Tab opens the details, Shift+Tab cycles identities and Esc cancels. The
// flow's signals drive the failure shake and the close. The hint names the
// keys, and a spoofed path never changes who the command runs as.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.polkit" as Polkit

ShellRoot {
  id: shell

  QmlTest {
    id: t
  }

  // Stands in for Quickshell's authentication flow.
  QtObject {
    id: fakeFlow
    property string message: "Authentication is needed to run `/tmp/x' as user tim (tim)' as the super user"
    property string inputPrompt: "Password: "
    property string supplementaryMessage: ""
    property bool supplementaryIsError: false
    property string actionId: "org.freedesktop.policykit.exec"
    property bool isResponseRequired: true
    property bool responseVisible: false
    property var identities: ["unix-user:tim", "unix-user:root", "unix-user:admin"]
    property var selectedIdentity: "unix-user:tim"
    property string cookie: "c1"
    property var submitted: []
    property int cancelled: 0

    // The authentication flow's outcome signals.
    signal authenticationFailed
    signal authenticationSucceeded
    signal authenticationRequestCancelled

    // Records a submitted response.
    function submit(text) {
      submitted = submitted.concat([text])
    }

    // Records a cancel.
    function cancelAuthenticationRequest() {
      cancelled += 1
    }
  }

  // Stands in for the prompt window: the typed password and recorded calls.
  QtObject {
    id: fakeView
    property string password: ""
    property var calls: []

    // Records a call by name.
    function record(name) {
      calls = calls.concat([name])
    }
    // The typed password.
    function passwordText() {
      return password
    }
    // Clears the typed password.
    function clearPassword() {
      password = ""
      record("clearPassword")
    }
    // Records a focus request for the password field.
    function focusField() {
      record("focusField")
    }
    // Records a focus request for the key catcher.
    function focusKeys() {
      record("focusKeys")
    }
    // Records the empty-Enter nudge.
    function nudge() {
      record("nudge")
    }
    // Records the failure shake.
    function shake() {
      record("shake")
    }
    // Records the entrance animation.
    function playOpen() {
      record("playOpen")
    }
  }

  Polkit.PolkitAgent {
    id: prompt
    windowEnabled: false
    agentEnabled: false
    view: fakeView
    flow: fakeFlow
    agentActive: true
  }

  // Sends a key through the prompt's key map; returns whether it was taken.
  function press(code, modifiers) {
    var event = {
      key: code,
      modifiers: modifiers || Qt.NoModifier,
      text: "",
      accepted: false
    }
    prompt.handleKey(event)
    return event.accepted
  }

  Component.onCompleted: {
    prompt.syncFromFlow()
    t.equal(prompt.identityTotal, 3, "identities counted")

    // Empty Enter: nudge, nothing submitted.
    fakeView.password = ""
    t.check(press(Qt.Key_Return), "Enter is taken")
    t.equal(fakeFlow.submitted, [], "empty Enter submits nothing")
    t.check(fakeView.calls.indexOf("nudge") >= 0, "empty Enter nudges")

    // With reduced motion the empty Enter does not animate.
    prompt.motionEnabled = false
    fakeView.calls = []
    press(Qt.Key_Return)
    t.equal(fakeView.calls.indexOf("nudge"), -1, "no nudge with reduced motion")
    t.equal(fakeFlow.submitted, [], "still nothing submitted")
    prompt.motionEnabled = true

    // Enter with a password sends it and clears the field.
    fakeView.password = "hunter2"
    press(Qt.Key_Enter)
    t.equal(fakeFlow.submitted, ["hunter2"], "Enter sends the typed password")
    t.check(prompt.submitted, "prompt waits for PAM")
    t.equal(fakeView.password, "", "field cleared after submit")

    // A failed attempt: error flash, shake, field cleared, ready to retry.
    fakeView.password = "typed-after"
    fakeView.calls = []
    fakeFlow.authenticationFailed()
    t.check(prompt.errorFlash, "a failure flashes the error border")
    t.check(fakeView.calls.indexOf("shake") >= 0, "a failure shakes the card")
    t.equal(fakeView.password, "", "a failure clears the field")
    t.check(!prompt.submitted, "a failure ends the wait for PAM")

    // Tab opens the details.
    t.check(!prompt.detailsOpen, "details start collapsed")
    press(Qt.Key_Tab)
    t.check(prompt.detailsOpen, "Tab opens the details")

    // Shift+Tab cycles identities and wraps.
    press(Qt.Key_Backtab, Qt.ShiftModifier)
    t.equal(fakeFlow.selectedIdentity, "unix-user:root", "next identity")
    press(Qt.Key_Backtab, Qt.ShiftModifier)
    press(Qt.Key_Backtab, Qt.ShiftModifier)
    t.equal(fakeFlow.selectedIdentity, "unix-user:tim", "identity wraps around")

    // Hint names Shift+Tab when there are several identities.
    t.check(prompt.hintText.indexOf("⇧TAB SWITCH IDENTITY") >= 0, "hint offers identity switching")

    // The spoofed path stays in the command; the target is the real one.
    t.equal(prompt.targetText, "as root", "spoof cannot change the target")

    // Success closes the prompt after the close delay.
    fakeFlow.authenticationSucceeded()
    t.check(prompt.closing, "success starts closing")
    t.waitFor(function () {
      return !prompt.closing
    }, 5000, "the close delay ends", function () {
      // Esc cancels the request.
      t.check(press(Qt.Key_Escape), "Esc is taken")
      t.equal(fakeFlow.cancelled, 1, "Esc cancels the request")
      t.check(prompt.closing, "Esc starts closing")
      t.done()
    })
  }
}
