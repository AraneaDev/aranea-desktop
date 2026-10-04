// The shared CredentialPrompt never keeps a typed secret it no longer
// shows: clearFields empties the fields and forgets every recorded text,
// and a field going away (its slot destroyed, or the fields rebuilt with
// other keys) drops its recorded text, so a rebuilt delegate can never
// hand a stale password to connect.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  id: host

  QmlTest {
    id: t
  }

  // The fields a Wi-Fi passphrase prompt shows.
  readonly property var wifiFields: [
    {
      key: "ssid",
      label: "Network",
      readOnly: true,
      value: "Home"
    },
    {
      key: "password",
      placeholder: "Password",
      secret: true
    }
  ]

  FloatingWindow {
    implicitWidth: 420
    implicitHeight: 200
    visible: true

    Aranea.CredentialPrompt {
      id: prompt
      x: 20
      y: 20
      width: 380
      fields: host.wifiFields
    }
  }

  Component.onCompleted: t.step(300, function () {
    var field = t.findChild(prompt, "passwordField")
    t.check(field !== null, "the password field is built")
    field.text = "hunter2"
    t.equal(prompt.texts.password, "hunter2", "typing records the field's text")
    prompt.clearFields()
    t.equal(field.text, "", "clearFields empties the field")
    t.equal(JSON.stringify(prompt.texts), "{}", "and forgets every recorded text")
    field.text = "secret-again"
    t.equal(prompt.texts.password, "secret-again", "typing records it again")
    prompt.fields = [
      {
        key: "code",
        placeholder: "2FA code"
      }
    ]
    t.step(100, function () {
      t.check(!("password" in prompt.texts), "a field that went away leaves no recorded text")
      t.check(t.findChild(prompt, "passwordField") === null, "and no field")
      t.done()
    })
  })
}
