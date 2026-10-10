// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
// PanelWindow becomes creatable when Quickshell loads the Wayland backend.
// qmllint disable uncreatable-type
// Centered layer surface avoids dependence on compositor floating-window rules.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "ProjectsLogic.js" as Logic

PanelWindow {
  id: panel
  // Projects entry object supplied by the summoned host.
  required property var root
  // Unsaved drafts, wizard state and pending work prevent changing selection.
  readonly property bool navigationBlocked: surface.navigationBlocked
  // Current project destination, retained independently of window visibility.
  readonly property string section: surface.section
  // Refuse capture while action acceptance or activity work is pending.
  function captureBusy() {
    return surface.captureBusy()
  }
  // Activity observation follows the selected visible destination.
  readonly property bool activityVisible: surface.activityVisible
  // Desired size capped to the screen with 24-unit margins.
  readonly property var geometry: Logic.geometry(screen ? screen.width : 1920, screen ? screen.height : 1080, Style.spaceReal(1))
  // Give the first keyboard target focus on summon.
  function focusKeys() {
    surface.focusKeys()
  }
  // Select a known project only when no draft or operation would be hidden.
  function navigate(id) {
    return surface.navigate(id)
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
  // Remember the keyboard target for an already open Projects window.
  function captureFocus() {
    return surface.captureFocus()
  }
  visible: root.opened
  implicitWidth: geometry.width
  implicitHeight: geometry.height
  color: 'transparent'
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: 'aranea-projects'
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  ProjectsSurface {
    id: surface
    anchors.fill: parent
    root: panel.root
  }
}
