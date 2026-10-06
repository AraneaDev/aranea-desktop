// Real pointer and keyboard activation must honor the settings layout settling gate.
import QtQuick
import QtTest
import Quickshell
import qs.Ui
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: root
  // Mutations emitted by the real local switch adapter.
  property int mutations: 0
  QmlTest {
    id: t
  }
  TestCase {
    id: pointer
    name: 'settings-toggle-pointer'
    when: false
  }
  FloatingWindow {
    implicitWidth: 240
    implicitHeight: 120
    visible: true
    Item {
      id: host
      anchors.fill: parent
      PointerMoveGate {
        id: gate
        referenceItem: host
        property real layoutChangedAt: 0
      }
      Settings.SettingsToggle {
        id: toggle
        x: 40
        y: 40
        pointerGate: gate
        onToggled: root.mutations++
      }
    }
  }
  // A layout or scroll change resets movement before the next pointer press.
  function stamp() {
    gate.layoutChangedAt = Date.now()
    gate.reset()
  }
  Component.onCompleted: t.step(50, function () {
    pointer.mouseMove(toggle, 10, toggle.height / 2)
    t.step(30, function () {
      pointer.mouseMove(toggle, 14, toggle.height / 2)
      root.stamp()
      t.step(20, function () {
        pointer.mouseClick(toggle, 14, toggle.height / 2)
        t.equal(mutations, 0, 'still-pointer click immediately after layout stamp is rejected')
        toggle.forceActiveFocus()
        pointer.keyClick(Qt.Key_Space)
        t.equal(mutations, 1, 'intentional keyboard activation bypasses pointer settling')
        t.step(350, function () {
          pointer.mouseClick(toggle, 14, toggle.height / 2)
          t.equal(mutations, 2, 'settled pointer click is allowed')
          root.stamp()
          t.step(20, function () {
            pointer.mouseMove(toggle, 18, toggle.height / 2)
            t.step(20, function () {
              pointer.mouseMove(toggle, 22, toggle.height / 2)
              t.step(20, function () {
                pointer.mouseClick(toggle, 22, toggle.height / 2)
                t.equal(mutations, 3, 'accepted real pointer movement allows immediate intentional click')
                root.stamp()
                t.step(20, function () {
                  pointer.mouseClick(toggle, 22, toggle.height / 2)
                  t.equal(mutations, 3, 'a later layout stamp invalidates previously accepted movement')
                  toggle.enabled = false
                  toggle.activate()
                  t.equal(mutations, 3, 'disabled keyboard activation remains guarded')
                  t.done()
                })
              })
            })
          })
        })
      })
    })
  })
}
