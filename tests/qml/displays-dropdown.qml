// The assembled Aranea Displays dropdown, driven by a plain view object
// and its separate state properties in a real window with real pointer
// clicks: the header, the brightness, night light, keyboard light and
// displays sections hide on their inputs (text size and scale always
// show); every control emits its action keyed with its index and key (the
// brightness slider previews while dragging and commits on release or a
// wheel step); a pending request shows at once, pulsing busy; a change of
// only the selected scale, enabledDisplays or pendingDisplays keeps the
// pill and display-row delegates; the last enabled display's switch is
// disabled and a click on it, or its row, emits nothing; a click within
// 300 ms of a section appearing is ignored; no outline without
// cursor.active and exactly one with it; controls moved under a still
// pointer emit no hover; and every trailing element ends on one right
// content edge.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.monitor" as Monitor

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by full, as [name, arg], in emission order.
  property var actions: []

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // The scale pills, built once: no selected flag, which one is chosen
  // comes from selectedScale and pendingScale.
  readonly property var scaleRows: [
    {
      key: "1",
      label: "1×"
    },
    {
      key: "1.5",
      label: "1.5×"
    },
    {
      key: "2",
      label: "2×"
    },
    {
      key: "2.67",
      label: "2.67×"
    },
    {
      key: "3",
      label: "3×"
    }
  ]

  // The display rows, built once: no enabled flag, that comes from
  // enabledDisplays and pendingDisplays.
  readonly property var displayRows: [
    {
      key: "eDP-1",
      label: "eDP-1",
      detail: "3840×2160 · focused",
      glyph: String.fromCodePoint(0xf0322)
    },
    {
      key: "DP-2",
      label: "DP-2",
      detail: "2560×1440",
      glyph: String.fromCodePoint(0xf0379)
    }
  ]

  // The text size stops, built once.
  readonly property var stops: [9, 10, 11, 12, 14, 16, 20]

  // A view with CURSOR and OPTS: {brightness, nightlight, kbdMode, kbdMax,
  // scales, displays}; missing options give the full dropdown.
  function viewOf(cursor, opts) {
    var o = opts || {}
    return {
      header: {
        title: "Display",
        caption: "eDP-1 · 3840×2160 · 2.67×"
      },
      brightness: {
        visible: o.brightness !== undefined ? o.brightness : true,
        label: "Bright"
      },
      nightlight: {
        visible: o.nightlight !== undefined ? o.nightlight : true
      },
      kbd: {
        visible: o.kbdMode !== "none",
        mode: o.kbdMode || "switch",
        max: o.kbdMax || 1
      },
      textStops: stops,
      scales: o.scales || scaleRows,
      displays: o.displays || displayRows,
      cursor: cursor,
      keyHint: "↑↓ move · ←→ adjust · tab next"
    }
  }

  // A cursor object: ACTIVE on SECTION's INDEX.
  function cur(active, section, index) {
    return {
      active: active,
      section: section,
      index: index
    }
  }

  // Whether an action NAME with ARG (compared as JSON) was reported.
  function reported(name, arg) {
    var want = JSON.stringify([name, arg])
    return actions.some(function (a) {
      return JSON.stringify(a) === want
    })
  }

  // Actions other than hover.
  function nonHover() {
    return actions.filter(function (a) {
      return a[0] !== "hover"
    })
  }

  // Actions named NAME.
  function named(name) {
    return actions.filter(function (a) {
      return a[0] === name
    })
  }

  // How many cursor outlines in ITEM are drawn (a border or a fill).
  function litOutlines(item) {
    return t.findChildren(item, "cursorOutline").filter(function (o) {
      return o.visible && (o.border.width > 0 || o.color.a > 0)
    }).length
  }

  // Right edge of ITEM in HOST's coordinates.
  function rightEdge(item, host) {
    return item.mapToItem(host, item.width, 0).x
  }

  // The first child of ITEM named NAME.
  function one(item, name) {
    return t.findChild(item, name)
  }

  // The scale pills in DROPDOWN.
  function pillsOf(dropdown) {
    return t.findChildren(one(dropdown, "scaleSection"), "scalePill")
  }

  // The display rows in DROPDOWN.
  function rowsOf(dropdown) {
    return t.findChildren(one(dropdown, "displaysSection"), "displayRow")
  }

  // The display switches in DROPDOWN.
  function switchesOf(dropdown) {
    return t.findChildren(one(dropdown, "displaysSection"), "displaySwitch")
  }

  // Resets full's state properties to the baseline.
  function resetState() {
    full.brightnessPercent = 72
    full.nightlightOn = true
    full.nightlightCaption = "4000 K"
    full.nightlightPending = null
    full.kbdValue = 0
    full.kbdPending = -1
    full.textIndex = 3
    full.textPending = false
    full.selectedScale = "2.67"
    full.pendingScale = ""
    full.enabledDisplays = {
      "eDP-1": true,
      "DP-2": false
    }
    full.pendingDisplays = {}
    full.lastEnabled = "eDP-1"
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then ends the run.
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
    id: win
    implicitWidth: 420
    implicitHeight: 1400
    visible: true

    Column {
      x: 20
      width: 380
      spacing: 20

      Monitor.DisplaysDropdown {
        id: full
        width: 380
        view: viewOf(cur(false, "brightness", 0))
        brightnessPercent: 72
        nightlightOn: true
        nightlightCaption: "4000 K"
        kbdValue: 0
        textIndex: 3
        selectedScale: "2.67"
        enabledDisplays: ({
            "eDP-1": true,
            "DP-2": false
          })
        lastEnabled: "eDP-1"
        onAction: function (name, arg) {
          actions.push([name, arg])
        }
      }

      // One display, no backlight, no night light and no keyboard light.
      Monitor.DisplaysDropdown {
        id: bare
        width: 380
        view: viewOf(cur(false, "scale", 0), {
          brightness: false,
          nightlight: false,
          kbdMode: "none",
          displays: [displayRows[0]]
        })
        textIndex: 2
        selectedScale: "2"
      }

      // A stepped keyboard light (levels 0..3).
      Monitor.DisplaysDropdown {
        id: stepped
        width: 380
        view: viewOf(cur(false, "kbdlight", 0), {
          brightness: false,
          kbdMode: "slider",
          kbdMax: 3,
          displays: [displayRows[0]]
        })
        kbdValue: 1
        onAction: function (name, arg) {
          actions.push([name, arg])
        }
      }
    }
  }

  Component.onCompleted: run([[350, function () {
        // ---------- Header and sections ----------
        t.equal(one(full, "headerCaption").text, "EDP-1 · 3840×2160 · 2.67×", "the header caption is the view's, uppercased")
        t.check(one(full, "brightnessSection").visible, "brightness shows")
        t.equal(one(full, "brightnessCaption").text, "72% · Bright", "with its percent and level name")
        t.check(Math.abs(one(full, "brightnessSlider").value - 72) < 0.01, "the brightness slider sits at the percent")
        t.check(one(full, "nightlightRow").visible, "night light shows")
        t.equal(one(full, "nightlightCaption").text, "4000 K", "with its caption")
        t.check(one(full, "nightlightSwitch").checked, "its switch is on")
        t.check(one(full, "kbdRow").visible && one(full, "kbdSwitch").visible, "the keyboard light shows a switch")
        t.check(!one(full, "kbdSlider").visible, "and no slider for an on/off device")
        t.check(!one(full, "kbdSwitch").checked, "off at level 0")
        t.check(one(full, "textSection").visible, "text size shows")
        t.equal(one(full, "textCaption").text, "12 px", "with the stop in px")
        t.equal(t.findChildren(full, "textStop").map(function (s) {
          return s.text
        }), ["9", "10", "11", "12", "14", "16", "20"], "a label per text stop")
        t.check(Math.abs(one(full, "textSlider").value - 3) < 0.01, "the text slider sits on the stop index")
        t.check(one(full, "scaleSection").visible, "scale shows")
        t.equal(pillsOf(full).map(function (p) {
          return p.text
        }), ["1×", "1.5×", "2×", "2.67×", "3×"], "a pill per scale")
        t.check(pillsOf(full)[3].selected && !pillsOf(full)[0].selected, "the selected scale's pill reads selected")
        t.check(one(full, "displaysSection").visible, "displays show with two displays")
        t.equal(one(full, "displaysCount").text, "2", "with their count")
        t.equal(rowsOf(full).map(function (r) {
          return r.label
        }), ["eDP-1", "DP-2"], "a row per display")
        t.check(rowsOf(full)[0].active && !rowsOf(full)[1].active, "an enabled display's node is lit")
        t.check(switchesOf(full)[0].checked && !switchesOf(full)[1].checked, "the switches follow enabledDisplays")
        t.equal(one(full, "keyHint").text, "↑↓ move · ←→ adjust · tab next", "the key hint is the view's")

        t.check(!one(bare, "brightnessSection").visible, "no backlight hides brightness")
        t.check(!one(bare, "nightlightRow").visible, "night light hides")
        t.check(!one(bare, "kbdRow").visible, "the keyboard light hides without a device")
        t.check(one(bare, "textSection").visible && one(bare, "scaleSection").visible, "text size and scale always show")
        t.check(!one(bare, "displaysSection").visible, "one display hides the list")
        t.check(one(stepped, "kbdSlider").visible && !one(stepped, "kbdSwitch").visible, "a stepped keyboard light shows a slider")
        t.equal(one(stepped, "kbdCaption").text, "1/3", "with its level")

        // ---------- No outline without the cursor ----------
        t.equal(litOutlines(full), 0, "an inactive cursor draws no outline")
      }], [350, function () {
        // ---------- Keyed clicks ----------
        actions = []
        pointer.mouseClick(pillsOf(full)[2])
        t.check(reported("scale", {
          index: 2,
          key: "2"
        }) && nonHover().length === 1, "a pill click emits scale with its key")
        actions = []
        pointer.mouseClick(one(full, "nightlightSwitch"))
        t.check(reported("nightlight", {
          index: 0,
          key: "nightlight"
        }) && nonHover().length === 1, "the night light switch emits nightlight")
        actions = []
        pointer.mouseClick(one(full, "kbdSwitch"))
        t.check(reported("kbd", {
          index: 0,
          key: "kbdlight",
          value: 1
        }) && nonHover().length === 1, "the keyboard switch asks for its max when off")
        full.kbdValue = 1
        actions = []
        pointer.mouseClick(one(full, "kbdSwitch"))
        t.check(reported("kbd", {
          index: 0,
          key: "kbdlight",
          value: 0
        }), "and for 0 when on")
        full.kbdValue = 0
        actions = []
        pointer.mouseClick(switchesOf(full)[1])
        t.check(reported("display", {
          index: 1,
          key: "DP-2",
          enable: true
        }) && nonHover().length === 1, "a display switch emits display with its name")
        actions = []
        var row = rowsOf(full)[1]
        pointer.mouseClick(row, 40, row.height / 2)
        t.check(reported("display", {
          index: 1,
          key: "DP-2",
          enable: true
        }) && nonHover().length === 1, "and so does its row")

        // ---------- Sliders ----------
        actions = []
        var bright = one(full, "brightnessSlider")
        pointer.mousePress(bright, bright.width / 2, bright.height / 2)
        pointer.mouseMove(bright, bright.width / 4 + 3, bright.height / 2)
        t.check(named("brightnessPreview").length >= 1 && named("brightnessCommit").length === 0, "dragging brightness previews without committing")
        t.check(reported("brightnessPreview", {
          value: 50
        }), "a preview carries the percent")
        pointer.mouseRelease(bright, bright.width / 4 + 3, bright.height / 2)
        var commits = named("brightnessCommit")
        t.check(commits.length === 1 && commits[0][1].value === Math.round(commits[0][1].value) && commits[0][1].value < 50, "the release commits the dragged percent")
        actions = []
        pointer.mouseWheel(bright, bright.width / 2, bright.height / 2, 0, 120)
        t.check(reported("brightnessCommit", {
          value: 77
        }) && named("brightnessPreview").length === 0, "a wheel step commits five more")

        actions = []
        var text = one(full, "textSlider")
        pointer.mouseClick(text, text.width - 1, text.height / 2)
        t.check(reported("textSize", {
          index: 6,
          key: 20
        }) && nonHover().length === 1, "a text size click emits the stop's index and size")
        actions = []
        pointer.mouseClick(text, text.width * 0.5, text.height / 2)
        t.equal(nonHover().length, 0, "a click on the current stop emits nothing")

        actions = []
        var kbd = one(stepped, "kbdSlider")
        pointer.mouseClick(kbd, kbd.width - 1, kbd.height / 2)
        t.check(reported("kbd", {
          index: 0,
          key: "kbdlight",
          value: 3
        }), "a stepped keyboard slider emits the level")
        t.equal(litOutlines(full), 0, "clicks draw no outline")

        // ---------- Pending shows at once ----------
        actions = []
        full.nightlightOn = false
        full.nightlightPending = true
        t.check(one(full, "nightlightSwitch").checked && one(full, "nightlightSwitch").busy, "a pending night light shows on, pulsing")
        full.nightlightPending = null
        t.check(!one(full, "nightlightSwitch").checked && !one(full, "nightlightSwitch").busy, "and settles to the real state")
        full.nightlightOn = true
        full.kbdPending = 1
        t.check(one(full, "kbdSwitch").checked && one(full, "kbdSwitch").busy, "a pending keyboard light shows on, pulsing")
        full.kbdPending = -1
        t.check(!one(full, "kbdSwitch").busy, "and stops")
        stepped.kbdPending = 3
        t.check(Math.abs(one(stepped, "kbdSlider").value - 3) < 0.01 && one(stepped, "kbdSlider").busy, "a pending keyboard level moves the slider, pulsing")
        stepped.kbdPending = -1
        full.textIndex = 6
        full.textPending = true
        t.check(Math.abs(one(full, "textSlider").value - 6) < 0.01 && one(full, "textSlider").busy, "a pending text size pulses")
        t.equal(one(full, "textCaption").text, "20 px", "and names the new stop")
        full.textPending = false
        full.textIndex = 3
        t.check(!one(full, "textSlider").busy, "and stops")
        full.pendingScale = "3"
        t.check(pillsOf(full)[4].selected && pillsOf(full)[4].busy, "a pending scale reads selected, pulsing")
        t.check(!pillsOf(full)[3].selected && !pillsOf(full)[3].busy, "the old scale lets go at once")
        full.pendingScale = ""
        full.pendingDisplays = {
          "DP-2": true
        }
        t.check(switchesOf(full)[1].checked && switchesOf(full)[1].busy && rowsOf(full)[1].busy, "a pending display shows on, pulsing")
        t.check(!switchesOf(full)[0].busy, "only the pending display pulses")
        full.pendingDisplays = {}
        t.check(!switchesOf(full)[1].checked && !switchesOf(full)[1].busy, "and settles to the real state")

        // ---------- Identity across state changes ----------
        var pillsBefore = pillsOf(full)
        var rowsBefore = rowsOf(full)
        full.selectedScale = "1"
        full.pendingScale = "1.5"
        full.enabledDisplays = {
          "eDP-1": true,
          "DP-2": true
        }
        full.pendingDisplays = {
          "eDP-1": false
        }
        full.lastEnabled = ""
        full.view = viewOf(cur(false, "scale", 1))
        var pillsAfter = pillsOf(full)
        var rowsAfter = rowsOf(full)
        t.check(pillsAfter.length === 5 && pillsAfter.every(function (p, k) {
          return p === pillsBefore[k]
        }), "a scale selection change keeps the pill delegates")
        t.check(rowsAfter.length === 2 && rowsAfter.every(function (r, k) {
          return r === rowsBefore[k]
        }), "an enabledDisplays change keeps the display rows")
        t.check(switchesOf(full)[1].checked && !switchesOf(full)[0].checked, "and moves which switch reads on")
        resetState()

        // ---------- The last enabled display ----------
        t.check(!switchesOf(full)[0].enabled, "the last enabled display's switch is disabled")
        t.check(switchesOf(full)[1].enabled, "another display's switch is not")
        actions = []
        pointer.mouseClick(switchesOf(full)[0])
        var lastRow = rowsOf(full)[0]
        pointer.mouseClick(lastRow, 40, lastRow.height / 2)
        t.equal(nonHover().length, 0, "a click on its switch or its row emits nothing")
        full.lastEnabled = ""
        t.check(switchesOf(full)[0].enabled, "it enables again once another display is on")
        full.lastEnabled = "eDP-1"

        // ---------- One outline per cursor ----------
        var spots = [["brightness", 0], ["nightlight", 0], ["kbdlight", 0], ["textsize", 0], ["scale", 0], ["scale", 4], ["monitors", 0], ["monitors", 1]]
        for (var i = 0; i < spots.length; i++) {
          full.view = viewOf(cur(true, spots[i][0], spots[i][1]))
          t.equal(litOutlines(full), 1, "an active cursor on " + spots[i][0] + " " + spots[i][1] + " draws exactly one outline")
        }
        full.view = viewOf(cur(false, "scale", 1))
        t.equal(litOutlines(full), 0, "an inactive cursor draws none")

        // ---------- One right content edge ----------
        var edge = rightEdge(full, full)
        var trailing = [["brightness caption", one(full, "brightnessCaption")], ["brightness slider", one(full, "brightnessSlider")], ["night switch", one(full, "nightlightSwitch")], ["keyboard switch", one(full, "kbdSwitch")], ["text caption", one(full, "textCaption")], ["text slider", one(full, "textSlider")], ["last stop", t.findChildren(full, "textStop")[6]], ["last pill", pillsOf(full)[4]], ["displays count", one(full, "displaysCount")], ["last row", rowsOf(full)[1]], ["last switch", switchesOf(full)[1]]]
        for (var j = 0; j < trailing.length; j++)
          t.check(trailing[j][1] && Math.abs(rightEdge(trailing[j][1], full) - edge) < 0.5, trailing[j][0] + " ends on the content edge")
        t.check(Math.abs(rightEdge(one(stepped, "kbdSlider"), stepped) - rightEdge(stepped, stepped)) < 0.5, "the keyboard slider ends on the content edge")

        // ---------- Fresh clicks ----------
        full.view = viewOf(cur(false, "scale", 0), {
          brightness: false
        })
      }], [350, function () {
        freshFrom = pillsOf(full)[1].mapToItem(full, 0, 0).y
        actions = []
        // Brightness arrives late and pushes everything down.
        full.view = viewOf(cur(false, "scale", 0))
      }], [30, function () {
        t.check(pillsOf(full)[1].mapToItem(full, 0, 0).y > freshFrom, "brightness pushed the pills down")
        pointer.mouseClick(pillsOf(full)[1])
        pointer.mouseClick(one(full, "nightlightSwitch"))
        pointer.mouseClick(one(full, "kbdSwitch"))
        pointer.mouseClick(switchesOf(full)[1])
        var text = one(full, "textSlider")
        pointer.mouseClick(text, text.width - 1, text.height / 2)
        var bright = one(full, "brightnessSlider")
        pointer.mouseClick(bright, 10, bright.height / 2)
        t.equal(nonHover().length, 0, "clicks within 300 ms of a section appearing are ignored")
      }], [350, function () {
        pointer.mouseClick(pillsOf(full)[1])
        pointer.mouseClick(switchesOf(full)[1])
        t.check(reported("scale", {
          index: 1,
          key: "1.5"
        }) && reported("display", {
          index: 1,
          key: "DP-2",
          enable: true
        }), "clicks 300 ms after it are accepted")
        full.noteLayoutChange()
        actions = []
        pointer.mouseClick(pillsOf(full)[1])
        t.equal(nonHover().length, 0, "a click right after noteLayoutChange (a text reflow) is ignored")
      }], [350, function () {
        // ---------- A still pointer ----------
        full.disarmPointer()
        var pills = pillsOf(full)
        stillPoint = pills[1].mapToItem(full, pills[1].width / 2, pills[1].height / 2)
        actions = []
        pointer.mouseMove(full, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          section: "scale",
          index: 1,
          key: "1.5"
        }), "a real move over a pill reports hover with its key")
        actions = []
        full.view = viewOf(cur(false, "scale", 0), {
          scales: scaleRows.slice().reverse()
        })
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.equal(named("hover").length, 0, "pills rebuilt under a still pointer emit no hover")
        pointer.mouseMove(full, stillPoint.x, stillPoint.y + 2)
      }], [80, function () {
        t.check(reported("hover", {
          section: "scale",
          index: 1,
          key: "2.67"
        }), "a real move after the rebuild reports hover again")
        full.view = viewOf(cur(false, "scale", 0))
        var night = one(full, "nightlightSwitch")
        stillPoint = night.mapToItem(full, night.width / 2, night.height / 2)
        full.disarmPointer()
        actions = []
        pointer.mouseMove(full, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x - 4, stillPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          section: "nightlight",
          index: 0,
          key: "nightlight"
        }), "a real move over the night light row reports hover")
        var dp = switchesOf(full)[1]
        stillPoint = dp.mapToItem(full, dp.width / 2, dp.height / 2)
        full.disarmPointer()
        actions = []
        pointer.mouseMove(full, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x - 4, stillPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          section: "monitors",
          index: 1,
          key: "DP-2"
        }), "a real move over a display row reports hover with its name")
      }]])

  // A pill's position before brightness appeared.
  property real freshFrom: 0
  // The pointer position the still-pointer checks replay.
  property var stillPoint: null
}
