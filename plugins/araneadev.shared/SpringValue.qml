// Interruptible spatial value; disabling motion stops and assigns the target.
import QtQuick

Item {
  id: controller
  // Host-owned destination in pixel or normalized units.
  property real targetValue: 0
  // Animated presentation value, never used as logical state.
  property real value: 0
  // Shared preference, injectable by test and capture hosts.
  property bool motionEnabled: MotionState.motionEnabled
  // Pixel distances need a looser tolerance than normalized fractions.
  property real epsilon: 0.25
  // Whether spatial presentation is still settling.
  readonly property bool running: animation.running
  // Construction starts at the initial target before observing changes.
  property bool ready: false
  visible: false

  // Restart at the current position because running springs cache their target.
  function update() {
    if (!ready)
      return
    if (!motionEnabled) {
      animation.stop()
      value = targetValue
      return
    }
    if (value !== targetValue || animation.running) {
      let currentValue = value
      animation.stop()
      if (currentValue !== targetValue) {
        animation.from = currentValue
        animation.to = targetValue
        animation.start()
      }
    }
  }
  onTargetValueChanged: update()
  onMotionEnabledChanged: update()
  Component.onCompleted: {
    // Start at the initial destination without replaying layout construction.
    value = targetValue
    ready = true
  }
  SurfaceSpring {
    id: animation
    target: controller
    property: "value"
    epsilon: controller.epsilon
  }
}
