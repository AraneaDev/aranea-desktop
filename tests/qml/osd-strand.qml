// The OSD's level strand (OsdStrand.qml): the lit part runs the Filament
// strand gradient, mint to violet (DesignTokens.accent to strandEnd), over
// a hairline track, with the accent knob at the level; without progress a
// short fixed stub is lit instead. No font-dependent sizes are asserted.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.osd" as Osd
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }

  FloatingWindow {
    implicitWidth: 300
    implicitHeight: 60
    visible: true

    Osd.OsdStrand {
      id: strand
      width: 200
      height: 16
      fraction: 0.5
      hasProgress: true
      motionEnabled: false
    }
  }

  Component.onCompleted: {
    var fill = t.findChild(strand, "osdStrandFill")
    var knob = t.findChild(strand, "osdStrandKnob")
    var track = t.findChild(strand, "osdStrandTrack")
    t.check(fill !== null && knob !== null && track !== null, "the strand has a track, a fill and a knob")
    t.check(fill.gradient !== null, "the fill is a gradient, not a flat colour")
    var stops = fill.gradient ? fill.gradient.stops : []
    t.equal(stops.length, 2, "two gradient stops")
    t.equal(stops.length > 1 ? [stops[0].position, stops[1].position] : [], [0, 1], "the stops span the fill")
    t.check(stops.length > 1 && Qt.colorEqual(stops[0].color, Aranea.DesignTokens.accent), "the fill starts mint (accent)")
    t.check(stops.length > 1 && Qt.colorEqual(stops[1].color, Aranea.DesignTokens.strandEnd), "the fill ends violet (strandEnd)")
    t.equal(fill.gradient ? fill.gradient.orientation : -1, Gradient.Horizontal, "the gradient runs along the strand")
    t.equal(fill.width, 100, "the fill covers the fraction")
    t.equal(knob.x + knob.width / 2, 100, "the knob sits at the level")
    t.check(Qt.colorEqual(knob.color, Aranea.DesignTokens.accent), "the knob keeps the accent")
    t.check(fill.height > track.height, "the fill is thicker than the hairline track")
    strand.hasProgress = false
    t.equal(Math.round(fill.width), 56, "without progress a fixed stub is lit")
    t.equal(Math.round(knob.x + knob.width / 2), 56, "with the knob at its end")
    t.done()
  }
}
