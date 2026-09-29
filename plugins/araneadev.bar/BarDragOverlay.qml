// Drag ghost and candidate drop feedback for the bar.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

Item {
  id: overlay
  // Public contract member.
  property bool active: false
  // Public contract member.
  property url dragImageUrl: ""
  // Public contract member.
  property string barPosition: "top"
  // Public contract member.
  property bool vertical: barPosition === "left" || barPosition === "right"
  // Public contract member.
  property real sceneX: 0
  // Public contract member.
  property real sceneY: 0
  // Public contract member.
  property real targetX: 0
  // Public contract member.
  property real targetY: 0
  // Public contract member.
  property real targetWidth: 0
  // Public contract member.
  property real targetHeight: 0
  // Public contract member.
  property bool dropAfter: false
  // Public contract member.
  property color accent: Color.bar.active

  visible: active
  Image {
    visible: overlay.dragImageUrl !== ""
    source: overlay.dragImageUrl
    x: overlay.sceneX - width / 2
    y: overlay.sceneY - height / 2
    width: Style.space(32)
    height: Style.space(32)
    opacity: 0.78
    fillMode: Image.PreserveAspectFit
  }
  Rectangle {
    visible: overlay.targetWidth > 0 && overlay.targetHeight > 0
    color: overlay.accent
    opacity: 0.8
    width: overlay.vertical ? Style.space(3) : Style.space(2)
    height: overlay.vertical ? Style.space(2) : Style.space(3)
    x: overlay.vertical ? overlay.targetX : overlay.targetX + (overlay.dropAfter ? overlay.targetWidth : 0) - width / 2
    y: overlay.vertical ? overlay.targetY + (overlay.dropAfter ? overlay.targetHeight : 0) - height / 2 : overlay.targetY
  }
}
