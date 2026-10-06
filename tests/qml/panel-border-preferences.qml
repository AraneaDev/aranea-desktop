// Refined popup chrome must retain zero and asymmetric user border widths.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.shared" as Shared

ShellRoot {
  QmlTest {
    id: t
  }
  QtObject {
    id: panel
    readonly property var borderSpec: Shared.PanelChrome.popupBorder(true)
  }
  Timer {
    interval: 120
    running: true
    onTriggered: {
      Color.shellValues = {
        "popups.border-width": "0"
      }
      Qt.callLater(function () {
        t.equal(Border.top(panel.borderSpec), 0, "a configured zero popup border stays absent")
        t.equal(Border.left(panel.borderSpec), 0, "zero applies to each popup edge")
        Color.shellValues = {
          "popups.border-width": "3",
          "popups.border-width-top": "1",
          "popups.border-width-right": "4",
          "popups.border-width-bottom": "2",
          "popups.border-width-left": "0"
        }
        Qt.callLater(function () {
          t.equal(Border.top(panel.borderSpec), 1, "refined popup preserves configured top width")
          t.equal(Border.right(panel.borderSpec), 4, "refined popup preserves configured right width")
          t.equal(Border.bottom(panel.borderSpec), 2, "refined popup preserves configured bottom width")
          t.equal(Border.left(panel.borderSpec), 0, "refined popup preserves an absent left edge")
          t.done()
        })
      })
    }
  }
}
