// Verify preview separator pixels using the actual clipboard results pane.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.clipboard" as Clipboard
import "plugins/araneadev.clipboard/components" as Components

ShellRoot {
  QmlTest {
    id: t
  }
  Clipboard.Clipboard {
    id: clip
    windowEnabled: false
    captureEnabled: false
    historyPath: Quickshell.env("HOME") + "/native-clipboard.json"
  }
  FloatingWindow {
    visible: true
    implicitWidth: 800
    implicitHeight: 600
    Rectangle {
      id: scene
      anchors.fill: parent
      color: "#101010"
      Components.ClipboardResultsPane {
        id: pane
        x: 20
        y: 20
        width: 400
        height: 250
        model: clip.displayModel
        selectedIndex: clip.selectedIndex
        borderColor: "#ff0000"
        emptyMessage: "No matches for “" + clip.filterText + "”"
      }
    }
  }
  // Capture the real rendered content before advancing the query state.
  function capture(name, next) {
    scene.grabToImage(function (result) {
      t.check(result.saveToFile(Quickshell.env("ARANEA_NATIVE_CAPTURE") + "/" + name + ".png"), name + " picker capture saved")
      next()
    })
  }
  Component.onCompleted: t.step(500, function () {
    clip.loadHistory(JSON.stringify([
      {
        type: "text",
        text: "Saved note",
        capturedAtMs: Date.now()
      }
    ]))
    clip.setFilter("z".repeat(1000))
    t.step(100, function () {
      capture("empty", function () {
        clip.setFilter("")
        t.step(100, function () {
          capture("populated", function () {
            console.log("NATIVE PICKER " + JSON.stringify({
              width: scene.width,
              x: pane.x + Math.round(pane.width * 0.48),
              y: pane.y + 10
            }))
            console.log("NATIVE READY")
            t.done()
          })
        })
      })
    })
  })
}
