// Behaviour contract for the lock clock presentation.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.lock" as LockComponents

ShellRoot {
  QmlTest {
    id: t
  }

  LockComponents.LockClock {
    id: clock
    clockText: "12:34"
    dateText: "Tuesday  •  29 September"
  }

  Component.onCompleted: {
    t.equal(clock.clockText, "12:34", "lock clocks expose their time")
    t.equal(clock.dateText, "Tuesday  •  29 September", "lock clocks expose their date")
    t.check(clock.implicitHeight > 0, "lock clocks have measurable content")
    t.done()
  }
}
