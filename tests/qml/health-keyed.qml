// The health dropdown's Filament rules, in a real window with real pointer
// events. A host wired like Panel.qml (the cursor key, the keyboard mode and
// HealthLogic.outlineIndex) drives the problems section: the mint outline
// shows only with the keyboard and never on hover, and Enter as the first
// key only reveals it; a real pointer move draws a row's hover fill but
// never moves the cursor or the outline; no problem row carries the
// selected highlight (problems are not a choice); problem rows are keyed
// (by id, falling back to the text) and a keyed action whose row changed
// underneath is refused; the rows stay the same delegates across a refresh
// that hands over a new array, and an equal list does not stamp the layout;
// a click right after the rows re-sort is refused and accepted once
// settled, as is a click right after the content grows (a side or bottom
// bar moves the rows then). The resources draw strand bars (gradient stops
// present) and the CPU trace on the shared LinkGraph (a non-empty grab).
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.health" as Health
import "plugins/araneadev.health/HealthLogic.js" as HealthLogic
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  id: host

  QmlTest {
    id: t
  }

  // The host's cursor key, as Panel.cursorKey.
  property string cursorKey: ""
  // The host's keyboard mode, as Panel.keyboardCursor.
  property bool keyboard: false
  // Activated rows, as [index, key], in order.
  property var activated: []
  // Hovered row indexes, in order.
  property var hovered: []
  // The layout stamp a step compares against.
  property real stampBefore: 0
  // The rows' delegates a step compares against.
  property var rowsBefore: []
  // The pointer's resting point.
  property var stillPoint: null

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // A problem row fixture: KEY (may be ""), SUMMARY and URGENCY.
  function problem(key, summary, urgency) {
    return {
      key: key,
      check: "unit",
      summary: summary,
      body: "",
      urgency: urgency,
      glyph: "",
      execArgv: []
    }
  }

  // The problems in their first order: one keyed only by its text.
  function firstRows() {
    return [problem("unit:system:a.service", "a.service failed", 2), problem("reboot", "Reboot to finish the kernel update", 1), problem("", "Container web exited (code 1)", 1)]
  }

  // The section's problem rows, in order.
  function rows() {
    var out = []
    for (var i = 0; i < section.problems.length; i++)
      out.push(section.rowAt(i))
    return out
  }

  // How many rows draw the mint outline.
  function outlined() {
    return t.findChildren(section, "cursorOutline").filter(function (o) {
      return o.border.width > 0
    }).length
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
    implicitWidth: 400
    implicitHeight: 520
    visible: true

    Canvas {
      id: probe
      // The grabbed image's url.
      property string src: ""
      // How many pixels of the image are not transparent, -1 before.
      property int lit: -1
      width: 360
      height: 40
      z: -1
      onImageLoaded: requestPaint()
      onPaint: {
        if (probe.src === "" || !probe.isImageLoaded(probe.src))
          return
        var ctx = getContext("2d")
        ctx.reset()
        ctx.drawImage(probe.src, 0, 0)
        var data = ctx.getImageData(0, 0, probe.width, probe.height).data
        var n = 0
        for (var i = 3; i < data.length; i += 4)
          if (data[i] > 0)
            n++
        probe.lit = n
      }
    }

    Column {
      id: stack
      x: 20
      width: 360
      spacing: 10

      Health.HealthProblemsSection {
        id: section
        width: 360
        problems: firstRows()
        hostContentHeight: stack.implicitHeight
        cursor: HealthLogic.outlineIndex(section.problems, host.cursorKey, host.keyboard)
        onProblemActivated: function (index, key) {
          host.keyboard = false
          host.activated = host.activated.concat([[index, key]])
        }
        onRowHovered: function (index) {
          host.hovered = host.hovered.concat([index])
        }
      }

      Health.HealthResourceSection {
        id: resources
        width: 360
        active: true
        metrics: ({
            cpu: 17,
            cpuHistory: [10, 12, 60, 15, 20, 18, 40, 22],
            load: [1.31, 1.64, 1.7],
            mem: {
              memUsed: 50,
              memTotal: 100,
              swapUsed: 0,
              swapTotal: 0
            },
            diskRows: [
              {
                target: "/",
                percent: 7,
                avail: 1000
              },
              {
                target: "/boot",
                percent: 78,
                avail: 1000
              }
            ],
            iface: "wlan0",
            rates: null
          })
      }

      // Content arriving below the problems (TOP, the swap line, a disk).
      Rectangle {
        id: grower
        width: 360
        height: 0
        color: "transparent"
      }
    }
  }

  Component.onCompleted: run([[400, function () {
        // ---------- Outline: keyboard only ----------
        t.equal(rows().length, 3, "one row per problem")
        t.equal(outlined(), 0, "no outline before the keyboard")
        var first = HealthLogic.cursorPress(section.problems, "", false)
        t.check(first.key === HealthLogic.problemKey(section.problems[0]) && first.keyboard && first.row === null, "Enter as the first key only reveals the cursor on the first problem")
        t.check(rows().every(function (r) {
          return !t.findChild(r, "selectedFill").visible
        }), "no problem row carries the selected highlight")
        t.equal(rows()[2].key, "Container web exited (code 1)", "a row without an id is keyed by its text")
        var next = HealthLogic.cursorMove(section.problems, host.cursorKey, host.keyboard, 1)
        host.cursorKey = next.key
        host.keyboard = next.keyboard
        t.check(rows()[0].hasCursor && outlined() === 1, "the first key reveals the outline on the first row")
        t.check(Qt.colorEqual(t.findChild(rows()[0], "nodeMarker").color, Aranea.DesignTokens.urgent), "a critical problem's node is urgent")
        t.check(Qt.colorEqual(t.findChild(rows()[1], "nodeMarker").color, Aranea.DesignTokens.attention), "an attention problem's node is amber")

        // ---------- Stable rows across a refresh ----------
        rowsBefore = rows()
        stampBefore = section.layoutChangedAt
        section.problems = firstRows()
        t.check(rows().every(function (r, i) {
          return r === rowsBefore[i]
        }), "a refresh with a new array keeps every row delegate")
        t.equal(section.layoutChangedAt, stampBefore, "an equal list rebuilt does not stamp")
        var reworded = firstRows()
        reworded[1].summary = "Reboot now"
        section.problems = reworded
        t.check(rows().every(function (r, i) {
          return r === rowsBefore[i]
        }) && rows()[1].label === "Reboot now", "a changed row keeps its delegate and shows the new text")
        section.problems = firstRows()

        // ---------- Keyed actions ----------
        section.activateRow(0, "reboot")
        section.activateRow(1, "")
        t.equal(activated.length, 0, "a keyed action whose row does not carry the key is refused")
        section.activateRow(1, "reboot")
        t.equal(JSON.stringify(activated), JSON.stringify([[1, "reboot"]]), "the matching row is accepted")
        activated = []
        pointer.mouseClick(rows()[1], 60, rows()[1].height / 2)
        t.equal(JSON.stringify(activated), JSON.stringify([[1, "reboot"]]), "a settled click reports its row's key")

        // ---------- Settle after a re-sort ----------
        activated = []
        stampBefore = section.layoutChangedAt
        section.problems = firstRows().reverse()
        t.check(section.layoutChangedAt > stampBefore, "a re-sort stamps the layout")
        t.check(rows().every(function (r, i) {
          return r === rowsBefore[i]
        }), "a re-sort keeps the delegates too")
        pointer.mouseClick(rows()[0], 60, rows()[0].height / 2)
        t.equal(activated.length, 0, "a click right after a re-sort is refused")
      }], [350, function () {
        pointer.mouseClick(rows()[0], 60, rows()[0].height / 2)
        t.equal(JSON.stringify(activated), JSON.stringify([[0, "Container web exited (code 1)"]]), "once settled, the re-sorted row takes the click with its own key")

        // ---------- Hover never outlines ----------
        host.keyboard = true
        host.cursorKey = "reboot"
        t.equal(outlined(), 1, "the keyboard outline is showing")
        section.disarmPointer()
        stillPoint = rows()[2].mapToItem(section, 60, rows()[2].height / 2)
        pointer.mouseMove(section, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(section, stillPoint.x + 4, stillPoint.y)
      }], [200, function () {
        t.check(hovered.indexOf(2) >= 0, "a real move over a row reports hover")
        t.check(t.findChild(rows()[2], "hoverFill").visible, "a real move draws the hover fill on that row")
        t.check(!t.findChild(rows()[0], "hoverFill").visible && !t.findChild(rows()[1], "hoverFill").visible, "and only there")
        t.equal(host.cursorKey, "reboot", "hover never moves the cursor key")
        t.check(outlined() === 1 && rows()[1].hasCursor && !rows()[2].hasCursor, "the outline stays on the keyboard's row")
        var press = HealthLogic.cursorPress(section.problems, host.cursorKey, host.keyboard)
        t.check(!!press.row && HealthLogic.problemKey(press.row) === "reboot", "Enter acts on the outlined row, not the hovered one")

        // ---------- Strand bars and the trace ----------
        var memBar = t.findChild(resources, "memBar")
        var fill = t.findChild(memBar, "filamentBarFill")
        t.check(Math.abs(memBar.fraction - 0.5) < 0.001, "the memory bar lights its share")
        t.check(fill.gradient.stops.length === 2 && Qt.colorEqual(fill.gradient.stops[0].color, Aranea.DesignTokens.accent) && Qt.colorEqual(fill.gradient.stops[1].color, Aranea.DesignTokens.strandEnd), "the memory bar's gradient stops are mint and violet")
        t.equal(t.findChildren(resources, "diskBar").length, 2, "one strand bar per disk")
        var trace = t.findChild(resources, "cpuTrace")
        t.check(trace.slots === 60 && trace.floor === 100 && !trace.secondary && trace.softFill, "the CPU trace is the shared graph over 60 samples, 0..100 %")
        t.equal(trace.points.rx.length, 8, "one trace point per sample")
        var file = Qt.resolvedUrl("health-trace-grab.png")
        trace.grabToImage(function (result) {
          result.saveToFile(decodeURIComponent(String(file).replace(/^file:\/\//, "")))
          probe.src = String(file)
          probe.loadImage(probe.src)
        })
      }], [600, function () {
        t.check(probe.lit > 50, "the trace grab has drawn pixels (" + probe.lit + ")")

        // ---------- Growth below the rows settles their clicks ----------
        activated = []
        stampBefore = section.layoutChangedAt
        grower.height = 40
      }], [40, function () {
        // The Column lays out on the next frame, as the card does.
        t.check(section.layoutChangedAt > stampBefore, "the content growing stamps the layout")
        pointer.mouseClick(rows()[1], 60, rows()[1].height / 2)
        t.equal(activated.length, 0, "a click within 300 ms of the growth is refused")
      }], [350, function () {
        pointer.mouseClick(rows()[1], 60, rows()[1].height / 2)
        t.equal(JSON.stringify(activated), JSON.stringify([[1, HealthLogic.problemKey(section.problems[1])]]), "a click after 350 ms is accepted")
      }]])
}
