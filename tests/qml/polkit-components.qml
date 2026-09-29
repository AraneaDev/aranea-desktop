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
    rows: [{ key: "Action", value: "org.example.test" }]
  }

  Component.onCompleted: {
    t.equal(details.rows.length, 1, "polkit details expose their row model")
    t.equal(details.rows[0].key, "Action", "polkit details preserve row keys")
    t.equal(details.rows[0].value, "org.example.test", "polkit details preserve row values")
    t.done()
  }
}
