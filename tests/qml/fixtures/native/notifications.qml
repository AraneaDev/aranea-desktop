// Real notification surfaces and keyboard handlers on the private compositor.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "lib"
import "plugins/araneadev.shared" as Aranea
import "plugins/araneadev.notifications" as Notif
import "plugins/araneadev.notifications/NotificationLogic.js" as Logic

ShellRoot {
  id: host
  // Test-owned sender boundary; no notification daemon or external action runs.
  property var invoked: []
  // Stable timestamp origin for the independent notification identities.
  property real stamp: Date.now()
  // Dynamically owned real Toasts instance, destroyed by the teardown check.
  property var toast: null
  // Timer progress sampled before hold/release intervals.
  property real remaining: 0
  // Latch compositor delivery during the production Exclusive prime.
  property bool centerPrimeAcquired: false
  // Stored observer target avoids binding to the non-notifying data collection.
  property var centerFrame: null
  QmlTest {
    id: t
  }
  Notif.Service {
    id: svc
    serverEnabled: false
    windowEnabled: false
    motionEnabled: false
    stateDir: Quickshell.env('HOME') + '/native-notification-state/'
  }
  FloatingWindow {
    id: ordinary
    title: "Aranea native keyboard sink"
    visible: true
    screen: Quickshell.screens[0]
    implicitWidth: 600
    implicitHeight: 400
    TextInput {
      id: typed
      anchors.centerIn: parent
      width: 400
      height: 40
      focus: true
    }
    Notif.Panel {
      id: center
      service: svc
      x: 10
      y: 10
      width: implicitWidth
      height: implicitHeight
    }
  }
  Connections {
    target: host.centerFrame ? host.centerFrame.focusTarget : null
    function onActiveFocusChanged() {
      if (center.opened && frame().focusTarget.activeFocus)
        host.centerPrimeAcquired = true
    }
  }
  Component {
    id: toastComponent
    Notif.Toasts {
      root: svc
      focusedOutputName: 'HEADLESS-2'
    }
  }
  // Find the real native center frame among the panel data objects.
  function frame() {
    for (var child of center.data) {
      var candidate = child as Aranea.KeyboardPanelFrame
      if (candidate)
        return candidate
    }
    return null
  }
  // Observe the actual layer-shell policy on every native toast window.
  function owners() {
    return Array.prototype.slice.call(toast.surfaces).filter(function (window) {
      return window.WlrLayershell.keyboardFocus === WlrKeyboardFocus.Exclusive
    })
  }
  // Deduplicate native content traversal to observe each timer-owning slot once.
  function slots() {
    return Array.prototype.slice.call(toast.surfaces).reduce(function (out, window) {
      return out.concat(t.findChildren(window, 'notificationToastSlot'))
    }, []).filter(function (slot, index, all) {
      return all.indexOf(slot) === index
    })
  }
  // Deliver test sender actions through the unchanged service dispatch path.
  function add(id) {
    svc.liveRefs[id] = {
      tracked: true,
      actions: [
        {
          identifier: 'one',
          text: 'One',
          invoke: function () {
            invoked = invoked.concat([id + '-one'])
          }
        },
        {
          identifier: 'two',
          text: 'Two',
          invoke: function () {
            invoked = invoked.concat([id + '-two'])
          }
        }
      ],
      dismiss: function () {
        this.tracked = false
      }
    }
    svc.popupModel.insert(0, Logic.snapshotOf({
      id: id,
      appName: 'omarchy-action',
      expireTimeout: 30000
    }, stamp + id))
  }
  // Check native ownership and real expiry timers after every exit route.
  function released(reason) {
    t.check(!svc.keyboardMode && owners().length === 0, reason + ' releases toast native ownership')
    t.check(slots().length > 0 && slots().every(function (slot) {
      return slot.ticking
    }), reason + ' resumes expiry')
  }
  // Control setup and observation only; input always arrives through wtype.
  IpcHandler {
    target: 'native.fixture'
    function seed(id: int): void {
      add(id)
    }
    function held(label: string): void {
      t.equal(toast.surfaces.length, 2, label + ' has two actual outputs')
      t.equal(owners().length, 1, label + ' grants one native owner')
      t.equal(owners()[0].screen.name, 'HEADLESS-2', label + ' grants focused output')
      t.check(slots().every(function (slot) {
        return !slot.ticking
      }), label + ' pauses every expiry timer')
      remaining = slots()[0].remainingLifetime
    }
    function paused(): void {
      t.equal(slots()[0].remainingLifetime, remaining, 'held countdown stays unchanged')
    }
    function action(expected: string): void {
      t.equal(invoked, expected === 'enter' ? ['81-two'] : ['81-two', '82-one'], 'native key invokes exactly the selected action once')
      released('action')
    }
    function escaped(): void {
      released('Escape')
      remaining = slots()[0].remainingLifetime
    }
    function resumed(): void {
      t.check(slots()[0].remainingLifetime < remaining, 'released countdown advances')
    }
    function typedText(expected: string): void {
      t.equal(typed.text, expected, 'ordinary window receives typing after release')
      typed.text = ''
    }
    function removeSelected(): void {
      svc.expirePopup(svc.popupIndexFor(svc.keyboardOriginalId))
      add(85)
    }
    function stale(): void {
      t.equal(invoked, ['81-two', '82-one'], 'removed selection cannot redirect a real key to its replacement')
      released('selected removal')
    }
    function openCenter(): void {
      host.centerPrimeAcquired = false
      center.open()
    }
    function handoff(): void {
      t.check(host.centerPrimeAcquired, 'compositor delivers automatic center focus before pointer refocus')
      t.equal(svc.inbox.model.get(0).summary, 'retained inbox entry', 'center handoff preserves inbox')
      t.equal(svc.popupModel.count, 2, 'center handoff preserves live toasts')
      t.check(center.opened && frame().open, 'real center opens during toast keyboard mode')
      released('center handoff')
      t.check(frame().WlrLayershell.keyboardFocus !== WlrKeyboardFocus.None, 'center requests native keyboard ownership')
    }
    function centerKey(): void {
      t.check(center.keyboardCursor && center.cursorShown, 'real Down key reaches OnDemand center after private pointer refocus')
    }
    function centerClosed(): void {
      t.check(!center.opened && !frame().open, 'real Escape closes the center')
      released('center close')
    }
    function outputLost(): void {
      t.equal(Quickshell.screens.length, 1, 'private owner output removed')
      t.check(!svc.keyboardMode && owners().length === 0, 'output loss releases ownership without transfer')
    }
    function teardown(): void {
      t.check(svc.keyboardMode && owners().length === 1, 'remaining output owns keyboard before teardown')
      toast.destroy()
      t.step(100, function () {
        t.check(!svc.keyboardMode && !svc.popupHeld('unused'), 'native toast teardown releases keyboard and timer hold')
        svc.clearPopups()
        console.log('NATIVE TEARDOWN')
      })
    }
    function finish(): void {
      t.done()
    }
  }
  Component.onCompleted: t.step(250, function () {
    centerFrame = frame()
    toast = toastComponent.createObject(host)
    frame().motionEnabled = false
    svc.inbox.upsert({
      timestamp: stamp,
      originalId: 901,
      app: 'mail',
      summary: 'retained inbox entry'
    })
    add(80)
    add(81)
    t.waitFor(function () {
      return toast.surfaces.length === 2 && slots().length === 4
    }, 5000, 'native toast surfaces ready', function () {
      t.equal(owners().length, 0, 'passive toasts never grab keyboard')
      console.log('NATIVE READY')
    })
  })
}
