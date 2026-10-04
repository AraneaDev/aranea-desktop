// Behaviour contract for the presentational polkit components, in a real
// window with real key presses and pointer clicks. The password field is
// the shared Aranea.CredentialPrompt: it keeps the lock glyph and the
// placeholder, masks the typed password, emits authorize on Enter and
// cancel on Esc, and hands Tab/Shift+Tab to the window's key map. While the
// check runs it pulses busy and is read-only (no "Checking..." text); a
// failure shows "Wrong" in the error colour, read-only and unpulsed, and
// clearing it re-enables an empty field. Fingerprint mode swaps the field
// for the sensor prompt. The DETAILS toggle ignores a click within 300 ms of
// the card opening or shifting. No font-dependent sizes are asserted.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.polkit" as PolkitComponents
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }

  // How many times the field emitted authorize.
  property int authorizes: 0
  // How many times the field emitted cancel.
  property int cancels: 0
  // Keys the field handed to the window's key map, in order.
  property var keys: []
  // How many times the card emitted detailsToggled.
  property int toggles: 0

  // Synthesizes pointer and key events (TestCase's mouse and key helpers),
  // never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  PolkitComponents.PolkitDetails {
    id: details
    rows: [
      {
        key: "Action",
        value: "org.example.test"
      }
    ]
  }

  FloatingWindow {
    implicitWidth: 420
    implicitHeight: 600
    visible: true

    Column {
      x: 20
      y: 20
      width: 380
      spacing: 20

      PolkitComponents.PolkitAuthField {
        id: field
        width: 380
        fieldHeight: 44
        errorColor: "#ff3355"
        accent: "#33ffaa"
        placeholderText: "Password"
        onAuthorize: authorizes += 1
        onCancel: cancels += 1
        onKeyPressed: function (event) {
          if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            keys = keys.concat([event.key])
            event.accepted = true
          }
        }
      }

      PolkitComponents.PolkitPromptCard {
        id: card
        width: 380
        currentMessage: "Authentication is needed to run `/usr/bin/true' as the super user"
        onDetailsToggled: toggles += 1
      }
    }
  }

  // The password input inside the shared prompt.
  function input() {
    return t.findChild(field, "passwordField")
  }

  // Runs [delay, fn] steps in order.
  function run(steps) {
    if (!steps.length)
      return
    t.step(steps[0][0], function () {
      steps[0][1]()
      run(steps.slice(1))
    })
  }

  Component.onCompleted: {
    t.equal(details.rows.length, 1, "polkit details expose their row model")
    t.equal(details.rows[0].value, "org.example.test", "polkit details preserve row values")
    run([[150, function () {
          t.check(t.findChild(field, "promptPanel") !== null, "the field is the shared CredentialPrompt")
          field.focusField()
        }], [50, function () {
          var pw = input()
          t.check(pw.visible && pw.activeFocus, "focusField focuses the password input")
          t.equal(pw.echoMode, TextInput.Password, "the password is masked")
          t.equal(pw.placeholderText, "Password", "the placeholder is kept")
          var lock = t.findChild(field, "passwordGlyph")
          t.equal(lock.text, String.fromCodePoint(0xf023), "the lock glyph is kept")
          t.check(lock.visible, "the lock glyph shows")
          t.check(Qt.colorEqual(lock.color, "#33ffaa"), "the lock glyph wears the accent")
          t.check(!t.findChild(field, "connectButton").visible, "no connect button (Enter authorizes)")
          pointer.keyClick(Qt.Key_A)
          pointer.keyClick(Qt.Key_B)
        }], [50, function () {
          t.equal(field.passwordText, "ab", "typing reaches the field")
          t.check(input().displayText !== "ab", "and is echoed masked")
          pointer.keyClick(Qt.Key_Return)
          t.equal(authorizes, 1, "Enter emits authorize")
          pointer.keyClick(Qt.Key_Tab)
          t.equal(keys, [Qt.Key_Tab], "Tab goes to the window's key map (details)")
          t.check(input().activeFocus, "Tab leaves focus in the field")
          pointer.keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
          t.equal(keys, [Qt.Key_Tab, Qt.Key_Backtab], "Shift+Tab goes to the window's key map (identity)")
          pointer.keyClick(Qt.Key_Escape)
          t.equal(cancels, 1, "Esc emits cancel")

          // Checking: busy pulse, read-only, no text.
          field.clearPassword()
          field.submitted = true
        }], [50, function () {
          var pw = input()
          t.equal(field.passwordText, "", "clearPassword empties the field")
          t.check(pw.visible, "checking keeps the field in place")
          t.check(!t.findChild(field, "promptStatus").visible, "no status text replaces the field")
          t.check(pw.readOnly, "input is disabled while checking")
          t.check(pw.placeholderText.indexOf("Checking") < 0, "no Checking... text")
          var pulse = t.findChild(field, "promptPulse")
          t.equal(pulse.running, Aranea.DesignTokens.motionEnabled, "the field pulses while checking")
          t.check(t.findChild(field, "promptPanel").busy, "the shared prompt is busy")

          // A failure: read-only, "Wrong" in the error colour, no pulse.
          field.submitted = false
          field.errorFlash = true
        }], [50, function () {
          var pw = input()
          t.check(pw.readOnly, "input is disabled during the failure flash")
          t.equal(pw.placeholderText, "Wrong", "the failure says Wrong")
          t.check(Qt.colorEqual(pw.placeholderTextColor, "#ff3355"), "in the error colour")
          t.check(Qt.colorEqual(t.findChild(field, "passwordGlyph").color, "#ff3355"), "the lock glyph turns the error colour")
          t.check(!t.findChild(field, "promptPulse").running, "no pulse during the failure")

          // The flash ends: an empty, writable field.
          field.errorFlash = false
          field.focusField()
        }], [50, function () {
          var pw = input()
          t.check(!pw.readOnly, "the field is re-enabled after the failure")
          t.equal(pw.text, "", "and empty")
          t.equal(pw.placeholderText, "Password", "with its placeholder back")
          t.check(!t.findChild(field, "promptPulse").running, "with no stuck pulse")
          t.check(pw.activeFocus, "and focused")
          pointer.keyClick(Qt.Key_C)
        }], [50, function () {
          t.equal(field.passwordText, "c", "a retry can be typed")
          field.responseVisible = true
        }], [50, function () {
          t.equal(input().echoMode, TextInput.Normal, "a visible response is not masked")
          field.fingerprintMode = true
        }], [50, function () {
          t.check(!t.findChild(field, "promptPanel").visible, "fingerprint mode hides the password field")
          var sensor = t.findChild(field, "fingerprintPrompt")
          t.check(sensor.visible, "fingerprint mode shows the sensor prompt")
          t.equal(t.findChild(field, "fingerprintGlyph").text, String.fromCodePoint(0xf0237), "with the fingerprint glyph")
          t.equal(field.height, 44, "at the field height")

          // DETAILS: a click right after opening is ignored, a settled one toggles.
          var link = t.findChild(card, "detailsToggle")
          t.equal(link.text, String.fromCodePoint(0x25be) + " DETAILS", "collapsed details point down")
          card.openedAt = Date.now()
          pointer.mouseClick(link)
          t.equal(toggles, 0, "a click within 300 ms of opening is ignored")
        }], [350, function () {
          pointer.mouseClick(t.findChild(card, "detailsToggle"))
          t.equal(toggles, 1, "a settled click toggles the details")
          card.detailsOpen = true
          card.layoutChangedAt = Date.now()
          t.equal(t.findChild(card, "detailsToggle").text, String.fromCodePoint(0x25b4) + " DETAILS", "open details point up")
          pointer.mouseClick(t.findChild(card, "detailsToggle"))
          t.equal(toggles, 1, "a click within 300 ms of a layout shift is ignored")
          t.done()
        }]])
  }
}
