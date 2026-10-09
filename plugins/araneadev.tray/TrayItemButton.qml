// Tray input shared by native pointer events and the bar's drag/click router.
import QtQuick

Item {
  id: button
  // The StatusNotifierItem shown by this button.
  required property var modelData
  // Host bar API used for tooltips and click registration.
  property var bar: null
  // Host currently holding this button in its click registry.
  property var registeredBar: null
  // Whether the native pointer is hovering this visible icon.
  readonly property bool tooltipHovered: visible && opacity > 0 && pointer.containsMouse
  // Request the app menu with coordinates local to this icon.
  signal menuRequested(var mouse)
  // Forward native hover entry to the tray tooltip host.
  signal hoverEntered
  // Forward native hover exit to the tray tooltip host.
  signal hoverExited

  // Dispatch a completed native click or a click forwarded by the bar.
  function triggerPress(mouseButton, mouse) {
    if (button.bar)
      button.bar.hideTooltip(button)
    if (mouseButton === Qt.RightButton || (mouseButton === Qt.LeftButton && button.modelData.onlyMenu))
      button.menuRequested(mouse || {
        x: button.width / 2,
        y: button.height / 2
      })
    else if (mouseButton === Qt.MiddleButton)
      button.modelData.secondaryActivate()
    else if (mouseButton === Qt.LeftButton)
      button.modelData.activate()
  }

  // Move this icon between host click registries when the bar changes.
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget)
      registeredBar.unregisterClickTarget(button)
    registeredBar = bar
    if (registeredBar && registeredBar.registerClickTarget)
      registeredBar.registerClickTarget(button)
  }
  onBarChanged: syncClickRegistration()
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget)
    registeredBar.unregisterClickTarget(button)

  MouseArea {
    id: pointer
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: button.hoverEntered()
    onExited: button.hoverExited()
    onClicked: function (mouse) {
      button.triggerPress(mouse.button, mouse)
    }
    onWheel: function (wheel) {
      button.modelData.scroll(wheel.angleDelta.y, false)
    }
  }
}
