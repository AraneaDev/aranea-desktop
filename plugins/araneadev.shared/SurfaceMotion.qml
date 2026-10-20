// Presentation only: hosts retain logical visibility, focus and input ownership.
import QtQuick

Item {
  id: motion
  // Logical open state, independent of closing presentation frames.
  property bool opened: false
  // Shared preference; injectable for inert hosts and deterministic tests.
  property bool motionEnabled: MotionState.motionEnabled
  // Small scale change keeps large cards and text comfortable.
  property real closedScale: DesignTokens.surfaceClosedScale
  // Closing fades are shorter than opening feedback.
  property int fadeDuration: opened ? DesignTokens.settleDuration : DesignTokens.feedbackDuration
  // Hosts remain mapped only while there is visible presentation to draw.
  readonly property bool present: opened || opacity > 0
  // Capture hosts wait for both spatial and opacity motion to settle.
  readonly property bool running: scaleSpring.running || fade.running
  // Delay animation ownership until property initialization is complete.
  property bool ready: false

  opacity: 0
  scale: closedScale
  visible: false

  // Retarget from the current frame; reduced motion assigns exact final values.
  function update() {
    if (!ready)
      return
    var targetScale = opened ? 1 : closedScale
    var targetOpacity = opened ? 1 : 0
    if (!motionEnabled) {
      scaleSpring.stop()
      fade.stop()
      scale = targetScale
      opacity = targetOpacity
      return
    }
    if (scale !== targetScale || scaleSpring.running) {
      let currentScale = scale
      scaleSpring.stop()
      if (currentScale !== targetScale) {
        scaleSpring.from = currentScale
        scaleSpring.to = targetScale
        scaleSpring.start()
      }
    }
    if (opacity !== targetOpacity || fade.running) {
      fade.stop()
      fade.from = opacity
      fade.to = targetOpacity
      fade.start()
    }
  }

  onOpenedChanged: update()
  onMotionEnabledChanged: update()
  Component.onCompleted: {
    ready = true
    update()
  }

  SurfaceSpring {
    id: scaleSpring
    target: motion
    property: "scale"
    epsilon: 0.0001
  }
  NumberAnimation {
    id: fade
    target: motion
    property: "opacity"
    duration: motion.fadeDuration
    easing.type: Easing.OutCubic
  }
}
