// An authentication service publishes only its readiness/activity boolean.
import QtQuick

Item {
  id: guard
  // Authentication category: lock or polkit.
  property string kind: ''
  // Defaults to unsafe until the owning service reports readiness.
  property bool busy: true
  // Distinct registration prevents overlapping owners clearing each other.
  readonly property string key: Date.now() + '-' + Math.random().toString(16).slice(2)
  // Suppresses updates until this instance has completed construction.
  property bool registered: false

  onBusyChanged: if (registered)
    PluginReloadState.update(kind, key, busy)
  Component.onCompleted: {
    registered = true
    PluginReloadState.update(kind, key, busy)
  }
  Component.onDestruction: PluginReloadState.remove(kind, key)
}
