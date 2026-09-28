// Behaviour of the polkit prompt's non-visual entry (PolkitAgent.qml) with
// no window and no system-bus agent: a fake request (flow) and a fake view
// record what the prompt does. Empty Enter nudges without submitting, Enter
// sends the typed password, Shift+Tab cycles identities, the hint names the
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

  Component.onCompleted: {
    prompt.syncFromFlow()
    t.equal(prompt.identityTotal, 3, "identities counted")

    // Empty Enter: nudge, nothing submitted.
    fakeView.password = ""
    prompt.submitResponse()
    t.equal(fakeFlow.submitted, [], "empty Enter submits nothing")
    t.check(fakeView.calls.indexOf("nudge") >= 0, "empty Enter nudges")

    // With reduced motion the empty Enter does not animate.
    prompt.motionEnabled = false
    fakeView.calls = []
    prompt.submitResponse()
    t.equal(fakeView.calls.indexOf("nudge"), -1, "no nudge with reduced motion")
    t.equal(fakeFlow.submitted, [], "still nothing submitted")
    prompt.motionEnabled = true

    // Enter with a password sends it and clears the field.
    fakeView.password = "hunter2"
    prompt.submitResponse()
    t.equal(fakeFlow.submitted, ["hunter2"], "Enter sends the typed password")
    t.check(prompt.submitted, "prompt waits for PAM")
    t.equal(fakeView.password, "", "field cleared after submit")

    // Shift+Tab cycles identities and wraps.
    prompt.cycleIdentity()
    t.equal(fakeFlow.selectedIdentity, "unix-user:root", "next identity")
    prompt.cycleIdentity()
    prompt.cycleIdentity()
    t.equal(fakeFlow.selectedIdentity, "unix-user:tim", "identity wraps around")

    // Hint names Shift+Tab when there are several identities.
    t.check(prompt.hintText.indexOf("⇧TAB SWITCH IDENTITY") >= 0, "hint offers identity switching")

    // The spoofed path stays in the command; the target is the real one.
    t.equal(prompt.targetText, "as root", "spoof cannot change the target")

    // Esc cancels the request.
    prompt.cancelRequest()
    t.equal(fakeFlow.cancelled, 1, "Esc cancels the request")
    t.done()
  }
}
