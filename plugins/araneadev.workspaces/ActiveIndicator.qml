// Decorative position only: workspace buttons keep their fixed hit targets.
import QtQuick
import "../araneadev.shared" as Aranea

Rectangle {
  id: marker
  // Active row index, -1 when the focused workspace has no bar slot.
  property int activeIndex: -1
  // Layout orientation and immutable slot geometry from the button grid.
  property bool vertical: false
  // Size of each fixed workspace button along the sliding axis.
  property real slotSize: 12
  // Gap between adjacent workspace buttons.
  property real slotSpacing: 1
  // Bar size across the sliding axis.
  property real crossSize: 32
  // Width of the decorative selection strand.
  property real thickness: 2
  // Logical host visibility and shared motion preference.
  property bool presented: true
  // Shared motion preference, overridable by inert fixtures.
  property bool motionEnabled: Aranea.MotionState.motionEnabled
  // Slot origin in the animated axis; absent slots stop and reset motion.
  readonly property real destination: Math.max(0, activeIndex) * (slotSize + slotSpacing) + (slotSize - (vertical ? height : width)) / 2
  // Whether the selection strand is still settling.
  readonly property bool running: position.running
  visible: presented && activeIndex >= 0
  width: vertical ? thickness : slotSize * 0.65
  height: vertical ? slotSize * 0.65 : thickness
  radius: thickness / 2
  x: vertical ? crossSize - thickness - 2 : position.value
  y: vertical ? position.value : crossSize - thickness - 2
  Aranea.SpringValue {
    id: position
    targetValue: marker.destination
    motionEnabled: marker.motionEnabled && marker.presented && marker.activeIndex >= 0
  }
}
