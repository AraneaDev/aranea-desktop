// Self-test of the QML test runner: a passing check and an async step.
import QtQuick
import Quickshell
import "lib"

ShellRoot {
  QmlTest {
    id: t
    Component.onCompleted: {
      t.equal(1 + 1, 2, "arithmetic")
      t.step(50, function () {
        t.check(true, "async step runs")
        t.done()
      })
    }
  }
}
