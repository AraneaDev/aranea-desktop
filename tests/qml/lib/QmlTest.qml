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

  // Polls COND every 50 ms and runs FN once it returns true (file loads,
  // processes, Qt.callLater work), however slow the machine. After TIMEOUT
  // ms without it, NAME fails and the run ends. An exception in FN fails
  // the test like in step().
  function waitFor(cond, timeout, name, fn) {
    var started = Date.now()
    var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 50; repeat: true }', t)
    timer.triggered.connect(function () {
      var ready = false
      try {
        ready = !!cond()
      } catch (e) {
        ready = false
      }
      if (!ready && Date.now() - started < timeout)
        return
      timer.stop()
      timer.destroy()
      if (!ready) {
        failures += 1
        console.log("QMLTEST FAIL " + name + " (timed out after " + timeout + " ms)")
        done()
        return
      }
      try {
        fn()
      } catch (e) {
        failures += 1
        console.log("QMLTEST FAIL exception: " + e)
        done()
      }
    })
    timer.start()
  }

  // Ends the test run; the runner stops quickshell when it sees this line.
  function done() {
    console.log("QMLTEST DONE " + failures)
  }

  // Depth-first search over ROOT's data (every declared child, visual or
  // not, e.g. Items, Animations, Timers) and contentItem, where present,
  // for the first descendant whose objectName is NAME; null when none
  // matches.
  function findChild(root, name) {
    if (!root)
      return null
    var kids = []
    if (root.contentItem)
      kids.push(root.contentItem)
    if (root.data)
      for (var i = 0; i < root.data.length; i++)
        kids.push(root.data[i])
    for (var j = 0; j < kids.length; j++) {
      var kid = kids[j]
      if (!kid)
        continue
      if (kid.objectName === name)
        return kid
      var found = findChild(kid, name)
      if (found)
        return found
    }
    return null
  }

  // Depth-first search over ROOT's data (every declared child, visual or
  // not, e.g. Items, Animations, Timers) and contentItem, where present,
  // for every descendant whose objectName is NAME, in depth-first order.
  function findChildren(root, name) {
    var matches = []
    if (!root)
      return matches
    var kids = []
    if (root.contentItem)
      kids.push(root.contentItem)
    if (root.data)
      for (var i = 0; i < root.data.length; i++)
        kids.push(root.data[i])
    for (var j = 0; j < kids.length; j++) {
      var kid = kids[j]
      if (!kid)
        continue
      if (kid.objectName === name)
        matches.push(kid)
      matches = matches.concat(findChildren(kid, name))
    }
    return matches
  }
}
