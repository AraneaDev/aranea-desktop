// Geometry-only custom widget: the production bar owns its clock anchor/peek.
import QtQuick

Item {
  // API injected into the custom clock slot by the production bar.
  property var bar: null
  implicitWidth: 80
  implicitHeight: 30
  Text {
    anchors.centerIn: parent
    text: "12:34"
    color: "white"
  }
}
