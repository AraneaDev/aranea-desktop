// Catches duplicate toggles, lost final intent, failed pending state and stale reads.
import QtQuick
import Quickshell
import "lib"

ShellRoot {
  id: root
  // Real persistent night-light command owner.
  property var owner: null
  QmlTest {
    id: t
  }
  DisplayFixture {
    id: fixture
  }
  Component.onCompleted: fixture.configure({
    reset: true
  }, function () {
    var component = Qt.createComponent("plugins/araneadev.monitor/NightlightController.qml")
    if (component.status !== Component.Ready) {
      t.check(false, "night light owner accepts pending toggles: " + component.errorString())
      t.done()
      return
    }
    root.owner = component.createObject(root)
    owner.readNight()
    t.waitFor(function () {
      return owner.nightAvailable
    }, 2000, "initial night status loads", function () {
      owner.toggleNightlight()
      owner.toggleNightlight()
      owner.toggleNightlight()
      t.equal(owner.nightPending, true, "rapid flips preview the final requested state")
      t.waitFor(function () {
        return owner.nightPending === null && owner.nightOn && fixture.state.nightToggleCount === 1 && fixture.state.events.length === 3
      }, 3000, "night light final intent confirms", function () {
        t.equal(fixture.state.events, [["omarchy-toggle-nightlight", "--status"], ["omarchy-toggle-nightlight"], ["omarchy-toggle-nightlight", "--status"]], "matching final intent needs one exact toggle then readback")
        owner.toggleNightlight()
        owner.toggleNightlight()
        t.waitFor(function () {
          return owner.nightSerial === 3 && owner.nightPending === null && owner.nightOn
        }, 3000, "opposite queued intent receives a second toggle", function () {
          t.equal(owner.nightCaption, "4000 K", "confirmed temperature updates the caption")
          fixture.configure({
            nightFail: true
          }, function () {
            owner.toggleNightlight()
            t.waitFor(function () {
              return owner.nightSerial === 4 && owner.nightPending === null
            }, 2000, "failed toggle releases pending state", function () {
              t.check(owner.nightOn, "failed toggle retains confirmed night state")
              fixture.configure({
                nightFail: false,
                nightReadDelay: 0.45
              }, function () {
                var before = fixture.state.nightReadCount
                owner.readNight()
                t.waitFor(function () {
                  return fixture.state.nightReadCount > before
                }, 2000, "pre-toggle status read is captured", function () {
                  owner.toggleNightlight()
                  t.waitFor(function () {
                    return owner.nightReadSerial === 5 && owner.nightOn
                  }, 3000, "stale status schedules a fresh generation", function () {
                    t.equal(owner.nightPending, false, "stale opposite status cannot settle the pending toggle")
                    t.waitFor(function () {
                      return owner.nightPending === null && !owner.nightOn
                    }, 3000, "fresh read confirms final night state", function () {
                      t.equal(owner.nightCaption, "Off", "fresh off state clears temperature caption")
                      t.done()
                    })
                  })
                })
              })
            })
          })
        })
      })
    })
  })
}
