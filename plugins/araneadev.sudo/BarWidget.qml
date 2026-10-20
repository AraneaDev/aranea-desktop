// Standalone presentation of Omarchy's native authenticated sudo toggle.
import QtQuick
import Quickshell

Item {
  id: root
  // Scoped bar API injected by the widget host.
  property var bar: null
  // Canonical registry and layout identity.
  property string moduleName: "araneadev.sudo"
  // Native per-indicator preferences retained by layout migration.
  property var settings: ({})
  // Keep the native inactive indicator visible without revealing its neighbors.
  readonly property bool revealInactiveIndicators: true
  // Actual upstream component loaded from the active Omarchy installation.
  readonly property url nativeSource: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/shell/plugins/bar/indicators/PasswordlessSudo.qml"
  // Native indicator interface; the upstream Loader owns its concrete type.
  readonly property var nativeIndicator: indicatorLoader.item
  // Native grant and expiry refreshes retain their existing signal contract.
  signal refreshRequested

  implicitWidth: nativeIndicator ? nativeIndicator.implicitWidth : 0
  implicitHeight: nativeIndicator ? nativeIndicator.implicitHeight : 0

  // Request an on-demand native status probe; upstream coalesces busy requests.
  function refresh() {
    refreshRequested()
  }
  // Customize only presentation and host wiring; authentication stays upstream.
  function injectIndicator() {
    var target = nativeIndicator
    if (!target)
      return
    target.indicatorBlock = "single"
    target.indicatorHost = root
    target.activeColor = "#ffffff"
    target.settings = root.settings.nativeSettings || ({})
    target.bar = root.bar
  }
  onBarChanged: injectIndicator()
  onSettingsChanged: injectIndicator()

  Loader {
    id: indicatorLoader
    anchors.fill: parent
    source: root.nativeSource
    onLoaded: root.injectIndicator()
  }
}
