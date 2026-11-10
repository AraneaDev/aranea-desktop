// Real toast routing, countdown and key dispatch with only native windows adapted.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import "lib"
import "plugins/araneadev.notifications" as Notif
import "plugins/araneadev.notifications/NotificationLogic.js" as Logic

ShellRoot {
  id: host
  // Records sender actions reached through the production toast key handler.
  property var invoked: []
  // Stable timestamp origin for independent toast identities.
  property real stamp: Date.now()
  QmlTest {
    id: t
  }
  TestCase {
    id: keys
    when: false
  }
  FloatingWindow {
    visible: true
    implicitWidth: 1200
    implicitHeight: 900
    Item {
      id: surfaceHost
      anchors.fill: parent
    }
  }
  Notif.Service {
    id: svc
    serverEnabled: false
    windowEnabled: false
    motionEnabled: false
    stateDir: Quickshell.env('HOME') + '/toast-state/'
  }
  Component {
    id: toastComponent
    Notif.Toasts {
      root: svc
      outputScreens: [
        {
          name: 'left',
          width: 1000,
          height: 800
        },
        {
          name: 'right',
          width: 1000,
          height: 800
        }
      ]
      focusedOutputName: 'right'
    }
  }
  // Dynamically owned production Toasts component under the native adapter.
  property var toast: null
  // Deliver a plain popup row with a controlled native sender boundary.
  function add(id) {
    var ref = {
      tracked: true,
      actions: [
        {
          identifier: 'one',
          text: 'One',
          invoke: function () {
            invoked.push(id + '-one')
          }
        },
        {
          identifier: 'two',
          text: 'Two',
          invoke: function () {
            invoked.push(id + '-two')
          }
        }
      ],
      dismiss: function () {
        this.tracked = false
      }
    }
    svc.liveRefs[id] = ref
    svc.popupModel.insert(0, Logic.snapshotOf({
      id: id,
      appName: 'omarchy-action'
    }, stamp + id))
  }
  // Inspect the actual surfaces instantiated by production output routing.
  function windows() {
    return Array.prototype.slice.call(toast.surfaces)
  }
  // Surfaces currently requesting exclusive native keyboard ownership.
  function owners() {
    return windows().filter(function (w) {
      return w.nativeLayer.keyboardFocus === WlrKeyboardFocus.Exclusive
    })
  }
  // Live timer-owning production card delegates across every output.
  function slots() {
    return windows().reduce(function (out, window) {
      return out.concat(t.findChildren(window, 'notificationToastSlot'))
    }, [])
  }
  QtObject {
    id: unnamedSignals
    signal closed
  }
  // Confirm separate unnamed deliveries become separate actual toast delegates.
  function checkUnnamedCards() {
    toast = toastComponent.createObject(surfaceHost)
    toast.outputScreens = [
      {
        name: 'left',
        width: 1000,
        height: 800
      }
    ]
    for (var id of [91, 92]) {
      svc.handleNotification({
        id: id,
        appName: '',
        summary: 'unnamed ' + id,
        urgency: 0,
        hints: {
          transient: true
        },
        tracked: false,
        closed: unnamedSignals.closed,
        dismiss: function () {
          this.tracked = false
        }
      })
    }
    t.step(80, function () {
      windows().forEach(function (window) {
        window.parent = surfaceHost
      })
      t.step(40, function () {
        var cards = slots()
        t.equal(cards.map(function (card) {
          return card.originalId
        }).sort(), [91, 92], 'unnamed deliveries render two independent card delegates')
        t.check(cards.length === 2 && cards.every(function (card) {
          return card.visible && card.width > 0 && card.height > 0
        }), 'both unnamed cards have visible geometry')
        svc.dismissPopup(0)
        t.step(20, function () {
          t.equal(slots().map(function (card) {
            return card.originalId
          }), [91], 'dismissing newest unnamed toast leaves its visible neighbour')
          svc.clearPopups()
          toast.destroy()
          t.done()
        })
      })
    })
  }
  Component.onCompleted: t.step(200, function () {
    toast = toastComponent.createObject(surfaceHost)
    add(81)
    t.step(100, function () {
      windows().forEach(function (window) {
        window.parent = surfaceHost
      })
      t.equal(owners().length, 0, 'passive notifications never own keyboard')
      svc.startKeyboard(81)
      t.step(100, function () {
        t.equal(owners().length, 1, 'exactly one output owns keyboard')
        t.equal(owners()[0].screen.name, 'right', 'focused output receives keyboard ownership')
        t.check(slots().every(function (slot) {
          return !slot.ticking
        }), 'every toast timer is paused')
        var before = slots()[0].remainingLifetime
        t.step(150, function () {
          t.equal(slots()[0].remainingLifetime, before, 'paused countdown does not advance')
          var catcher = t.findChildren(owners()[0], 'notificationToastKeys')[0]
          catcher.forceActiveFocus()
          keys.keyClick(Qt.Key_Down)
          keys.keyClick(Qt.Key_Return)
          t.equal(invoked, ['81-two'], 'actual Enter key dispatch invokes selected choice')
          t.equal(owners().length, 0, 'action releases native keyboard ownership')
          add(82)
          t.step(100, function () {
            svc.startKeyboard(82)
            var catcher = t.findChildren(owners()[0], 'notificationToastKeys')[0]
            catcher.forceActiveFocus()
            keys.keyClick(Qt.Key_Escape)
            t.equal(owners().length, 0, 'Escape releases native keyboard ownership')
            t.check(slots().every(function (slot) {
              return slot.ticking
            }), 'Escape resumes every countdown')
            var remaining = slots()[0].remainingLifetime
            t.step(150, function () {
              t.check(slots()[0].remainingLifetime < remaining, 'resumed countdown advances')
              svc.startKeyboard(82)
              var staleCatcher = t.findChildren(owners()[0], 'notificationToastKeys')[0]
              svc.expirePopup(0)
              add(83)
              staleCatcher.forceActiveFocus()
              keys.keyClick(Qt.Key_1)
              t.equal(invoked, ['81-two'], 'queued numeric key cannot invoke a card after selected expiry')
              t.equal(owners().length, 0, 'expiry releases native keyboard ownership')
              t.check(slots().every(function (slot) {
                return slot.ticking
              }), 'expiry releases countdown pause')
              svc.startKeyboard(83)
              toast.outputScreens = [
                {
                  name: 'left',
                  width: 1000,
                  height: 800
                }
              ]
              t.step(50, function () {
                t.check(!svc.keyboardMode, 'removing owner output exits keyboard mode')
                t.equal(owners().length, 0, 'lost output never redirects keyboard ownership')
                toast.outputScreens = []
                t.equal(svc.startKeyboard(83), false, 'no output cannot report acquired keyboard ownership')
                toast.outputScreens = [
                  {
                    name: 'left',
                    width: 1000,
                    height: 800
                  }
                ]
                svc.startKeyboard(83)
                t.equal(owners()[0].screen.name, 'left', 'missing focused output falls back to one existing output')
                toast.destroy()
                t.step(50, function () {
                  t.check(!svc.keyboardMode && !svc.popupHeld('unused'), 'toast teardown releases keyboard and expiry pause')
                  svc.clearPopups()
                  checkUnnamedCards()
                })
              })
            })
          })
        })
      })
    })
  })
}
