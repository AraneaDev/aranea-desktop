// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
// PanelWindow becomes creatable when Quickshell loads the Wayland backend.
// qmllint disable uncreatable-type
// Centered layer surface avoids dependence on compositor floating-window rules.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../araneadev.shared" as Aranea
import qs.Commons
import "ProjectsLogic.js" as Logic

PanelWindow {
  id: panel
  // Projects entry object supplied by the summoned host.
  required property var root
  // Unsaved drafts, wizard state and pending work prevent changing selection.
  readonly property bool navigationBlocked: surface.navigationBlocked
  // External destinations use the same focused draft decision as local selection.
  readonly property bool hasUnsavedDraft: surface.hasUnsavedDraft
  // The compact switcher must not hide a setup wizard or an unsaved draft.
  readonly property bool switcherBlocked: surface.switcherBlocked
  // Current project destination, retained independently of window visibility.
  readonly property string section: surface.section
  // Refuse capture while action acceptance or activity work is pending.
  function captureBusy() {
    return surface.captureBusy()
  }
  // Activity observation follows the selected visible destination.
  readonly property bool activityVisible: surface.activityVisible
  // Desired size capped to the screen with 24-unit margins.
  readonly property var geometry: (root.mode === 'switcher' ? Logic.switcherGeometry : Logic.geometry)(screen ? screen.width : 1920, screen ? screen.height : 1080, Style.spaceReal(1))
  // Give the first keyboard target focus on summon.
  function focusKeys() {
    surface.focusKeys()
  }
  // Select a known project only when no draft or operation would be hidden.
  function navigate(id) {
    return surface.navigate(id)
  }
  // External bar inspection preserves exact checkout identity and local drafts.
  function inspectCheckout(projectId, checkoutId) {
    return surface.inspectCheckout(projectId, checkoutId)
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
    return surfaceMotion.opened && !surfaceMotion.running && surface.captureReady()
  }
  // Remember the keyboard target for an already open Projects window.
  function captureFocus() {
    return surface.captureFocus()
  }
  Aranea.SurfaceMotion {
    id: surfaceMotion
    opened: panel.root.opened
    motionEnabled: Aranea.MotionState.motionEnabled
  }

  visible: surfaceMotion.present
  onVisibleChanged: if (!visible)
    panel.root.closeFinished()
  // The compact switcher spans the screen so a click outside its card can close it.
  anchors.left: root.mode === 'switcher'
  anchors.right: root.mode === 'switcher'
  anchors.top: root.mode === 'switcher'
  anchors.bottom: root.mode === 'switcher'
  implicitWidth: geometry.width + Style.space(8)
  implicitHeight: geometry.height + Style.space(8)
  color: 'transparent'
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: 'aranea-projects'
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: surfaceMotion.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  // Closing frames never intercept pointer input.
  mask: Region {
    width: surfaceMotion.opened ? panel.width : 0
    height: surfaceMotion.opened ? panel.height : 0
  }
  ProjectsSurface {
    id: surface
    scale: surfaceMotion.scale
    opacity: surfaceMotion.opacity
    enabled: surfaceMotion.opened
    anchors.fill: parent
    // Reserve a small transparent gutter for spring overshoot.
    anchors.margins: Style.space(4)
    root: panel.root
  }
}
