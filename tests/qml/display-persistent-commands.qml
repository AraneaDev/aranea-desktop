// Catches command owners tied to popup visibility or lost public Panel forwarding.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.monitor" as Monitor

ShellRoot {
  QmlTest {
    id: t
  }
  DisplayFixture {
    id: fixture
  }
  Window {
    visible: true
    width: 1000
    height: 800
    Monitor.DisplayPanel {
      id: display
    }
  }
  Component.onCompleted: fixture.configure({
    nightDelay: 0.35,
    kbdDelay: 0.35,
    textDelay: 0.35
  }, function () {
    display.toggleNightlight()
    display.setKbd(3)
    t.equal(display.nightPending, null, "hidden night-light row refuses a toggle before discovery")
    t.equal(display.kbdPending, -1, "hidden keyboard row refuses a level before discovery")
    display.open()
    t.waitFor(function () {
      return display.nightAvailable && display.kbdMax === 3
    }, 3000, "real Display panel discovers controllable rows", function () {
      display.requestTextStop(4)
      display.toggleNightlight()
      display.setKbd(3)
      t.check(display.reflowingText, "Panel retains text reflow hover policy")
      display.close()
      t.check(!display.opened, "real Display popup closes while commands are accepted")
      t.equal(display.textSizePreviewIndex, 4, "public text preview remains pending after close")
      t.equal(display.nightPending, true, "public night-light intent remains pending after close")
      t.equal(display.kbdPending, 3, "public keyboard intent remains pending after close")
      t.waitFor(function () {
        return fixture.state.textValues.length === 1 && display.nightSerial === 1 && display.nightPending === null && display.nightOn && display.kbdSerial === 1 && display.kbdPending < 0 && display.kbdValue === 3
      }, 4000, "all accepted commands and readback complete after popup closure", function () {
        t.equal(fixture.state.textValues, [14], "closed popup still applies the accepted text command")
        t.check(!display.opened, "command completion keeps the popup closed")
        t.equal(display.nightCaption, "4000 K", "closed Panel forwards confirmed night caption")
        t.equal(display.kbdShownLevel(), 3, "closed Panel forwards confirmed keyboard level")
        t.done()
      })
    })
  })
}
