// Real spring timing: reversal, final settling, and reduced-motion interruption.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }
  Aranea.SurfaceMotion {
    id: motion
    motionEnabled: true
  }
  Component.onCompleted: {
    t.equal(motion.opacity, 0, "closed starts transparent")
    t.equal(motion.present, false, "closed starts unmapped")
    motion.opened = true
    t.check(motion.present, "logical open maps immediately")
    t.step(60, function () {
      t.check(motion.opacity > 0 && motion.opacity < 1, "opening fade progresses")
      t.check(motion.scale > motion.closedScale, "opening spring progresses")
      motion.opened = false
      t.check(motion.present, "close retains decorative frames")
      t.step(30, function () {
        var before = motion.scale
        motion.opened = true
        t.check(Math.abs(motion.scale - before) < 0.001, "reopening preserves current spring position")
        t.waitFor(function () {
          return !motion.running
        }, 3000, "reopened settles", function () {
          t.equal(motion.scale, 1, "spring settles exactly at open scale")
          t.equal(motion.opacity, 1, "fade settles exactly opaque")
          motion.opened = false
          t.step(20, function () {
            motion.motionEnabled = false
            t.equal(motion.running, false, "disabling motion stops active transitions")
            t.equal(motion.present, false, "disabling motion unmaps closed surface immediately")
            t.equal(motion.opacity, 0, "disabled close snaps transparent")
            t.equal(motion.scale, motion.closedScale, "disabled close snaps scale")
            motion.opened = true
            t.equal(motion.scale, 1, "disabled open snaps full scale")
            t.equal(motion.opacity, 1, "disabled open snaps opaque")
            t.check(motion.present, "disabled open is present")
            motion.motionEnabled = true
            t.equal(motion.running, false, "enabling motion does not replay entrance")
            motion.opened = false
            t.waitFor(function () {
              return !motion.present
            }, 3000, "normal close releases presentation", function () {
              t.equal(motion.opacity, 0, "normal close reaches transparent")
              motion.opened = true
              motion.opened = false
              t.waitFor(function () {
                return !motion.running
              }, 3000, "same-frame reversal settles", function () {
                t.equal(motion.opacity, 0, "same-frame open/close stays closed")
                t.check(!motion.present, "same-frame reversal does not leave a ghost surface")
                t.equal(motion.scale, motion.closedScale, "same-frame reversal keeps closed scale")
                t.done()
              })
            })
          })
        })
      })
    })
  }
}
