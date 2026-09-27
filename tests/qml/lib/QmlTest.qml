// Minimal assertion helper for the offscreen QML behaviour tests
// (tests/qml-behaviour.test.sh reads the QMLTEST lines it prints).
import QtQuick

Item {
  id: t

  // Checks that failed so far.
  property int failures: 0

  // Reports NAME as passed when COND is true, failed otherwise.
  function check(cond, name) {
    if (cond) {
      console.log("QMLTEST PASS " + name)
    } else {
      failures += 1
      console.log("QMLTEST FAIL " + name)
    }
  }

  // Compares two values as JSON and reports NAME, with both values on failure.
  function equal(actual, expected, name) {
    var a = JSON.stringify(actual)
    var e = JSON.stringify(expected)
    if (a === e) {
      console.log("QMLTEST PASS " + name)
    } else {
      failures += 1
      console.log("QMLTEST FAIL " + name + ": got " + a + ", expected " + e)
    }
  }

  // Runs FN after DELAY ms (file writes, timers, Qt.callLater work); an
  // exception fails the test and ends the run.
  function step(delay, fn) {
    var timer = Qt.createQmlObject('import QtQuick; Timer {}', t)
    timer.interval = delay
    timer.triggered.connect(function () {
      try {
        fn()
      } catch (e) {
        failures += 1
        console.log("QMLTEST FAIL exception: " + e)
        done()
      }
      timer.destroy()
    })
    timer.start()
  }

  // Ends the test run; the runner stops quickshell when it sees this line.
  function done() {
    console.log("QMLTEST DONE " + failures)
  }
}
