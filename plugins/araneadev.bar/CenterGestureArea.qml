// Shared center-bar gesture surface for moving the bar and toggling
// transparency. Module registration remains owned by Bar.qml.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

MouseArea {
  id: gestureArea

  // Public contract member.
  property var bar: null
  // Public contract member.
  property bool dragging: false
  // Public contract member.
  property bool suppressClick: false
  // Public contract member.
  property real pressedX: 0
  // Public contract member.
  property real pressedY: 0
  // Public contract member.
  readonly property real dragThreshold: Style.space(4)

  acceptedButtons: Qt.LeftButton
  cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
  pressAndHoldInterval: 200

  // Starts a bar move and seeds its screen-space drag position.
  function startDrag(x, y) {
    if (dragging || !bar)
      return
    dragging = true
    bar.beginBarMove(bar.targetWindow(gestureArea))
    var scenePoint = gestureArea.mapToItem(null, x, y)
    bar.updateBarMove(bar.windowScreenPoint(scenePoint, bar.barMoveWindow))
  }

  onPressed: function (mouse) {
    dragging = false
    suppressClick = false
    pressedX = mouse.x
    pressedY = mouse.y
  }

  onPressAndHold: function (mouse) {
    // A widget above us can propagate its composed press-and-hold without
    // handing over the grab, so no release would otherwise end the move.
    if (!gestureArea.pressed)
      return
    startDrag(mouse.x, mouse.y)
  }

  onPositionChanged: function (mouse) {
    if (!(mouse.buttons & Qt.LeftButton))
      return
    if (!dragging) {
      var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
      if (distance < dragThreshold)
        return
      startDrag(mouse.x, mouse.y)
      return
    }

    var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
    bar.updateBarMove(bar.windowScreenPoint(scenePoint, bar.barMoveWindow))
  }

  onReleased: function (mouse) {
    if (!dragging || !bar)
      return
    dragging = false
    suppressClick = true
    bar.finishBarMove()
    mouse.accepted = true
  }

  onCanceled: {
    dragging = false
    suppressClick = false
    if (bar)
      bar.clearBarMove()
  }

  onClicked: function (mouse) {
    if (suppressClick) {
      suppressClick = false
      mouse.accepted = true
    }
  }

  onDoubleClicked: function (mouse) {
    if (suppressClick) {
      suppressClick = false
      return
    }
    if (mouse.button === Qt.LeftButton && bar) {
      bar.toggleTransparency()
      mouse.accepted = true
    }
  }
}
