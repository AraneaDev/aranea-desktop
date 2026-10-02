// The assembled Aranea Power dropdown, driven by a plain view object in a
// real window with real pointer clicks: the hero draws the battery cell
// (its fill following fraction), "Battery", the status line (faded by
// statusOpacity) and the big percentage; the details grid keeps the view's
// order; the CHARGE, POWER DRAW and POWER PROFILE sections hide on their
// inputs; profile pills emit setProfile with the index and key, but not
// within 300 ms of being built or of the history section appearing above them;
// no outline without cursor.active and exactly one with it; changing only
// drawSamples, historySegments or statusOpacity keeps the pill delegates;
// pills rebuilt under a still pointer emit no hover; and every trailing
// element ends on one right content edge.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.power" as Power

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

  // The profile rows, built once so a rebuilt view keeps the same model.
  readonly property var profileRows: [
    {
      key: "power-saver",
      label: "Power saver",
      glyph: String.fromCodePoint(0xf032a),
      selected: false
    },
    {
      key: "balanced",
      label: "Balanced",
      glyph: String.fromCodePoint(0xf029a),
      selected: true
    },
    {
      key: "performance",
      label: "Performance",
      glyph: String.fromCodePoint(0xf04c5),
      selected: false
    }
  ]

  // The details, built once.
  readonly property var detailRows: [
    {
      label: "Time left",
      value: "3 h 40 min"
    },
    {
      label: "Discharging",
      value: "7.8 W"
    },
    {
      label: "Battery size",
      value: "58 Wh"
    },
    {
      label: "Charge cycles",
      value: "112"
    }
  ]

  // A view with CURSOR, the history section shown when HISTORY, the draw
  // section when DRAW, and PROFILES.
  function viewOf(cursor, history, draw, profiles) {
    return {
      hero: {
        glyph: "",
        fraction: 0.62,
        status: "Sipping juice",
        percent: "62"
      },
      details: detailRows,
      history: {
        visible: history,
        summary: "100% → 62%",
        startLabel: "yesterday 09:00"
      },
      draw: {
        visible: draw,
        caption: "7.8 W"
      },
      profiles: profiles,
      cursor: cursor,
      keyHint: "←→ pick · enter set · tab next"
    }
  }

  // The full view, keeping its rows, with the cursor C.
  function withCursor(c) {
    return viewOf(c, true, true, profileRows)
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

  // The profile pills in DROPDOWN.
  function pillsOf(dropdown) {
    return t.findChildren(t.findChild(dropdown, "profilesSection"), "profilePill")
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

  // History segments in unit coordinates: two runs with a gap.
  readonly property var segments: [[
      {
        x: 0,
        y: 0
      },
      {
        x: 0.3,
        y: 0.1
      }
    ], [
      {
        x: 0.5,
        y: 0.2
      },
      {
        x: 0.98,
        y: 0.38
      }
    ]]

  FloatingWindow {
    id: win
    implicitWidth: 420
    implicitHeight: 1600
    visible: true

    Column {
      x: 20
      width: 380
      spacing: 20

      Power.PowerDropdown {
        id: full
        width: 380
        view: withCursor(cur(false, "profiles", 0))
        historySegments: segments
        drawSamples: [
          {
            rx: 6,
            tx: 0
          },
          {
            rx: 7.8,
            tx: 0
          }
        ]
        nowPercent: 62
        onAction: function (name, arg) {
          actions.push([name, arg])
        }
      }

      // A desktop: no battery, only the profiles.
      Power.PowerDropdown {
        id: desktop
        width: 380
        view: ({
            hero: null,
            details: [],
            history: {
              visible: false,
              summary: "",
              startLabel: ""
            },
            draw: {
              visible: false,
              caption: ""
            },
            profiles: profileRows,
            cursor: {
              active: false,
              section: "profiles",
              index: 0
            },
            keyHint: "←→ pick · enter set"
          })
      }

      // No profiles at all.
      Power.PowerDropdown {
        id: bare
        width: 380
        view: viewOf(cur(false, "profiles", 0), false, false, [])
      }
    }
  }

  Component.onCompleted: run([[350, function () {
        // ---------- Hero ----------
        var hero = t.findChild(full, "powerHero")
        t.check(hero !== null && hero.visible, "the hero shows")
        t.equal(t.findChild(hero, "heroTitle").text, "Battery", "the hero title")
        t.equal(t.findChild(hero, "heroStatus").text, "Sipping juice", "the status line")
        t.equal(t.findChild(hero, "heroPercent").text, "62", "the big percentage")
        var fill = t.findChild(hero, "batteryFill")
        var track = t.findChild(hero, "batteryTrack")
        t.check(Math.abs(fill.width - track.width * 0.62) < 0.5, "the fill width follows fraction")
        var v = withCursor(cur(false, "profiles", 0))
        v.hero.fraction = 0.25
        full.view = v
        t.check(Math.abs(t.findChild(hero, "batteryFill").width - track.width * 0.25) < 0.5, "and changes with it")
        v = withCursor(cur(false, "profiles", 0))
        v.hero.fraction = 1.4
        full.view = v
        t.check(Math.abs(t.findChild(hero, "batteryFill").width - track.width) < 0.5, "clamped at full")
        full.view = withCursor(cur(false, "profiles", 0))
        full.statusOpacity = 0.3
        t.check(Math.abs(t.findChild(hero, "heroStatus").opacity - 0.3) < 0.01, "statusOpacity fades the status line")
        full.statusOpacity = 1

        // ---------- Details ----------
        var labels = t.findChildren(full, "detailLabel").map(function (l) {
          return l.text
        })
        t.equal(labels, ["Time left", "Discharging", "Battery size", "Charge cycles"], "the details keep the view's order")
        var values = t.findChildren(full, "detailValue")
        t.equal(values[3].text, "112", "with their values")
        t.check(values[0].mapToItem(full, 0, 0).y === values[1].mapToItem(full, 0, 0).y && values[2].mapToItem(full, 0, 0).y > values[0].mapToItem(full, 0, 0).y, "two pairs per line (four columns)")

        // ---------- Sections ----------
        t.check(t.findChild(full, "historySection").visible, "the history section shows")
        t.equal(t.findChild(full, "historySummary").text, "100% → 62%", "with its summary")
        t.equal(t.findChild(full, "historyStart").text, "yesterday 09:00", "the start label")
        t.equal(t.findChild(full, "historyNow").text, "now", "the now label")
        var hist = t.findChild(full, "powerHistory")
        t.equal(hist.segments.length, 2, "the history graph gets the segments")
        t.check(Math.abs(hist.height - Style.space(44)) < 0.5, "a 44 px history graph")
        t.check(t.findChild(full, "drawSection").visible, "the draw section shows")
        t.equal(t.findChild(full, "drawCaption").text, "7.8 W", "with its caption")
        var draw = t.findChild(full, "powerDraw")
        t.equal(draw.samples.length, 2, "the draw trace gets the samples")
        t.check(Math.abs(draw.height - Style.space(26)) < 0.5, "a 26 px draw trace")
        t.check(t.findChild(full, "profilesSection").visible, "the profiles show")
        t.equal(pillsOf(full).map(function (p) {
          return p.text
        }), [profileRows[0].glyph + " Power saver", profileRows[1].glyph + " Balanced", profileRows[2].glyph + " Performance"], "a pill per profile with its glyph")
        t.check(pillsOf(full)[1].selected && !pillsOf(full)[0].selected, "the selected profile's pill is selected")
        t.equal(t.findChild(full, "keyHint").text, "←→ pick · enter set · tab next", "the key hint is the view's")

        t.check(!t.findChild(bare, "historySection").visible, "history hides")
        t.check(!t.findChild(bare, "drawSection").visible, "draw hides")
        t.check(!t.findChild(bare, "profilesSection").visible, "no profiles hides the section")
        t.check(!t.findChild(desktop, "powerHero").visible, "no hero hides it")
        t.check(!t.findChild(desktop, "detailsSection").visible, "no details hide the grid")
        t.check(t.findChild(desktop, "profilesSection").visible, "a desktop still shows the profiles")

        // ---------- No outline without the cursor ----------
        t.equal(litOutlines(full), 0, "an inactive cursor draws no outline")
      }], [350, function () {
        // ---------- Clicks ----------
        var pills = pillsOf(full)
        actions = []
        pointer.mouseClick(pills[2])
        t.check(reported("setProfile", {
          index: 2,
          key: "performance"
        }) && nonHover().length === 1, "a pill click emits setProfile with its key")
        actions = []
        pointer.mouseClick(pills[0])
        t.check(reported("setProfile", {
          index: 0,
          key: "power-saver"
        }), "another pill names its own key")
        t.equal(litOutlines(full), 0, "clicks draw no outline")

        // ---------- One outline per cursor ----------
        for (var i = 0; i < 3; i++) {
          full.view = withCursor(cur(true, "profiles", i))
          t.equal(litOutlines(full), 1, "an active cursor on profile " + i + " draws exactly one outline")
          t.check(pillsOf(full)[i].hasCursor, "on the pill it names")
        }
        full.view = withCursor(cur(false, "profiles", 1))
        t.equal(litOutlines(full), 0, "an inactive cursor draws none")

        // ---------- One right content edge ----------
        var edge = rightEdge(full, full)
        var trailing = [["percent", t.findChild(full, "heroPercentBlock")], ["details", t.findChild(full, "detailsSection")], ["last value", t.findChildren(full, "detailValue")[3]], ["summary", t.findChild(full, "historySummary")], ["history", t.findChild(full, "powerHistory")], ["now label", t.findChild(full, "historyNow")], ["draw caption", t.findChild(full, "drawCaption")], ["draw", t.findChild(full, "powerDraw")], ["last pill", pillsOf(full)[2]]]
        for (var j = 0; j < trailing.length; j++)
          t.check(trailing[j][1] && Math.abs(rightEdge(trailing[j][1], full) - edge) < 0.5, trailing[j][0] + " ends on the content edge")

        // ---------- Identity across refreshes ----------
        identityBefore = pillsOf(full)
        full.drawSamples = [
          {
            rx: 6,
            tx: 0
          },
          {
            rx: 7.8,
            tx: 0
          },
          {
            rx: 9,
            tx: 0
          }
        ]
        full.historySegments = [segments[1]]
        full.statusOpacity = 0.5
        full.nowPercent = 61
        var after = pillsOf(full)
        t.check(after.length === 3 && after.every(function (p, k) {
          return p === identityBefore[k]
        }), "drawSamples, historySegments and statusOpacity keep the pill delegates")
        t.equal(t.findChild(full, "powerDraw").samples.length, 3, "new samples reach the draw trace")
        t.equal(t.findChild(full, "powerHistory").segments.length, 1, "new segments reach the history graph")
        full.statusOpacity = 1

        // ---------- A fresh click ----------
        full.view = viewOf(cur(false, "profiles", 0), false, true, profileRows)
      }], [350, function () {
        var pills = pillsOf(full)
        actions = []
        pointer.mouseClick(pills[1])
        t.check(reported("setProfile", {
          index: 1,
          key: "balanced"
        }), "a settled pill takes a click with history hidden")
        freshFrom = pills[1].mapToItem(full, 0, 0).y
        actions = []
        // The history arrives late and pushes the pills down.
        full.view = viewOf(cur(false, "profiles", 0), true, true, profileRows)
      }], [30, function () {
        var pills = pillsOf(full)
        t.check(pills[1].mapToItem(full, 0, 0).y > freshFrom, "the history pushed the pills down")
        pointer.mouseClick(pills[1])
        t.equal(nonHover().length, 0, "a click within 300 ms of the history appearing is ignored")
      }], [350, function () {
        pointer.mouseClick(pillsOf(full)[1])
        t.check(reported("setProfile", {
          index: 1,
          key: "balanced"
        }) && nonHover().length === 1, "a click 300 ms after it is accepted")
        actions = []
        // Rebuilt pills (a new profile list) refuse a click while fresh.
        full.view = viewOf(cur(false, "profiles", 0), true, true, profileRows.slice().reverse())
      }], [30, function () {
        pointer.mouseClick(pillsOf(full)[0])
        t.equal(nonHover().length, 0, "a click within 300 ms of a pill being built is ignored")
      }], [350, function () {
        pointer.mouseClick(pillsOf(full)[0])
        t.check(reported("setProfile", {
          index: 0,
          key: "performance"
        }), "a settled rebuilt pill names its own key")
        full.view = withCursor(cur(false, "profiles", 0))
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
          section: "profiles",
          index: 1,
          key: "balanced"
        }), "a real move over a pill reports hover with its key")
        actions = []
        full.view = viewOf(cur(false, "profiles", 0), true, true, profileRows.slice().reverse())
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.equal(actions.filter(function (a) {
          return a[0] === "hover"
        }).length, 0, "pills rebuilt under a still pointer emit no hover")
        pointer.mouseMove(full, stillPoint.x, stillPoint.y + 2)
      }], [80, function () {
        t.check(reported("hover", {
          section: "profiles",
          index: 1,
          key: "balanced"
        }), "a real move after the rebuild reports hover again")
      }]])

  // The pill delegates before the refresh check.
  property var identityBefore: []
  // A pill's position before the history appeared.
  property real freshFrom: 0
  // The pointer position the still-pointer check replays.
  property var stillPoint: null
}
