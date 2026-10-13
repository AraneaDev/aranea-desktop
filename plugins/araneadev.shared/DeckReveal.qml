// Interruptible cockpit entrance; never owns input, visibility, or layout.
import QtQuick
import qs.Commons

Item {
  id: reveal
  // Logical presentation state supplied by the existing surface owner.
  property bool opened: false
  // Later deck sections start after this delay in milliseconds.
  property int delay: 0
  // Shared preference can be overridden by deterministic capture hosts.
  property bool motionEnabled: MotionState.motionEnabled
  // Presentation progress, separate from logical open and input state.
  property real progress: 0
  // Vertical artwork offset; input targets retain their fixed layout.
  readonly property real offset: (1 - progress) * Style.space(14)
  // Whether a delayed entrance sequence is still active.
  readonly property bool running: sequence.running
  // Defer transitions until component construction has completed.
  property bool ready: false
  visible: false

  // Retarget from the current frame; reduced motion cancels even pending delays.
  function update() {
    if (!ready)
      return
    sequence.stop()
    var destination = opened ? 1 : 0
    if (!motionEnabled) {
      progress = destination
      return
    }
    if (progress === destination)
      return
    pause.duration = opened && progress === 0 ? Math.max(0, delay) : 0
    travel.from = progress
    travel.to = destination
    travel.duration = opened ? 320 : 100
    sequence.start()
  }
  onOpenedChanged: update()
  onMotionEnabledChanged: update()
  Component.onCompleted: {
    ready = true
    update()
  }
  SequentialAnimation {
    id: sequence
    PauseAnimation {
      id: pause
    }
    NumberAnimation {
      id: travel
      target: reveal
      property: "progress"
      easing.type: Easing.OutCubic
    }
  }
}
