// Exercise the production tooltip flag bindings against Quickshell's metatypes.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"

ShellRoot {
  id: root
  QmlTest {
    id: t
  }
  FileView {
    id: production
    path: Quickshell.shellDir + "/plugins/araneadev.bar/Bar.qml"
    blockLoading: true
  }
  Component.onCompleted: t.step(0, function () {
    var source = production.text()
    t.check(source.length > 0, "production source is readable")
    var declaration = source.match(/readonly property var anchorFlags: \(\{[\s\S]*?\}\)/)
    t.check(declaration !== null, "production declares the opaque flag conversion boundary")
    if (!declaration) {
      t.done()
      return
    }
    var assignments = source.split("\n").filter(function (line) {
      return /^\s*(adjustment|edges|gravity): tooltipWindow\.anchorFlags\./.test(line)
    }).join("\n")
    var popup = Qt.createQmlObject("import Quickshell\nPopupWindow { id: tooltipWindow; " + declaration[0] + "; anchor { " + assignments + " } }", root)
    t.equal(popup.anchor.edges, Edges.Top | Edges.Left, "tooltip edges retain both native flags")
    t.equal(popup.anchor.gravity, Edges.Bottom | Edges.Right, "tooltip gravity retains both native flags")
    t.equal(popup.anchor.adjustment, PopupAdjustment.Slide, "tooltip adjustment retains both slide axes")
    popup.destroy()
    t.done()
  })
}
