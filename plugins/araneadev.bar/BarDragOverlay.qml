// Drag ghost and candidate drop feedback for the bar.
import QtQuick
import qs.Commons

Item {
  id: overlay
  property bool active: false
  property url dragImageUrl: ""
  property string barPosition: "top"
  property bool vertical: barPosition === "left" || barPosition === "right"
  property real sceneX: 0
  property real sceneY: 0
  property real targetX: 0
  property real targetY: 0
  property real targetWidth: 0
  property real targetHeight: 0
  property bool dropAfter: false
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
