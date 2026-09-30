// Shared Filament components: the slider maps value to progress over any
// range and keeps its node inside its own width (one right edge), the
// switch and device row emit only when they should.
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

  Component.onCompleted: t.step(200, function () {
    t.equal(Math.round(stream.progress * 100), 80, "1.2 of 1.5 lights 80% of the strand")
    t.check(full.progress === 1, "a full slider lights the whole strand")
    var node = t.findChild(full, "filamentNode")
    t.check(node !== null && node.x + node.width <= full.width + 0.01, "the node never passes the strand's right edge")
    full.setFromX(150)
    t.equal(Math.round(full.liveValue * 100), 50, "a click at half width sets half")
    sw.activate()
    t.equal(sw.count, 1, "the switch emits toggled")
    unplugged.activate()
    t.equal(unplugged.count, 0, "an unavailable device can't be chosen")
    speakers.activate()
    t.equal(speakers.count, 1, "an available device is chosen")
    t.done()
  })
}
