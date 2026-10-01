// Shared Filament components: the slider maps value to progress over any
// range and keeps its node inside its own width (one right edge), the
// switch and device row emit only when they should, and the live-signal
// glow follows the level along the lit strand.
import QtQuick
import Quickshell
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

    t.done()
  })
}
