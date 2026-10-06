// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
// PanelWindow becomes creatable when Quickshell loads the Wayland backend.
// qmllint disable uncreatable-type
// Centered layer surface avoids dependence on compositor floating-window rules.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "SettingsLogic.js" as Logic

PanelWindow {
  id: panel
  // Settings entry object supplied by the summoned host.
  required property var root
  // Desired size capped to the screen with 24-unit margins.
  readonly property var geometry: Logic.geometry(screen ? screen.width : 1920, screen ? screen.height : 1080, Style.spaceReal(1))
  // Give the first keyboard target focus on summon.
  function focusKeys() {
    surface.focusKeys()
  }
  // Snapshot local presentation for the scoped capture transaction.
  function captureSnapshot() {
    return surface.captureSnapshot()
  }
  // Restore local presentation without invoking an owner operation.
  function captureRestore(saved) {
    surface.captureRestore(saved)
  }
  // Reset the capture view after fixture acceptance.
  function captureReset(fixture) {
    surface.captureReset(fixture)
  }
  // Confirm visible artwork and layout have settled.
  function captureReady() {
    return visible && surface.captureReady()
  }
  // Remember the keyboard target for an already open Settings window.
  function captureFocus() {
    return surface.captureFocus()
  }
  visible: root.opened
  implicitWidth: geometry.width
  implicitHeight: geometry.height
  color: 'transparent'
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: 'aranea-settings'
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  SettingsSurface {
    id: surface
    anchors.fill: parent
    root: panel.root
  }
}
