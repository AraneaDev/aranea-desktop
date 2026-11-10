// Real center lifecycle, bell and toast ownership; only native windows adapt.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.Ui as Ui
import "lib"
import "plugins/araneadev.shared" as Aranea
import "plugins/araneadev.notifications" as Notif
import "plugins/araneadev.notifications/NotificationLogic.js" as Logic

ShellRoot {
  id: testRoot
  // Stable identity for the card held during each opening route.
  readonly property real stamp: Date.now()
  QmlTest {
    id: t
  }
  TestCase {
    id: pointer
    when: false
  }
  Notif.Service {
    id: svc
    serverEnabled: false
    windowEnabled: false
    motionEnabled: false
    stateDir: Quickshell.env('HOME') + '/center-keyboard-state/'
  }
  FloatingWindow {
    visible: true
    implicitWidth: 1000
    implicitHeight: 800
    Item {
      id: surfaceHost
      anchors.fill: parent
      Notif.Panel {
        id: center
        x: 8
        y: 8
        service: svc
        width: implicitWidth
        height: implicitHeight
      }
    }
  }
  Notif.Toasts {
    id: toasts
    root: svc
    outputScreens: [
      {
        name: 'fixture',
        width: 1000,
        height: 800
      }
    ]
    focusedOutputName: 'fixture'
  }
  // Find real controls by their QML type without replacing their behavior.
  function bell() {
    for (var i = 0; i < center.children.length; i++) {
      var button = center.children[i] as Ui.BarIconButton
      if (button)
        return button
    }
    return null
  }
  // Read the actual keyboard frame's requested native ownership policy.
  function frame() {
    for (var i = 0; i < center.children.length; i++) {
      var popup = center.children[i] as Aranea.KeyboardPanelFrame
      if (popup)
        return popup
    }
    return null
  }
  // Restore the original toast keyboard session before each entry point.
  function holdToast() {
    center.close()
    svc.startKeyboard(801)
    t.check(svc.keyboardMode && svc.popupHeld(String(stamp) + '-801'), 'toast starts with keyboard ownership and paused expiry')
    t.equal(toasts.surfaces[0].nativeLayer.keyboardFocus, WlrKeyboardFocus.Exclusive, 'toast surface requests exclusive keyboard focus')
  }
  // Every direct entry point must release the same original toast session.
  function checkHandoff(route) {
    t.check(center.opened, route + ' opens the actual center')
    t.check(!svc.keyboardMode && !svc.popupHeld(String(stamp) + '-801'), route + ' releases toast keyboard and expiry pause')
    t.equal(toasts.surfaces[0].nativeLayer.keyboardFocus, WlrKeyboardFocus.None, route + ' releases native toast focus')
    t.check(frame().open && frame().nativeLayer.keyboardFocus !== WlrKeyboardFocus.None, route + ' leaves keyboard ownership with center frame')
    t.equal(svc.inbox.model.get(0).summary, 'retained inbox entry', route + ' preserves inbox content')
    t.equal(svc.popupModel.count, 1, route + ' preserves live toast')
  }
  Component.onCompleted: t.step(200, function () {
    toasts.surfaces[0].parent = surfaceHost
    frame().motionEnabled = false
    svc.inbox.upsert({
      timestamp: stamp,
      originalId: 901,
      app: 'mail',
      summary: 'retained inbox entry'
    })
    svc.popupModel.append(Logic.snapshotOf({
      id: 801,
      appName: 'omarchy-action'
    }, stamp))
    holdToast()
    // Host shell summons the widget through its public open method.
    center.open()
    checkHandoff('direct panel open')
    holdToast()
    // Direct shell toggle uses the same public method as the existing bell.
    center.toggle()
    checkHandoff('direct shell toggle')
    holdToast()
    t.step(50, function () {
      pointer.mouseClick(bell())
      checkHandoff('bell pointer press')
      var slots = t.findChildren(toasts.surfaces[0], 'notificationToastSlot')
      t.check(slots[0].ticking, 'center handoff resumes production toast timer')
      var remaining = slots[0].remainingLifetime
      t.step(150, function () {
        t.check(slots[0].remainingLifetime < remaining, 'resumed toast countdown advances while center is open')
        center.close()
        svc.clearPopups()
        t.done()
      })
    })
  })
}
