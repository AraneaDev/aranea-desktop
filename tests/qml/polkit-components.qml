// Behaviour contract for presentational polkit components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.polkit" as PolkitComponents

ShellRoot {
  QmlTest {
    id: t
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

  PolkitComponents.PolkitAuthField {
    id: authField
    fingerprintMode: true
    fieldHeight: 44
    submitted: false
    dialogVisible: true
  }

  Component.onCompleted: {
    t.equal(details.rows.length, 1, "polkit details expose their row model")
    t.equal(details.rows[0].key, "Action", "polkit details preserve row keys")
    t.equal(details.rows[0].value, "org.example.test", "polkit details preserve row values")
    t.equal(authField.fingerprintMode, true, "polkit auth fields expose fingerprint mode")
    t.equal(authField.fieldHeight, 44, "polkit auth fields expose field sizing")
    t.done()
  }
}
