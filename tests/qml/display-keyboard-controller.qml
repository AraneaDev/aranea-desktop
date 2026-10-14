// Catches repeated discovery, lost last-wins levels, stale reads and missing devices.
import QtQuick
import Quickshell
import "lib"

ShellRoot {
  id: root
  // Real persistent keyboard command owner.
  property var owner: null
  // Production component recreated for each hardware discovery scenario.
  property var factory: null
  QmlTest {
    id: t
  }
  DisplayFixture {
    id: fixture
  }
  // Create the real owner and exercise coalesced discovery.
  function makeOwner() {
    root.owner = factory.createObject(root)
    owner.readKbd()
    owner.readKbd()
    owner.readKbd()
  }
  // Exercise the stock off command on a one-level device.
  function switchDevice() {
    owner.destroy()
    fixture.configure({
      reset: true,
      kbdMax: 1,
      kbdValue: 1
    }, function () {
      makeOwner()
      t.waitFor(function () {
        return owner.kbdMax === 1
      }, 2000, "on-off device is discovered", function () {
        t.equal(owner.kbdMode, "switch", "on-off hardware selects switch controls")
        owner.setKbd(-99)
        t.waitFor(function () {
          return owner.kbdSerial === 1 && owner.kbdPending < 0 && owner.kbdValue === 0 && fixture.state.kbdValues.length === 1
        }, 2000, "keyboard off command confirms", function () {
          t.check(fixture.state.events.some(function (event) {
            return JSON.stringify(event) === '["omarchy-brightness-keyboard","off"]'
          }), "on-off hardware uses the stock keyboard-off argument array")
          missingDevice()
        })
      })
    })
  }
  // Exercise no-device discovery and refusal of keyboard requests.
  function missingDevice() {
    owner.destroy()
    fixture.configure({
      reset: true,
      kbdDevice: ""
    }, function () {
      makeOwner()
      t.waitFor(function () {
        return owner.kbdDeviceChecked
      }, 2000, "missing keyboard device discovery completes", function () {
        owner.setKbd(1)
        owner.readKbd()
        t.step(200, function () {
          t.equal(owner.kbdMode, "none", "missing keyboard device hides the control")
          t.equal(owner.kbdPending, -1, "missing device cannot accept a pending level")
          t.equal(fixture.state.events, [["ls", "/sys/class/leds"]], "missing hardware is discovered once and never sent a read or set")
          t.done()
        })
      })
    })
  }
  Component.onCompleted: fixture.configure({
    reset: true
  }, function () {
    root.factory = Qt.createComponent("plugins/araneadev.monitor/KeyboardBacklightController.qml")
    if (factory.status !== Component.Ready) {
      t.check(false, "keyboard light owner accepts queued levels: " + factory.errorString())
      t.done()
      return
    }
    makeOwner()
    t.waitFor(function () {
      return owner.kbdMax === 3
    }, 2000, "keyboard device and levels load", function () {
      t.equal(owner.kbdMode, "slider", "stepped keyboard hardware selects slider controls")
      owner.setKbd(1)
      owner.setKbd(2)
      owner.setKbd(999)
      t.equal(owner.kbdShownLevel(), 3, "latest queued keyboard level previews immediately")
      t.waitFor(function () {
        return owner.kbdSerial === 2 && owner.kbdPending < 0 && owner.kbdValue === 3 && fixture.state.kbdValues.length === 2 && fixture.state.events.length === 5
      }, 3000, "queued keyboard level confirms", function () {
        t.equal(fixture.state.kbdValues, [1, 3], "keyboard queue applies first and last request only")
        t.equal(fixture.state.events, [["ls", "/sys/class/leds"], ["brightnessctl", "-d", "platform::kbd_backlight", "-m"], ["brightnessctl", "-sd", "platform::kbd_backlight", "set", "1"], ["brightnessctl", "-sd", "platform::kbd_backlight", "set", "3"], ["brightnessctl", "-d", "platform::kbd_backlight", "-m"]], "discovery, sets and final read preserve exact argument arrays")
        fixture.configure({
          kbdFail: true
        }, function () {
          owner.setKbd(2)
          t.waitFor(function () {
            return owner.kbdSerial === 3 && owner.kbdPending < 0
          }, 2000, "failed keyboard command drops pending level", function () {
            t.equal(owner.kbdValue, 3, "failed command retains confirmed keyboard level")
            fixture.configure({
              kbdFail: false,
              kbdReadDelay: 0.45
            }, function () {
              var before = fixture.state.kbdReadCount
              owner.readKbd()
              t.waitFor(function () {
                return fixture.state.kbdReadCount > before
              }, 2000, "pre-command keyboard read is captured", function () {
                owner.setKbd(2)
                t.waitFor(function () {
                  return owner.kbdReadSerial === 4 && owner.kbdValue === 3
                }, 3000, "stale keyboard read schedules a fresh generation", function () {
                  t.equal(owner.kbdPending, 2, "stale opposite read cannot settle the keyboard request")
                  t.waitFor(function () {
                    return owner.kbdPending < 0 && owner.kbdValue === 2
                  }, 3000, "fresh keyboard read confirms final level", switchDevice)
                })
              })
            })
          })
        })
      })
    })
  })
}
