// The Aranea Bluetooth view's Filament click rules, in a real window with
// real pointer events: the power switch shows the view's pending state
// (on and busy) and falls back to the adapter's own without one; row
// actions carry the device address and a keyed action whose row changed
// underneath (a re-sort) is refused; a section's keys changing, a section
// showing or hiding and the scanning pulse stamp the layout (an equal list
// rebuilt does not); clicks on a row, its right-click area and the power
// switch within 300 ms of a stamp are refused and accepted after; and a
// row sliding under a still pointer emits no hover and takes no click.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.bluetooth" as Bluetooth

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by full, as [name, arg], in emission order.
  property var actions: []
  // The layout stamp a step compares against.
  property real stampBefore: 0
  // The pointer's resting point for the still-pointer checks.
  property var stillPoint: null

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // A device row fixture: KEY and LABEL, idle, forgettable unless NOFORGET.
  function dev(key, label, noForget) {
    return {
      key: key,
      label: label,
      glyph: "",
      detail: "",
      busy: false,
      forgettable: !noForget
    }
  }

  // The paired devices, in their first order.
  readonly property var knownRows: [dev("BB:1", "MX Master 3S"), dev("BB:2", "Pixel 8"), dev("BB:3", "Keychron K3")]

  // A view with KNOWN as Paired, DISCOVERED as Available, SCANNING and
  // POWER ({on, busy}, or undefined for none).
  function viewOf(known, discovered, scanning, power) {
    var v = {
      glyph: "",
      caption: "",
      enabled: true,
      hasAdapter: true,
      toggleHint: "Turn Bluetooth off",
      headerCursor: false,
      open: true,
      scanning: scanning,
      cursor: {
        active: false,
        section: "",
        index: -1,
        action: false
      },
      connected: [],
      known: known,
      discovered: discovered,
      signals: {},
      emptyText: ""
    }
    if (power !== undefined)
      v.power = power
    return v
  }

  // Actions other than hover.
  function nonHover() {
    return actions.filter(function (a) {
      return a[0] !== "hover"
    })
  }

  // Whether an action NAME with ARG (compared as JSON) was reported.
  function reported(name, arg) {
    var want = JSON.stringify([name, arg])
    return actions.some(function (a) {
      return JSON.stringify(a) === want
    })
  }

  // Paired's device rows, in order.
  function pairedRows() {
    return t.findChildren(t.findChild(full, "pairedSection"), "deviceRow")
  }

  // Paired's right-click areas, in order.
  function pairedSecondary() {
    return t.findChildren(t.findChild(full, "pairedSection"), "secondaryArea")
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then finishes.
  function run(steps) {
    if (steps.length === 0) {
      t.done()
      return
    }
    t.step(steps[0][0], function () {
      steps[0][1]()
      run(steps.slice(1))
    })
  }

  FloatingWindow {
    implicitWidth: 380
    implicitHeight: 420
    visible: true

    Bluetooth.BluetoothDropdown {
      id: full
      width: 360
      view: viewOf(knownRows, [dev("CC:1", "JBL Flip 6", true)], true, {
        on: true,
        busy: true
      })
      onAction: function (name, arg) {
        actions.push([name, arg])
      }
    }
  }

  Component.onCompleted: run([[400, function () {
        // ---------- Power switch: pending state ----------
        var sw = t.findChild(full, "powerSwitch")
        t.check(sw !== null && sw.checked && sw.busy, "the power switch shows the pending state on and busy")
        t.check(sw.clickGate !== null, "the power switch settles its clicks")
        full.view = viewOf(knownRows, [dev("CC:1", "JBL Flip 6", true)], true, {
          on: false,
          busy: false
        })
        t.check(!sw.checked && !sw.busy, "an idle power state shows off and still")
        var plain = viewOf(knownRows, [dev("CC:1", "JBL Flip 6", true)], true)
        full.view = plain
        t.check(sw.checked && !sw.busy, "without a power state the switch follows the adapter")

        // ---------- Keyed row actions ----------
        actions = []
        pointer.mouseClick(pairedRows()[1], 60, pairedRows()[1].height / 2)
        t.check(reported("primary", {
          section: "known",
          index: 1,
          key: "BB:2"
        }), "a settled click reports primary with the row's key")
        actions = []
        pointer.mouseClick(pairedSecondary()[2], 60, pairedSecondary()[2].height / 2, Qt.RightButton)
        t.check(reported("secondary", {
          section: "known",
          index: 2,
          key: "BB:3"
        }), "a settled right-click reports secondary with the row's key")

        // A re-sort: BB:1 moves from row 0 to row 2.
        actions = []
        stampBefore = full.layoutChangedAt
        full.view = viewOf(knownRows.slice().reverse(), [dev("CC:1", "JBL Flip 6", true)], true)
        t.check(full.layoutChangedAt > stampBefore, "a re-sort of Paired stamps the layout")
        full.rowAction("primary", "known", 0, "BB:1")
        full.rowAction("forget", "known", 0, "BB:1")
        t.equal(nonHover().length, 0, "a keyed action whose row changed underneath is refused")
        full.rowAction("forget", "known", 2, "BB:1")
        t.check(reported("forget", {
          section: "known",
          index: 2,
          key: "BB:1"
        }), "the same key at its new row is accepted")
        actions = []
        pointer.mouseClick(pairedRows()[0], 60, pairedRows()[0].height / 2)
        pointer.mouseClick(pairedSecondary()[1], 60, pairedSecondary()[1].height / 2, Qt.RightButton)
        t.equal(nonHover().length, 0, "clicks right after a re-sort are refused (row and right-click)")
      }], [350, function () {
        actions = []
        pointer.mouseClick(pairedRows()[0], 60, pairedRows()[0].height / 2)
        t.check(reported("primary", {
          section: "known",
          index: 0,
          key: "BB:3"
        }), "once settled, the re-sorted row takes the click with its own key")

        // ---------- Stamps ----------
        stampBefore = full.layoutChangedAt
        full.view = viewOf(knownRows.slice().reverse().map(function (r) {
          return Object.assign({}, r)
        }), [dev("CC:1", "JBL Flip 6", true)], true)
        t.equal(full.layoutChangedAt, stampBefore, "an equal list rebuilt does not stamp")
        full.view = viewOf(knownRows.slice().reverse(), [dev("CC:1", "JBL Flip 6", true), dev("CC:2", "Galaxy Buds2", true)], true)
        t.check(full.layoutChangedAt > stampBefore, "a device joining Available stamps")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf(knownRows.slice().reverse(), [], true)
        t.check(full.layoutChangedAt > stampBefore, "Available hiding stamps")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf(knownRows.slice().reverse(), [], false)
        t.check(full.layoutChangedAt > stampBefore, "the scanning pulse hiding stamps (the header shrinks)")
        t.check(!t.findChild(full, "scanPulse").visible, "the pulse is hidden")
      }], [350, function () {
        // ---------- Settle window after a stamp ----------
        var sw = t.findChild(full, "powerSwitch")
        actions = []
        full.noteLayoutChange()
        pointer.mouseClick(pairedRows()[1], 60, pairedRows()[1].height / 2)
        pointer.mouseClick(pairedSecondary()[1], 60, pairedSecondary()[1].height / 2, Qt.RightButton)
        pointer.mouseClick(sw)
        t.equal(nonHover().length, 0, "clicks right after a stamp are refused (row, right-click, power switch)")
      }], [60, function () {
        var sw = t.findChild(full, "powerSwitch")
        pointer.mouseClick(sw)
        t.equal(nonHover().length, 0, "and still refused inside the settle window")
      }], [350, function () {
        var sw = t.findChild(full, "powerSwitch")
        actions = []
        pointer.mouseClick(sw)
        pointer.mouseClick(pairedSecondary()[1], 60, pairedSecondary()[1].height / 2, Qt.RightButton)
        t.check(reported("toggleBluetooth", null), "a settled power click toggles")
        t.check(reported("secondary", {
          section: "known",
          index: 1,
          key: "BB:2"
        }), "a settled right-click is accepted")

        // ---------- A still pointer ----------
        full.disarmPointer()
        var r1 = pairedRows()[1]
        stillPoint = r1.mapToItem(full, 60, r1.height / 2)
        pointer.mouseMove(full, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [400, function () {
        t.check(actions.some(function (a) {
          return a[0] === "hover" && a[1].section === "known" && a[1].index === 1
        }), "a real move over a row reports hover")
        actions = []
        // The first device leaves: the next slides under the still pointer.
        full.view = viewOf(knownRows.slice().reverse().slice(1), [], false)
      }], [60, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
        t.equal(actions.filter(function (a) {
          return a[0] === "hover"
        }).length, 0, "a row sliding under a still pointer emits no hover")
        pointer.mouseClick(full, stillPoint.x + 4, stillPoint.y)
        t.equal(nonHover().length, 0, "nor takes a click inside the settle window")
      }]])
}
