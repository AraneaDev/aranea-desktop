import Quickshell
import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "araneadev.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    fixedWidth: 30
    fixedHeight: root.bar ? root.bar.barSize : 32
    horizontalMargin: 0
    verticalPadding: 0
    tooltipText: "Aranea menu"

    Image {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -3
      width: 16
      height: 16
      source: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/unlock.png"
      sourceClipRect: Qt.rect(96, 85, 128, 144)
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
      enabled: false
    }

    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle araneadev.menu '{\"menu\":\"root\"}'")
    }
  }
}
