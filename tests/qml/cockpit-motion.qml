// Cockpit motion keeps hit targets stable and stops immediately when disabled.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.shared" as Aranea
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host
  QmlTest {
    id: t
  }
  Menu.MenuRootTile {
    id: tile
    x: 20
    y: 30
    width: 220
    height: 100
    motionEnabled: true
    tileData: ({
        id: "files",
        label: "Files",
        detail: "BROWSE",
        icon: "F"
      })
  }
  FloatingWindow {
    id: frameWindow
    visible: true
    implicitWidth: 300
    implicitHeight: 200
    Aranea.CircuitFrame {
      id: frame
      anchors.fill: parent
    }
  }
  Component.onCompleted: t.step(30, function () {
    tile.hovered = true
    t.step(60, function () {
      t.check(tile.highlight > 0 && tile.highlight < 1, "hover lighting passes through intermediate frames: " + tile.highlight)
      t.equal(tile.x, 20, "hover does not move the horizontal hit target")
      t.equal(tile.y, 30, "hover does not move the vertical hit target")
      tile.motionEnabled = false
      t.equal(tile.highlight, 1, "disabling hover motion snaps to the active light")
      tile.hovered = false
      t.equal(tile.highlight, 0, "reduced-motion hover clears immediately")
      var component = Qt.createComponent("plugins/araneadev.shared/DeckReveal.qml")
      t.equal(component.status, Component.Ready, "deck entrance controller loads")
      if (component.status !== Component.Ready) {
        t.done()
        return
      }
      var reveal = component.createObject(host, {
        motionEnabled: true,
        delay: 100
      })
      reveal.opened = true
      t.step(50, function () {
        t.equal(reveal.progress, 0, "stagger holds later content until its turn")
        t.step(140, function () {
          t.check(reveal.progress > 0 && reveal.progress < 1, "staggered reveal has intermediate frames")
          reveal.motionEnabled = false
          t.equal(reveal.progress, 1, "disabling entrance motion shows the complete content")
          t.equal(reveal.running, false, "reduced motion cancels pending choreography")
          reveal.opened = false
          t.equal(reveal.progress, 0, "reduced-motion close resets presentation")
          reveal.opened = true
          reveal.motionEnabled = true
          t.equal(reveal.running, false, "enabling motion does not replay a completed entrance")
          Aranea.MotionState.motionEnabled = true
          t.equal(frame.ambientRunning, false, "reading surfaces do not run decorative sweeps")
          frame.ambientEnabled = true
          t.check(frame.ambientRunning, "visible instrument frame animates")
          frame.visible = false
          t.equal(frame.ambientRunning, false, "hidden instrument frame stops ambient work")
          frame.visible = true
          frameWindow.visible = false
          t.equal(frame.ambientRunning, false, "hiding the native window stops ambient work")
          frameWindow.visible = true
          Aranea.MotionState.motionEnabled = false
          t.equal(frame.ambientRunning, false, "reduced motion stops ambient work")
          t.done()
        })
      })
    })
  })
}
