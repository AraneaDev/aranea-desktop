// Shared Filament components: the slider maps value to progress over any
// range and keeps its node inside its own width (one right edge), the
// switch and device row emit only when they should, and the live-signal
// glow follows the level along the lit strand. A NodeDeviceRow with a
// PointerMoveGate never takes the cursor when it moves under a still
// pointer, and KeyboardInputFrame/blocked forwards to its key catcher.
// A key the catcher leaves unaccepted (Delete) reaches unhandledKey unless
// the frame is blocked.
import QtQuick
import QtTest
import Quickshell
import qs.Ui
import "lib"
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }

  Aranea.FilamentSlider {
    id: stream
    width: 300
    maximum: 1.5
    value: 1.2
  }
  Aranea.FilamentSlider {
    id: full
    width: 300
    value: 1
  }
  Aranea.FilamentSlider {
    id: signal
    width: 300
    value: 0.8
  }
  Aranea.FilamentSlider {
    id: wheeled
    width: 300
    value: 0.5
    property var emitted: []
    onMoved: function (value) {
      emitted.push(Math.round(value * 100))
    }
  }
  Aranea.FilamentSlider {
    id: canceled
    width: 300
    value: 0.3
  }
  Aranea.FilamentSwitch {
    id: sw
    property int count: 0
    onToggled: count += 1
  }
  Aranea.NodeDeviceRow {
    id: unplugged
    width: 300
    label: "WH-1000XM4"
    available: false
    property int count: 0
    onChosen: count += 1
  }
  Aranea.NodeDeviceRow {
    id: speakers
    width: 300
    label: "ALC236 Analog"
    active: true
    property int count: 0
    onChosen: count += 1
  }
  Aranea.NodeDeviceRow {
    id: busyRow
    width: 300
    label: "Earbuds"
    busy: true
  }
  Aranea.NodeDeviceRow {
    id: strongSignal
    width: 300
    label: "Keyboard"
    signal: 3
  }
  Aranea.NodeDeviceRow {
    id: noSignal
    width: 300
    label: "Mouse"
    signal: 0
  }
  Aranea.NodeDeviceRow {
    id: unusedSignal
    width: 300
    label: "Headset"
  }
  Aranea.NodeDeviceRow {
    id: trailingRow
    width: 300
    label: "Trailing device"
    detail: "connected"
    Rectangle {
      id: trailingAction
      width: 20
      height: 20
    }
  }
  Aranea.FilamentPulse {
    id: pulseOff
    width: 200
    running: false
  }
  Aranea.FilamentPulse {
    id: pulseOn
    width: 200
    running: true
  }
  Aranea.KeyboardInputFrame {
    id: keyboardInput
    width: 120
    height: 80
    property int deletes: 0
    onDeleteRequested: deletes += 1
  }
  Aranea.KeyboardInputFrame {
    id: blockedInput
    width: 120
    height: 80
    blocked: true
  }

  // A tall row so it still covers the test point after shifting, and a
  // plain row with no gate, in a real window so Qt delivers hover/move.
  FloatingWindow {
    id: gateWindow
    implicitWidth: 320
    implicitHeight: 220
    visible: true

    Item {
      id: gateHost
      anchors.fill: parent

      Aranea.NodeDeviceRow {
        id: gatedRow
        objectName: "gatedRow"
        width: 300
        height: 100
        y: 40
        label: "Gated"
        pointerGate: rowGate
        property int enteredCount: 0
        onEntered: enteredCount += 1
      }
      Aranea.NodeDeviceRow {
        id: ungatedRow
        objectName: "ungatedRow"
        width: 300
        y: 180
        label: "Ungated"
        property int enteredCount: 0
        onEntered: enteredCount += 1
      }

      PointerMoveGate {
        id: rowGate
        referenceItem: gateHost
      }
    }
  }

  // A row created under a still pointer, as a Repeater rebuild does: a
  // click that lands right after it appears, before any real move over it,
  // was aimed at whatever was there before.
  FloatingWindow {
    id: freshWindow
    implicitWidth: 320
    implicitHeight: 120
    visible: true

    Item {
      id: freshHost
      anchors.fill: parent

      Loader {
        id: freshLoader
        y: 20
        active: false
        sourceComponent: Aranea.NodeDeviceRow {
          width: 300
          height: 60
          label: "Fresh"
          pointerGate: freshGate
          onChosen: freshHost.chosenCount += 1
        }
      }

      // How many times a fresh row was chosen.
      property int chosenCount: 0

      PointerMoveGate {
        id: freshGate
        referenceItem: freshHost
      }
    }
  }

  // A focused frame in a real window, so Qt delivers real key events.
  FloatingWindow {
    id: keyWindow
    implicitWidth: 160
    implicitHeight: 100
    visible: true

    Aranea.KeyboardInputFrame {
      id: keyedInput
      anchors.fill: parent
      property var unhandled: []
      property int moves: 0
      onMoveRequested: moves += 1
      onUnhandledKey: function (event) {
        // keyClick with a modifier presses the modifier first; only the
        // keys under test are recorded.
        if (event.key !== Qt.Key_Delete && event.key !== Qt.Key_Down)
          return
        unhandled = unhandled.concat([
          {
            key: event.key,
            shift: (event.modifiers & Qt.ShiftModifier) !== 0
          }
        ])
        event.accepted = true
      }
    }
  }

  // Synthesizes the pointer events (TestCase's mouseMove), never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // Keys the catcher leaves unaccepted reach unhandledKey (with their
  // modifiers); keys it takes and keys while blocked do not.
  function unhandledKeys() {
    keyedInput.focusTarget.forceActiveFocus()
    t.step(50, function () {
      pointer.keyClick(Qt.Key_Delete, Qt.ShiftModifier)
      t.equal(keyedInput.unhandled.length, 1, "an unaccepted key reaches unhandledKey")
      t.check(keyedInput.unhandled.length === 1 && keyedInput.unhandled[0].key === Qt.Key_Delete && keyedInput.unhandled[0].shift, "with its key and Shift")
      pointer.keyClick(Qt.Key_Down)
      t.equal(keyedInput.moves, 1, "the catcher still takes its own keys")
      t.equal(keyedInput.unhandled.length, 1, "a key the catcher took never reaches unhandledKey")
      keyedInput.blocked = true
      pointer.keyClick(Qt.Key_Delete)
      t.equal(keyedInput.unhandled.length, 1, "nothing reaches unhandledKey while blocked")
      t.done()
    })
  }

  // Clicks on rows created under a still pointer: refused for about 300 ms
  // unless the gate accepted a real move over the row since.
  function freshClicks() {
    pointer.mouseMove(freshHost, 40, 50)
    t.step(80, function () {
      pointer.mouseMove(freshHost, 44, 50)
      t.step(80, function () {
        freshLoader.active = true
        t.step(30, function () {
          pointer.mouseClick(freshHost, 44, 50)
          t.equal(freshHost.chosenCount, 0, "a click right after a row appears under a still pointer is ignored")
          t.step(350, function () {
            pointer.mouseClick(freshHost, 44, 50)
            t.equal(freshHost.chosenCount, 1, "once the row has settled, a click chooses it")
            freshLoader.active = false
            freshLoader.active = true
            t.step(30, function () {
              pointer.mouseMove(freshHost, 50, 52)
              t.step(30, function () {
                pointer.mouseClick(freshHost, 50, 52)
                t.equal(freshHost.chosenCount, 2, "a real move over a fresh row lets a click through at once")
                unhandledKeys()
              })
            })
          })
        })
      })
    })
  }

  Component.onCompleted: t.step(200, function () {
    t.equal(Math.round(stream.progress * 100), 80, "1.2 of 1.5 lights 80% of the strand")
    t.check(full.progress === 1, "a full slider lights the whole strand")
    var node = t.findChild(full, "filamentNode")
    t.check(node !== null && node.x + node.width <= full.width + 0.01, "the node never passes the strand's right edge")
    full.setFromX(150)
    t.equal(Math.round(full.liveValue * 100), 50, "a click at half width sets half")
    var glow = t.findChild(signal, "filamentGlow")
    t.check(glow !== null && !glow.visible, "no level, no signal glow")
    signal.level = 0.5
    var lit = t.findChild(signal, "filamentLit")
    t.check(glow.visible, "a level lights the signal glow")
    t.check(Math.abs(glow.width - lit.width / 2) < 0.5, "a half level glows over half the lit strand")
    signal.muted = true
    t.check(!glow.visible, "a muted slider has no signal glow")
    wheeled.wheelBy(120)
    wheeled.wheelBy(-120)
    wheeled.wheelBy(-120)
    wheeled.wheelBy(0)
    t.equal(wheeled.emitted, [55, 50, 45], "each wheel notch steps by 5% (a zero delta does nothing)")
    wheeled.value = 0.98
    wheeled.wheelBy(120)
    t.equal(wheeled.emitted[wheeled.emitted.length - 1], 100, "the wheel clamps at the maximum")
    var area = t.findChild(canceled, "filamentMouse")
    t.check(area !== null && area.preventStealing, "a drag can't be stolen by a surrounding Flickable")
    canceled.dragging = true
    canceled.liveValue = 0.9
    area.canceled()
    t.check(!canceled.dragging && Math.abs(canceled.liveValue - 0.3) < 0.001, "a canceled drag ends and shows the real value")
    sw.activate()
    t.equal(sw.count, 1, "the switch emits toggled")
    unplugged.activate()
    t.equal(unplugged.count, 0, "an unavailable device can't be chosen")
    speakers.activate()
    t.equal(speakers.count, 1, "an available device is chosen")

    var pulse = t.findChild(busyRow, "busyPulse")
    t.check(pulse !== null && pulse.running, "a busy row's marker pulse is running")
    var noPulse = t.findChild(speakers, "busyPulse")
    t.check(noPulse !== null && !noPulse.running, "a non-busy row's marker pulse is idle")

    var strongGlow = t.findChild(strongSignal, "signalGlow")
    t.check(strongGlow !== null && strongGlow.visible, "signal: 3 shows a marker glow")
    var noGlow = t.findChild(noSignal, "signalGlow")
    t.check(noGlow !== null && !noGlow.visible, "signal: 0 shows no marker glow")
    var unusedGlow = t.findChild(unusedSignal, "signalGlow")
    t.check(unusedGlow !== null && !unusedGlow.visible, "signal: -1 (default/unused) shows no marker glow")

    var edge = trailingRow.width
    var actionEdge = trailingAction.mapToItem(trailingRow, trailingAction.width, 0).x
    t.check(Math.abs(actionEdge - edge) < 0.5, "a trailing child ends on the row's right edge")
    var actionLeft = trailingAction.mapToItem(trailingRow, 0, 0).x
    var detail = t.findChild(trailingRow, "detailText")
    var detailRight = detail.mapToItem(trailingRow, detail.width, 0).x
    t.check(detail !== null && detailRight <= actionLeft + 0.5, "the detail text ends left of the trailing child")

    t.check(!pulseOff.visible, "FilamentPulse hides when not running")
    t.check(pulseOn.visible, "FilamentPulse shows when running")

    keyboardInput.focusTarget.deleteRequested()
    t.equal(keyboardInput.deletes, 1, "KeyboardInputFrame forwards the key catcher's deleteRequested")
    t.check(blockedInput.focusTarget.blocked, "KeyboardInputFrame.blocked forwards to the key catcher")

    // A gated row: the first sample only primes the gate, a real move past
    // it fires entered, a still pointer under a row that moved underneath
    // it does not, and a further real move does. Settle the pointer outside
    // any row first, since the window may open with the pointer already
    // somewhere over the content.
    pointer.mouseMove(gateHost, 10, 10)
    t.step(80, function () {
      pointer.mouseMove(gateHost, 10, 90)
      t.step(80, function () {
        pointer.mouseMove(gateHost, 14, 90)
        t.step(80, function () {
          t.equal(gatedRow.enteredCount, 1, "the first sample primes the gate; the second (a real move) fires entered")
          gatedRow.y += 20
          t.step(80, function () {
            pointer.mouseMove(gateHost, 14, 90)
            t.step(80, function () {
              t.equal(gatedRow.enteredCount, 1, "a still pointer under a row that moved doesn't take the cursor")
              pointer.mouseMove(gateHost, 14, 95)
              t.step(80, function () {
                t.equal(gatedRow.enteredCount, 2, "a real move after the row shifts fires entered again")
                pointer.mouseMove(ungatedRow, 10, 10)
                t.step(80, function () {
                  t.equal(ungatedRow.enteredCount, 1, "a row with no gate still emits entered on the first mouseMove")
                  freshClicks()
                })
              })
            })
          })
        })
      })
    })
  })
}
