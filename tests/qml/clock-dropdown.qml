// The assembled Aranea Clock dropdown, driven by a plain view object and
// its separate todayKey, bornText and liveToText in a real window with real
// pointer clicks and keys: the month grid renders stock Model.js's week
// rows, ISO week numbers and weekday order for both week starts (and across
// the ISO week 53 / week 1 turn of 2026 into 2027); today is the one mint
// diamond; the day cells are keyed by date, so a todayKey change or an
// equal view rebuilt keeps them; the chevrons, the W heading, the week
// start label, Back to today and the wheel emit their actions; Back to
// today shows only off the current month; double-clicks ask to edit or
// clear the life bar; the life fields take focus, Tab between them, commit
// on Enter and cancel on Esc; the sun and moon section hides without data,
// keeps the moon without the sun, reads "Night" after sunset and names a
// polar day or night; Back to today appearing or going stamps; a click
// within 300 ms of a layout stamp is ignored; nothing draws an outline; and
// every trailing element ends on one right content edge.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.clock" as Clock
import "plugins/araneadev.clock/Model.js" as Model

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by full, as [name, arg], in emission order.
  property var actions: []
  // Cells captured before an identity check.
  property var cellsBefore: []
  // A layout stamp taken before a week-count change.
  property real stampBefore: 0

  // Synthesizes pointer and key events (TestCase's helpers), never run as
  // a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // Stock's weeks for YEAR/MONTH (zero-based) with week start WS (0 Sunday,
  // 1 Monday), as the view carries them; TRIM drops trailing weeks with no
  // day in the month (a 5-week month).
  function weeksOf(year, month, ws, trim) {
    var weeks = Model.monthGrid(year, month, ws, "").map(function (w) {
      return {
        week: w.week,
        days: w.days.map(function (d) {
          return {
            key: d.key,
            day: d.day,
            inMonth: d.inMonth
          }
        })
      }
    })
    if (trim)
      weeks = weeks.filter(function (w) {
        return w.days.some(function (d) {
          return d.inMonth
        })
      })
    return weeks
  }

  // Weekday headings for week start WS.
  function weekdaysOf(ws) {
    var names = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    return Model.weekdayOrder(ws).map(function (i) {
      return names[i]
    })
  }

  // A view with OPTS: {year, month, ws, trim, current, sky, sun, life,
  // editing}; missing options give October 2026, Monday start, full sky.
  function viewOf(opts) {
    var o = opts || {}
    var year = o.year !== undefined ? o.year : 2026
    var month = o.month !== undefined ? o.month : 9
    var ws = o.ws !== undefined ? o.ws : 1
    var sun = o.sun !== undefined ? o.sun : {
      visible: true,
      sunrise: "07:43",
      sunset: "19:15",
      daylight: "11 h 32",
      arcT: 0.7,
      night: false,
      polar: ""
    }
    return {
      title: "Friday 2 October",
      subtitle: "16:58 · Week 40",
      monthLabel: o.monthLabel || "October 2026",
      viewingCurrentMonth: o.current !== undefined ? o.current : true,
      weekdays: weekdaysOf(ws),
      weeks: weeksOf(year, month, ws, o.trim !== undefined ? o.trim : true),
      weekStartLabel: ws === 1 ? "Start weeks on Sunday" : "Start weeks on Monday",
      year: {
        percent: 75
      },
      life: {
        visible: o.life !== undefined ? o.life : true,
        percent: 49,
        born: 1977,
        liveTo: 85,
        editing: !!o.editing
      },
      sky: {
        visible: o.sky !== undefined ? o.sky : true,
        place: "Amsterdam",
        sun: sun,
        moon: {
          glyph: String.fromCodePoint(0xf0f66),
          name: "Waning gibbous",
          illumination: 68
        }
      },
      keyHint: "←→ month · ↑↓ year · t today"
    }
  }

  // Whether an action NAME with ARG (compared as JSON) was reported.
  function reported(name, arg) {
    var want = JSON.stringify([name, arg])
    return actions.some(function (a) {
      return JSON.stringify(a) === want
    })
  }

  // The first child of ITEM named NAME.
  function one(item, name) {
    return t.findChild(item, name)
  }

  // The day cells in DROPDOWN, in grid order.
  function cellsOf(dropdown) {
    return t.findChildren(dropdown, "dayCell")
  }

  // The rendered week numbers in DROPDOWN, as numbers.
  function weekNumbersOf(dropdown) {
    return t.findChildren(dropdown, "weekNumber").map(function (w) {
      return Number(w.text)
    })
  }

  // The flat date keys of WEEKS.
  function keysOf(weeks) {
    var keys = []
    weeks.forEach(function (w) {
      w.days.forEach(function (d) {
        keys.push(d.key)
      })
    })
    return keys
  }

  // Right edge of ITEM in HOST's coordinates.
  function rightEdge(item, host) {
    return item.mapToItem(host, item.width, 0).x
  }

  // The visible items in ITEM named NAME.
  function shown(item, name) {
    return t.findChildren(item, name).filter(function (c) {
      return c.visible
    })
  }

  // Double-clicks ITEM at its centre (two presses in quick succession).
  function doubleClick(item) {
    pointer.mouseDoubleClickSequence(item, item.width / 2, item.height / 2)
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
    implicitHeight: 1300
    visible: true

    Column {
      x: 20
      width: 380
      spacing: 20

      Clock.ClockDropdown {
        id: full
        width: 380
        view: viewOf({})
        todayKey: "2026-10-02"
        bornText: "1977"
        liveToText: "85"
        onAction: function (name, arg) {
          actions.push([name, arg])
        }
      }

      // No sun (no location yet): the moon alone.
      Clock.ClockDropdown {
        id: moonOnly
        width: 380
        view: viewOf({
          sun: {
            visible: false
          },
          life: false
        })
        todayKey: "2026-10-02"
      }

      // A polar day.
      Clock.ClockDropdown {
        id: polar
        width: 380
        view: viewOf({
          sun: {
            visible: true,
            sunrise: "",
            sunset: "",
            daylight: "24 h 00",
            arcT: 0,
            night: true,
            polar: "day"
          },
          life: false
        })
        todayKey: "2026-10-02"
      }
    }
  }

  Component.onCompleted: run([[350, function () {
        // ---------- Header ----------
        t.equal(one(full, "headerCaption").text, "16:58 · Week 40", "the header caption preserves subtitle casing")
        t.equal(one(full, "monthLabel").text, "October 2026", "the trailing month label is the view's")
        t.check(one(full, "prevMonth").visible && one(full, "nextMonth").visible, "both chevrons show")

        // ---------- The grid, Monday start ----------
        var oct = weeksOf(2026, 9, 1, true)
        t.equal(t.findChildren(full, "weekdayHeading").map(function (h) {
          return h.text
        }), ["MO", "TU", "WE", "TH", "FR", "SA", "SU"], "Monday-start weekday headings")
        t.equal(weekNumbersOf(full), oct.map(function (w) {
          return w.week
        }), "the week numbers are stock Model.js's")
        t.equal(weekNumbersOf(full), [40, 41, 42, 43, 44], "October 2026 runs ISO weeks 40 to 44")
        t.equal(cellsOf(full).map(function (c) {
          return c.key
        }), keysOf(oct), "a cell per stock day, keyed by date")
        t.equal(cellsOf(full)[0].key, "2026-09-28", "the first Monday-start cell is 28 September")
        t.check(!cellsOf(full)[0].inMonth && cellsOf(full)[3].inMonth, "out-of-month days read out of month")
        t.check(one(cellsOf(full)[0], "dayText").opacity < one(cellsOf(full)[3], "dayText").opacity, "and are dim")
        t.equal(one(full, "weekHeading").text, "W", "the W heading")
        t.equal(one(full, "weekStartLabel").text, "W: start weeks on Sunday", "the week start label names the next start")

        // ---------- Today's marker ----------
        var marks = shown(full, "todayMarker")
        t.equal(marks.length, 1, "exactly one today marker")
        var todayCell = cellsOf(full).filter(function (c) {
          return c.isToday
        })
        t.check(todayCell.length === 1 && todayCell[0].key === "2026-10-02", "on today's cell")
        t.check(one(todayCell[0], "todayMarker").visible && Math.abs(one(todayCell[0], "todayMarker").rotation - 45) < 0.01, "a diamond")

        // ---------- Cell identity across a todayKey change ----------
        cellsBefore = cellsOf(full)
        full.todayKey = "2026-10-03"
        full.view = viewOf({})
        var after = cellsOf(full)
        t.check(after.length === cellsBefore.length && after.every(function (c, k) {
          return c === cellsBefore[k]
        }), "a todayKey change (and an equal view rebuilt) keeps every day cell")
        t.check(after[5].isToday && !after[4].isToday, "and the diamond moves to the new day")
        t.equal(shown(full, "todayMarker").length, 1, "still exactly one marker")
        full.todayKey = "2026-10-02"

        // ---------- Sunday start ----------
        full.view = viewOf({
          ws: 0
        })
        var octSun = weeksOf(2026, 9, 0, true)
        t.equal(t.findChildren(full, "weekdayHeading").map(function (h) {
          return h.text
        }), ["SU", "MO", "TU", "WE", "TH", "FR", "SA"], "Sunday-start weekday headings")
        t.equal(cellsOf(full).map(function (c) {
          return c.key
        }), keysOf(octSun), "Sunday-start cells are stock's")
        t.equal(cellsOf(full)[0].key, "2026-09-27", "the first Sunday-start cell is 27 September")
        t.equal(weekNumbersOf(full), octSun.map(function (w) {
          return w.week
        }), "Sunday-start week numbers are stock's (the row's Thursday)")
        t.equal(weekNumbersOf(full)[0], 40, "the first Sunday-start row is still week 40")
        t.equal(one(full, "weekStartLabel").text, "W: start weeks on Monday", "the label follows the view at once")

        // ---------- ISO week 53 and week 1 ----------
        full.view = viewOf({
          year: 2026,
          month: 11,
          current: false,
          monthLabel: "December 2026"
        })
        var dec = weeksOf(2026, 11, 1, true)
        t.equal(weekNumbersOf(full), dec.map(function (w) {
          return w.week
        }), "December 2026 week numbers are stock's")
        t.equal(weekNumbersOf(full)[weekNumbersOf(full).length - 1], 53, "December 2026 ends in ISO week 53")
        full.view = viewOf({
          year: 2027,
          month: 0,
          current: false,
          monthLabel: "January 2027"
        })
        var jan = weeksOf(2027, 0, 1, true)
        t.equal(weekNumbersOf(full), jan.map(function (w) {
          return w.week
        }), "January 2027 week numbers are stock's")
        t.equal(weekNumbersOf(full).slice(0, 2), [53, 1], "January 2027 opens in week 53, then week 1")
        t.equal(cellsOf(full).map(function (c) {
          return c.key
        }), keysOf(jan), "January 2027 cells are stock's")
        full.view = viewOf({
          year: 2027,
          month: 0,
          ws: 0,
          current: false,
          monthLabel: "January 2027"
        })
        t.equal(weekNumbersOf(full), weeksOf(2027, 0, 0, true).map(function (w) {
          return w.week
        }), "January 2027 Sunday-start week numbers are stock's")
        t.equal(shown(full, "todayMarker").length, 0, "no marker off today's month")

        // ---------- Back to today ----------
        t.check(one(full, "backToToday").visible, "Back to today shows off the current month")
        full.view = viewOf({})
        t.check(!one(full, "backToToday").visible, "and hides on it")

        // ---------- Sun and moon ----------
        t.check(one(full, "skySection").visible, "the sun and moon section shows with data")
        t.equal(one(full, "skyPlace").text, "Amsterdam", "with its place")
        t.equal(one(full, "sunriseValue").text, "07:43", "sunrise")
        t.equal(one(full, "sunsetValue").text, "19:15", "sunset")
        t.equal(one(full, "daylightValue").text, "11 h 32", "daylight")
        t.equal(one(full, "moonValue").text, String.fromCodePoint(0xf0f66) + " Waning gibbous · 68%", "the moon")
        var arc = one(full, "sunArc")
        t.check(arc.visible && arc.lit, "the arc shows lit by day")
        var dot = arc.dotPoint()
        t.check(dot && !dot.dim && dot.x > arc.width / 2 && dot.y < arc.height - 4, "the dot sits past noon, up on the arc")
        t.check(!one(full, "polarCaption").visible, "no polar caption")
        t.check(!one(full, "nightCaption").visible, "no Night caption by day")
        full.view = viewOf({
          sun: {
            visible: true,
            sunrise: "07:43",
            sunset: "19:15",
            daylight: "11 h 32",
            arcT: 0.25,
            night: true,
            polar: ""
          }
        })
        t.check(!one(full, "sunArc").lit && one(full, "sunArc").dotPoint().dim, "at night the arc and the dot are dim")
        t.check(one(full, "nightCaption").visible && one(full, "nightCaption").text === "Night", "and the caption reads Night")
        full.view = viewOf({})

        t.check(one(moonOnly, "skySection").visible, "the moon shows without sun data")
        t.check(!one(moonOnly, "sunArc").visible && !one(moonOnly, "sunriseValue").visible && !one(moonOnly, "daylightValue").visible, "without the arc or sun times")
        t.check(one(moonOnly, "moonValue").visible, "the moon value shows")
        t.check(Math.abs(rightEdge(one(moonOnly, "moonValue"), moonOnly) - rightEdge(moonOnly, moonOnly)) < 0.5, "the moon alone ends on the content edge")
        moonOnly.view = viewOf({
          sky: false,
          life: false
        })
        t.check(!one(moonOnly, "skySection").visible, "the section hides without data")

        t.check(one(polar, "sunArc").visible && one(polar, "sunArc").lit && one(polar, "sunArc").dotPoint() === null, "a polar day lights the whole arc, no dot")
        t.equal(one(polar, "polarCaption").text, "Sun up all day", "and says so")
        t.check(!one(polar, "sunriseValue").visible && !one(polar, "sunsetValue").visible, "without sunrise or sunset")
        polar.view = viewOf({
          sun: {
            visible: true,
            sunrise: "",
            sunset: "",
            daylight: "",
            arcT: 0,
            night: true,
            polar: "night"
          },
          life: false
        })
        t.check(!one(polar, "sunArc").lit && one(polar, "sunArc").dotPoint() === null, "a polar night dims the arc, no dot")
        t.equal(one(polar, "polarCaption").text, "Sun down all day", "and says so")
        t.check(!one(polar, "nightCaption").visible, "a polar night has no separate Night caption")

        // ---------- Year and life ----------
        t.equal(one(full, "yearPercent").text, "75%", "the year percent")
        t.check(Math.abs(one(full, "yearStrand").fraction - 0.75) < 0.001, "the year strand is lit to it")
        t.check(one(full, "lifeRow").visible, "the life bar shows when set")
        t.equal(one(full, "lifePercent").text, "49%", "the life percent")
        t.check(!one(polar, "lifeRow").visible, "and hides when not")
        t.check(!one(full, "lifeEdit").visible, "no edit row while not editing")
        t.equal(one(full, "keyHint").text, "←→ month · ↑↓ year · t today", "the key hint is the view's")

        // ---------- No stray outline ----------
        t.equal(t.findChildren(full, "cursorOutline").length, 0, "no cursor outline anywhere")
        t.check(cellsOf(full).every(function (c) {
          return c.border === undefined
        }), "day cells draw no border")
      }], [100, function () {
        // ---------- One right content edge (once laid out) ----------
        var edge = rightEdge(full, full)
        var trailing = [["next chevron", one(full, "nextMonth")], ["last weekday", t.findChildren(full, "weekdayHeading")[6]], ["last day", cellsOf(full)[6]], ["place", one(full, "skyPlace")], ["sunset", one(full, "sunsetValue")], ["moon", one(full, "moonValue")], ["year percent", one(full, "yearPercent")], ["year strand", one(full, "yearStrand")], ["life percent", one(full, "lifePercent")], ["life strand", one(full, "lifeStrand")], ["week start label", one(full, "weekStartLabel")]]
        for (var j = 0; j < trailing.length; j++)
          t.check(trailing[j][1] && Math.abs(rightEdge(trailing[j][1], full) - edge) < 0.5, trailing[j][0] + " ends on the content edge")
        full.view = viewOf({
          current: false
        })
      }], [350, function () {
        // ---------- Actions ----------
        actions = []
        pointer.mouseClick(one(full, "prevMonth"))
        pointer.mouseClick(one(full, "nextMonth"))
        t.check(reported("prevMonth", {}) && reported("nextMonth", {}), "the chevrons emit prevMonth and nextMonth")
        actions = []
        pointer.mouseClick(one(full, "weekHeading"))
        t.check(reported("toggleWeekStart", {}) && actions.length === 1, "the W heading emits toggleWeekStart")
        actions = []
        pointer.mouseClick(one(full, "weekStartLabel"))
        t.check(reported("toggleWeekStart", {}) && actions.length === 1, "so does the week start label")
        actions = []
        pointer.mouseClick(one(full, "backToToday"))
        t.check(reported("today", {}) && actions.length === 1, "Back to today emits today")
        actions = []
        var grid = one(full, "clockGrid")
        pointer.mouseWheel(grid, grid.width / 2, grid.height / 2, 0, -120)
        t.check(reported("wheel", {
          dy: -120
        }), "the wheel over the grid emits wheel with its dy")
        actions = []
        pointer.mouseWheel(grid, grid.width / 2, grid.height / 2, 120, 0)
        t.equal(actions.length, 0, "a horizontal wheel emits nothing")
        actions = []
        doubleClick(one(full, "yearRow"))
        t.check(reported("editLife", {
          clear: false
        }), "a double-click on the year bar asks to edit the life bar")
        actions = []
        doubleClick(one(full, "lifeRow"))
        t.check(reported("editLife", {
          clear: true
        }), "a double-click on the life bar asks to clear it")
        actions = []
        pointer.mouseClick(one(full, "yearRow"))
        t.equal(actions.length, 0, "a single click on the year bar does nothing")
      }], [450, function () {
        // ---------- Life editing ----------
        actions = []
        full.view = viewOf({
          current: false,
          editing: true
        })
      }], [150, function () {
        var born = one(full, "bornField")
        var liveTo = one(full, "liveToField")
        t.check(one(full, "lifeEdit").visible, "editing shows the edit row")
        t.equal(born.text, "1977", "the born field holds bornText")
        t.equal(liveTo.text, "85", "the live-to field holds liveToText")
        t.check(born.activeFocus, "the born field takes focus")
        t.equal(born.selectedText, "1977", "with its text selected")
        pointer.keyClick(Qt.Key_Tab)
        t.check(liveTo.activeFocus && liveTo.selectedText === "85", "Tab hops to the live-to field, selected")
        pointer.keyClick(Qt.Key_Backtab)
        t.check(born.activeFocus, "Backtab hops back")
        pointer.keyClick(Qt.Key_Tab)
        pointer.keyClick(Qt.Key_9)
        pointer.keyClick(Qt.Key_0)
        t.equal(liveTo.text, "90", "typing replaces the selection")
        actions = []
        doubleClick(one(full, "yearRow"))
        t.equal(actions.length, 0, "the year bar ignores a double-click while editing")
        liveTo.forceActiveFocus()
        actions = []
        pointer.keyClick(Qt.Key_Return)
        t.check(reported("lifeCommit", {
          born: "1977",
          liveTo: "90"
        }) && actions.length === 1, "Enter commits both fields")
        born.forceActiveFocus()
        actions = []
        pointer.keyClick(Qt.Key_Escape)
        t.check(reported("lifeCancel", {}) && actions.length === 1, "Esc cancels")
        full.bornText = "1980"
        t.equal(born.text, "1980", "a new bornText reaches the field")
        full.view = viewOf({
          current: false
        })
        t.check(!one(full, "lifeEdit").visible, "the edit row hides when editing ends")

        // ---------- Layout stamps and ClickSettle ----------
        stampBefore = full.layoutChangedAt
        full.view = viewOf({
          year: 2026,
          month: 7,
          current: false,
          monthLabel: "August 2026"
        })
        t.check(weekNumbersOf(full).length === 6, "August 2026 needs six weeks")
        t.check(full.layoutChangedAt > stampBefore, "a week-count change stamps the layout")
        actions = []
        pointer.mouseClick(one(full, "nextMonth"))
        pointer.mouseClick(one(full, "backToToday"))
        pointer.mouseClick(one(full, "weekHeading"))
        pointer.mouseClick(one(full, "weekStartLabel"))
        t.equal(actions.length, 0, "clicks right after a layout stamp are ignored")
      }], [350, function () {
        pointer.mouseClick(one(full, "nextMonth"))
        t.check(reported("nextMonth", {}), "a click 300 ms later is accepted")
        stampBefore = full.layoutChangedAt
        full.view = viewOf({
          year: 2026,
          month: 7,
          current: false,
          monthLabel: "August 2026",
          life: false
        })
        t.check(full.layoutChangedAt > stampBefore, "the life bar hiding stamps the layout")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf({
          year: 2026,
          month: 7,
          current: false,
          monthLabel: "August 2026",
          life: false,
          sky: false
        })
        t.check(full.layoutChangedAt > stampBefore, "the sky section hiding stamps the layout")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf({
          year: 2026,
          month: 7,
          current: false,
          monthLabel: "August 2026",
          life: false
        })
        t.check(full.layoutChangedAt > stampBefore, "the sky section appearing stamps the layout")
        actions = []
        pointer.mouseClick(one(full, "backToToday"))
        t.equal(actions.length, 0, "and a click right after it is ignored")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf({
          year: 2026,
          month: 7,
          current: true,
          monthLabel: "August 2026",
          life: false
        })
        t.check(!one(full, "backToToday").visible, "Back to today goes on the current month")
        t.check(full.layoutChangedAt > stampBefore, "and Back to today going stamps the layout")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf({
          year: 2026,
          month: 7,
          current: false,
          monthLabel: "August 2026",
          life: false
        })
        t.check(full.layoutChangedAt > stampBefore, "and Back to today coming back stamps it too")
      }], [350, function () {
        // ---------- Hover fill on a double-clickable strand ----------
        var year = one(full, "yearRow")
        t.check(!one(year, "hoverFill").visible, "the year strand is unlit before the pointer moves")
        pointer.mouseMove(year, year.width / 2, year.height / 2)
      }], [60, function () {
        var year = one(full, "yearRow")
        pointer.mouseMove(year, year.width / 2 + 4, year.height / 2)
      }], [60, function () {
        t.check(one(one(full, "yearRow"), "hoverFill").visible, "a real move onto the year strand draws its hover fill")
      }]])
}
