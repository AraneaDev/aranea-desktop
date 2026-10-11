// Real spring timing: reversal, final settling, and reduced-motion interruption.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }
  Aranea.SpringValue {
    id: spring
    motionEnabled: true
  }
  Aranea.DisclosureSection {
    id: section
    width: 200
    motionEnabled: true
    Item {
      width: 200
      height: 100
    }
  }
  Component.onCompleted: t.step(20, function () {
    var heading = section.height
    spring.targetValue = 100
    section.expanded = true
    t.step(50, function () {
      t.check(spring.value > 0 && spring.value < 100, "spatial spring has intermediate frames: " + spring.value)
      t.check(section.height > heading && section.height < heading + 116, "disclosure reveals intermediate height: " + section.height + " baseline " + heading)
      var before = spring.value
      spring.targetValue = 0
      t.check(Math.abs(spring.value - before) < 0.01, "retarget keeps current position")
      section.expanded = false
      t.check(t.findChild(section, "disclosureContent").visible, "closing content remains visible while clipping away")
      t.check(!t.findChild(section, "disclosureContent").enabled, "closing content cannot accept input")
      spring.motionEnabled = false
      section.motionEnabled = false
      t.equal(spring.value, 0, "disabled spring snaps immediately")
      t.equal(spring.running, false, "disabled spring stops")
      t.equal(section.height, heading, "reduced-motion disclosure closes exactly")
      section.expanded = true
      t.equal(section.height, heading + 116, "reduced-motion disclosure opens exactly")
      spring.targetValue = 75
      t.equal(spring.value, 75, "disabled target change assigns final value")
      spring.targetValue = 0
      spring.motionEnabled = true
      spring.targetValue = 100
      spring.targetValue = 0
      t.step(250, function () {
        t.equal(spring.value, 0, "same-frame spatial reversal stays at the destination")
        spring.targetValue = 100
        t.step(50, function () {
          spring.targetValue = 0
          t.waitFor(function () {
            return !spring.running
          }, 3000, "spatial close settles after reversal", function () {
            t.equal(spring.value, 0, "reversed spatial spring reaches exact destination")
            t.done()
          })
        })
      })
    })
  })
}
