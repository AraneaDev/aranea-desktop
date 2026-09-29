// Visual and input boundary for one bar module slot.
import QtQuick
import qs.Commons

Item {
  id: slot
  property string moduleId: ""
  property var widget: null
  property bool vertical: false
  property string position: "top"
  property bool openIndicatorVisible: false
  property real openIndicatorPosition: 0.5
  property color foreground: Color.bar.text
  property color urgent: Color.bar.active
  signal pressed(var slot)
  signal hoverChanged(bool hovered)
  signal dragStarted(var slot, var event)
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
    onPositionChanged: function (event) { if (pressed) slot.dragMoved(slot, event) }
  }
}
