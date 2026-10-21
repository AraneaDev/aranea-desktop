// Actual upstream idle service: custom window identity keeps/cancels its lock timer.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "upstream-idle" as Idle

ShellRoot {
  QmlTest {
    id: t
  }
  QtObject {
    id: host
    property var idleConfig: ({
        screensaver: 1,
        lock: 2
      })
  }
  Idle.Service {
    id: idle
    shell: host
  }
  Process {
    id: readEffects
    command: ["cat", Quickshell.env("ARANEA_TEST_SANDBOX") + "/idle-effects"]
    stdout: StdioCollector {
      onStreamFinished: {
        t.check(text.indexOf("omarchy-launch-screensaver") >= 0, "upstream launch dispatch reached the fake external boundary")
        t.equal(text.split("omarchy-system-lock").length - 1, 1, "only the armed cycle dispatches one real Process lock action")
        t.done()
      }
    }
  }
  // Deliver the actual compositor event shape for a custom mapped surface.
  function opened(address) {
    idle.handleHyprlandEvent({
      name: "openwindow",
      data: address + ",special:screensaver-DP-1,org.omarchy.screensaver,Aranea"
    })
  }
  // Deliver the corresponding compositor close event.
  function closed(address) {
    idle.handleHyprlandEvent({
      name: "closewindow",
      data: address
    })
  }
  // Observe upstream public status without accessing or replacing its timers.
  function state() {
    return JSON.parse(idle.statusJson())
  }
  Component.onCompleted: t.waitFor(function () {
    return idle.idleEnabled
  }, 2000, "upstream service loaded sandbox stay-awake state", function () {
    idle.startIdleCycle()
    idle.handleActiveSignal()
    t.check(state().timers.lock && state().timers.screensaverLaunchGrace, "startup activity preserves pending lock within actual launch grace")
    opened("aaa")
    opened("bbb")
    t.equal(state().screensaverWindows, 2, "exact custom class is recognized on two monitors")
    t.check(!state().timers.screensaverLaunchGrace, "first mapped custom surface ends upstream launch grace")
    idle.handleActiveSignal()
    closed("aaa")
    t.check(state().timers.lock && state().inIdleCycle, "one remaining custom surface keeps lock armed")
    closed("bbb")
    t.check(!state().timers.lock && !state().inIdleCycle, "last early custom close cancels upstream pending lock")
    t.step(1200, function () {
      t.check(!state().timers.lock, "canceled cycle stays canceled past its original deadline")
      idle.startIdleCycle()
      opened("ccc")
      idle.handleActiveSignal()
      t.check(state().timers.lock, "mapped startup activity preserves second pending lock")
      t.step(1300, function () {
        t.check(!state().inIdleCycle && !state().timers.lock, "actual upstream lock timer ends armed cycle")
        host.idleConfig = ({
            screensaver: 1,
            lock: 10
          })
        idle.startIdleCycle()
        idle.handleActiveSignal()
        t.step(2700, function () {
          t.check(state().inIdleCycle, "unmapped launch remains armed before actual three-second grace")
          t.step(500, function () {
            t.check(!state().inIdleCycle && !state().timers.lock, "actual three-second grace cancels an unmapped active launch")
            readEffects.running = true
          })
        })
      })
    })
  })
}
