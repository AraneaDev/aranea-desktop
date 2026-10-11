// Exercises confirmation key semantics, input release and reversible card motion.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }
  FloatingWindow {
    visible: true
    width: 500
    height: 400
    Aranea.SpringConfirmDialog {
      id: dialog
      anchors.fill: parent
      property int confirmations: 0
      property int cancellations: 0
      onConfirmed: {
        confirmations++
        opened = false
      }
      onCanceled: {
        cancellations++
        opened = false
      }
    }
  }
  Component.onCompleted: t.step(50, function () {
    t.check(!dialog.visible && !dialog.enabled, 'closed confirmation owns no input')
    dialog.opened = true
    t.equal(dialog.selectedIndex, 1, 'confirmation preserves upstream default selection')
    dialog.handleKey({
      key: Qt.Key_Left
    })
    t.equal(dialog.selectedIndex, 0, 'left changes confirmation selection')
    dialog.handleKey({
      key: Qt.Key_Tab
    })
    t.equal(dialog.selectedIndex, 1, 'tab changes confirmation selection')
    t.step(80, function () {
      var card = t.findChild(dialog, 'springConfirmationCard')
      t.check(card.opacity > 0 && card.opacity <= 1, 'confirmation fades its entire card')
      dialog.handleKey({
        key: Qt.Key_Return
      })
      t.equal(dialog.confirmations, 1, 'return confirms selected destructive action exactly once')
      t.check(!dialog.enabled && dialog.visible, 'closing confirmation retains presentation and releases input')
      t.check(!dialog.handleKey({
        key: Qt.Key_Return
      }), 'closing frames reject stale keys')
      var opacity = card.opacity
      dialog.opened = true
      t.equal(card.opacity, opacity, 'reopen keeps current presentation')
      dialog.motionEnabled = false
      t.equal(card.opacity, 1, 'reduced motion snaps open opacity')
      t.equal(card.scale, 1, 'reduced motion snaps open scale')
      dialog.handleKey({
        key: Qt.Key_Escape
      })
      t.equal(dialog.cancellations, 1, 'escape cancels exactly once')
      t.check(!dialog.visible && !dialog.enabled, 'reduced motion close releases presentation immediately')
      t.done()
    })
  })
}
