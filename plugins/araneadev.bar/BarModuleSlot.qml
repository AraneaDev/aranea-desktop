// Visual and input boundary for one bar module slot.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

Item {
  id: slot
  // Public contract member.
  property string moduleId: ""
  // Public contract member.
  property var widget: null
  // Public contract member.
  property bool vertical: false
  // Public contract member.
  property string position: "top"
  // Public contract member.
  property bool openIndicatorVisible: false
  // Public contract member.
  property real openIndicatorPosition: 0.5
  // Public contract member.
  property color foreground: Color.bar.text
  // Public contract member.
  property color urgent: Color.bar.active
  // Public contract member.
  signal pressed(var slot)
  // Public contract member.
  signal hoverChanged(bool hovered)
  // Public contract member.
  signal dragStarted(var slot, var event)
  // Public contract member.
  signal dragMoved(var slot, var event)

  implicitWidth: widget ? widget.implicitWidth : Style.space(24)
  implicitHeight: widget ? widget.implicitHeight : Style.space(24)

  Loader {
    anchors.fill: parent
    sourceComponent: slot.widget
  }

  Rectangle {
    visible: slot.openIndicatorVisible
    color: slot.urgent
    radius: height / 2
    width: slot.vertical ? Style.space(3) : Style.space(12)
    height: slot.vertical ? Style.space(12) : Style.space(3)
    x: slot.vertical ? (slot.width - width) / 2 : Math.max(0, Math.min(slot.width - width, slot.width * slot.openIndicatorPosition - width / 2))
    y: slot.vertical ? Math.max(0, Math.min(slot.height - height, slot.height * slot.openIndicatorPosition - height / 2)) : slot.height - height
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onEntered: slot.hoverChanged(true)
    onExited: slot.hoverChanged(false)
    onPressed: slot.pressed(slot)
    onPositionChanged: function (event) {
      if (pressed)
        slot.dragMoved(slot, event)
    }
  }
}
