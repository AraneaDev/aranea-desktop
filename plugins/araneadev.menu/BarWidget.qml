// Bar button for the Aranea menu: the plugin's "barWidget" entry point, placed
// in the omarchy-shell bar. Left click toggles the menu, right click opens a terminal.
import Quickshell
import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "araneadev.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  // Directory of the current theme's branding marks; the button shows aranea-glyph.svg from it.
  readonly property string brandingMarksPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/current/theme/branding/marks/"

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    fixedWidth: Style.space(30)
    fixedHeight: root.bar ? root.bar.barSize : 32
    horizontalMargin: 0
    verticalPadding: 0
    tooltipText: "Aranea menu"

    Image {
      anchors.centerIn: parent
      width: Style.space(16)
      height: Style.space(16)
      source: "file://" + root.brandingMarksPath + "aranea-glyph.svg"
      fillMode: Image.PreserveAspectFit
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      smooth: true
      mipmap: true
      enabled: false
    }

    onPressed: function (button) {
      if (!root.bar)
        return
      if (button === Qt.RightButton)
        root.bar.run("xdg-terminal-exec")
      else
        root.bar.run("omarchy-shell shell toggle araneadev.menu '{\"menu\":\"root\"}'")
    }
  }
}
