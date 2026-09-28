// Self-test of the QML test runner: a passing check, an async step and a
// wait that polls until its condition holds.
import QtQuick
import Quickshell
import "lib"

ShellRoot {
  id: testRoot

  // Set a moment after start, for the waitFor check.
  property bool ready: false

  Timer {
    interval: 200
    running: true
    onTriggered: testRoot.ready = true
  }

  QmlTest {
    id: t
    Component.onCompleted: {
      t.equal(1 + 1, 2, "arithmetic")
      t.step(50, function () {
        t.check(true, "async step runs")
        t.waitFor(function () {
          return testRoot.ready
        }, 2000, "ready is set", function () {
          t.check(testRoot.ready, "waitFor continues once the condition holds")
          t.done()
        })
      })
    }
  }
}
