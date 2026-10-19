// Independent authentication owners exercise cross-component reload guards.
import QtQuick
import "../araneadev.shared" as Shared

Item {
  id: owners
  // Controls whether a prompt service owner exists.
  property bool promptReady: true
  // Simulates an active lock session.
  property bool locked: false
  // Simulates an active authentication prompt.
  property bool authenticating: false
  Shared.PluginReloadGuard {
    kind: "lock"
    busy: parent.locked
  }
  Loader {
    active: owners.promptReady
    sourceComponent: Shared.PluginReloadGuard {
      kind: 'polkit'
      busy: owners.authenticating
    }
  }
}
