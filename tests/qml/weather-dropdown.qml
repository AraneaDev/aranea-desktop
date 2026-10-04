// The assembled Aranea Weather dropdown, driven by a plain view object and
// its separate hourlyPoints and editText in a real window with real pointer
// clicks and keys: the hero, rain soon, the details grid (the wind arrow's
// rotation, the pressure trend), the next-24h trace and rain bars, the air
// and UV chips with their tones and the forecast days render from the view;
// each section hides on its own; the place label asks to edit and the updated
// label to refresh; the place edit takes focus, emits query on typing only,
// keys its suggestions, picks by click with its index and key, commits on
// Enter with the highlighted suggestion or the raw text (empty is automatic),
// steps the highlight on Up and Down and cancels on Esc; a stale editText
// echo never overwrites the focused field; saving pulses the place label and
// refuses to edit; opening or closing the editor stamps the layout; the trace
// paints; a click right after a layout stamp (a section showing or hiding,
// the suggestions changing) or on a row whose key changed is refused; rows
// moving under a still pointer emit no hover; outside the editor no outline
// shows without cursor.active; the suggestions, a search list, outline the
// highlighted one (Enter's target) from the start; hover draws a row's fill
// but never an outline nor moves it; and every trailing element ends on
// one right content edge.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.weather" as Weather
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by full, as [name, arg], in emission order.
  property var actions: []
  // A layout stamp taken before a change.
  property real stampBefore: 0
  // The pointer position the still-pointer checks replay.
  property var stillPoint: null

  // Synthesizes pointer and key events (TestCase's helpers), never run as
  // a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // Amsterdam suggestions, keyed by name and coordinates.
  readonly property var amsterdam: [
    {
      key: "Amsterdam|52.37|4.90",
      name: "Amsterdam",
      description: "Noord-Holland, NL"
    },
    {
      key: "Amstelveen|52.30|4.86",
      name: "Amstelveen",
      description: "Noord-Holland, NL"
    }
  ]

  // The normalised next-24h points, as WeatherLogic.hourlyPoints returns.
  readonly property var points: ({
      temp: [
        {
          x: 0,
          y: 0.75
        },
        {
          x: 0.25,
          y: 0.25
        },
        {
          x: 0.5,
          y: 0
        },
        {
          x: 0.75,
          y: 0.5
        },
        {
          x: 1,
          y: 1
        }
      ],
      rain: [
        {
          x: 0,
          h: 0
        },
        {
          x: 0.25,
          h: 0.4
        },
        {
          x: 0.5,
          h: 0.8
        },
        {
          x: 0.75,
          h: 0
        },
        {
          x: 1,
          h: 0
        }
      ],
      min: 11,
      max: 19,
      now: 17
    })

  // A view with OPTS: {rainSoon, details, hourly, aqi, uv, days, edit,
  // cursor, place, updated, loading}; missing options give the full
  // fixture.
  function viewOf(opts) {
    var o = opts || {}
    return {
      hero: {
        glyph: String.fromCodePoint(0xf0595),
        temp: "17°",
        label: "Partly cloudy",
        place: o.place !== undefined ? o.place : "Amsterdam",
        updated: o.updated !== undefined ? o.updated : "updated 20:15",
        loading: !!o.loading
      },
      rainSoon: o.rainSoon !== undefined ? o.rainSoon : "Dry for the next 3 h",
      details: o.details !== undefined ? o.details : [
        {
          key: "feels",
          label: "Feels",
          value: "16°"
        },
        {
          key: "humid",
          label: "Humid",
          value: "71%"
        },
        {
          key: "wind",
          label: "Wind",
          value: "7 km/h",
          arrow: 79,
          dir: "SW"
        },
        {
          key: "gusts",
          label: "Gusts",
          value: "19 km/h"
        },
        {
          key: "pressure",
          label: "Pressure",
          value: "1030 hPa",
          trend: "↑"
        },
        {
          key: "visibility",
          label: "Visibility",
          value: "20 km"
        }
      ],
      hourly: {
        visible: o.hourly !== undefined ? o.hourly : true,
        caption: "17° → 11° → 19°",
        labels: ["now", "03", "09", "15", "20"]
      },
      air: {
        aqi: {
          visible: o.aqi !== undefined ? o.aqi.visible : true,
          text: o.aqi !== undefined ? o.aqi.text : "AQI 53 · Fair",
          tone: o.aqi !== undefined ? o.aqi.tone : "good"
        },
        uv: {
          visible: o.uv !== undefined ? o.uv : true,
          text: "UV 0 · Low"
        }
      },
      days: o.days !== undefined ? o.days : [
        {
          key: "2026-10-02",
          label: "Today",
          glyph: String.fromCodePoint(0xf0595),
          hi: "19°",
          lo: "11°"
        },
        {
          key: "2026-10-03",
          label: "Sat",
          glyph: String.fromCodePoint(0xf0597),
          hi: "16°",
          lo: "10°"
        },
        {
          key: "2026-10-04",
          label: "Sun",
          glyph: String.fromCodePoint(0xf0599),
          hi: "18°",
          lo: "9°"
        },
        {
          key: "2026-10-05",
          label: "Mon",
          glyph: String.fromCodePoint(0xf0590),
          hi: "15°",
          lo: "8°"
        }
      ],
      edit: o.edit || {
        active: false,
        suggestions: [],
        saving: false,
        cursor: -1
      },
      cursor: o.cursor || {
        active: false,
        section: "",
        index: -1
      },
      keyHint: "enter select · e edit place · r refresh"
    }
  }

  // An editing state with SUGGESTIONS, CURSOR (the highlighted one) and
  // SAVING.
  function editing(suggestions, cursor, saving) {
    return {
      active: true,
      suggestions: suggestions,
      saving: !!saving,
      cursor: cursor
    }
  }

  // Whether an action NAME with ARG (compared as JSON) was reported.
  function reported(name, arg) {
    var want = JSON.stringify([name, arg])
    return actions.some(function (a) {
      return JSON.stringify(a) === want
    })
  }

  // Actions named NAME.
  function named(name) {
    return actions.filter(function (a) {
      return a[0] === name
    })
  }

  // Actions other than hover.
  function nonHover() {
    return actions.filter(function (a) {
      return a[0] !== "hover"
    })
  }

  // The first child of ITEM named NAME.
  function one(item, name) {
    return t.findChild(item, name)
  }

  // The visible items in ITEM named NAME.
  function shown(item, name) {
    return t.findChildren(item, name).filter(function (c) {
      return c.visible
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

  // Whether colours A and B are the same.
  function sameColor(a, b) {
    return Qt.colorEqual(a, b)
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
    implicitWidth: 440
    implicitHeight: 1400
    visible: true

    // Reads a grabbed image's pixels back: lit counts the non-transparent
    // ones once src has loaded, -1 before.
    Canvas {
      id: probe
      // The grabbed image's url.
      property string src: ""
      // How many pixels of the image are not transparent, -1 before.
      property int lit: -1
      width: 400
      height: 60
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
      x: 20
      width: 400
      spacing: 20

      Weather.WeatherDropdown {
        id: full
        width: 400
        view: viewOf({})
        hourlyPoints: points
        onAction: function (name, arg) {
          actions.push([name, arg])
        }
      }

      // Nothing but the hero: every optional section hidden.
      Weather.WeatherDropdown {
        id: bare
        width: 400
        view: viewOf({
          rainSoon: "",
          details: [],
          hourly: false,
          aqi: {
            visible: false,
            text: "",
            tone: "plain"
          },
          uv: false,
          days: []
        })
        hourlyPoints: points
      }

      // Visible hourly but no points; a bad AQI and no UV.
      Weather.WeatherDropdown {
        id: partial
        width: 400
        view: viewOf({
          aqi: {
            visible: true,
            text: "AQI 72 · Poor",
            tone: "bad"
          },
          uv: false,
          loading: true
        })
        hourlyPoints: null
      }
    }
  }

  Component.onCompleted: run([[350, function () {
        // ---------- Hero ----------
        t.equal(one(full, "heroGlyph").text, String.fromCodePoint(0xf0595), "the hero glyph")
        t.equal(one(full, "heroTemp").text, "17°", "the big temperature")
        t.equal(one(full, "heroLabel").text, "PARTLY CLOUDY", "the condition, uppercased")
        t.equal(one(full, "placeLabel").text, "AMSTERDAM " + String.fromCodePoint(0xf03eb), "the place, uppercased, with the edit glyph")
        t.equal(one(full, "updatedLabel").text, "updated 20:15", "the updated label")
        t.check(!one(full, "loadingPulse").visible, "no loading strand when loaded")
        t.check(one(partial, "loadingPulse").visible, "a loading strand while loading")

        // ---------- Rain soon ----------
        t.check(one(full, "rainSoonRow").visible, "rain soon shows")
        t.equal(one(full, "rainSoonText").text, "Dry for the next 3 h", "with its line")
        full.view = viewOf({
          rainSoon: "Rain in ~40 min"
        })
        t.equal(one(full, "rainSoonText").text, "Rain in ~40 min", "a new line reaches it")
        full.view = viewOf({})

        // ---------- Details ----------
        t.equal(t.findChildren(full, "detailLabel").map(function (l) {
          return l.text
        }), ["Feels", "Humid", "Wind", "Gusts", "Pressure", "Visibility"], "the six detail labels, in pairs")
        t.equal(t.findChildren(full, "detailValue").map(function (v) {
          return v.text
        }), ["16°", "71%", "7 km/h", "19 km/h", "1030 hPa", "20 km"], "their values")
        var arrows = shown(full, "windArrow")
        t.equal(arrows.length, 1, "one wind arrow")
        t.check(Math.abs(arrows[0].rotation - 79) < 0.01, "rotated to the view's arrow")
        t.equal(shown(full, "windDir").map(function (d) {
          return d.text
        }), ["SW"], "with its compass label")
        t.equal(shown(full, "detailTrend").map(function (d) {
          return d.text
        }), ["↑"], "the pressure trend arrow")
        var details = viewOf({}).details
        details[2].arrow = 461
        details[4].trend = "↓"
        full.view = viewOf({
          details: details
        })
        t.check(Math.abs(shown(full, "windArrow")[0].rotation - 461) < 0.01, "a rotation past 360 is just applied")
        t.equal(shown(full, "detailTrend")[0].text, "↓", "a falling trend")
        full.view = viewOf({})

        // ---------- Next 24 h ----------
        t.check(one(full, "hourlySection").visible, "the hourly section shows")
        t.equal(one(full, "hourlyCaption").text, "17° → 11° → 19°", "with its caption")
        t.equal(t.findChildren(full, "hourLabel").map(function (l) {
          return l.text
        }), ["now", "03", "09", "15", "20"], "and its hour labels")
        var trace = one(full, "hourlyTrace")
        var pts = trace.tracePoints()
        t.equal(pts.length, 5, "a trace point per temperature")
        t.check(Math.abs(pts[0].x) < 0.5 && Math.abs(pts[4].x - trace.width) < 0.5, "spanning the full width")
        t.check(pts[2].y > pts[1].y && pts[1].y > pts[0].y && pts[0].y > pts[4].y, "warmer points sit higher")
        t.check(pts[4].y >= trace.inset - 0.01 && pts[2].y <= trace.height - trace.inset + 0.01, "inside the inset plot area")
        var bars = trace.rainBars()
        t.equal(bars.length, 2, "a rain bar per slot with a chance")
        t.check(bars[1].h > bars[0].h && Math.abs(bars[1].y + bars[1].h - trace.height) < 0.5, "bars stand on the floor, taller for a higher chance")
        t.check(bars[1].h <= trace.height * 0.5 + 0.5, "and stay in the lower half, under the trace")
        var dot = trace.dotPoint()
        t.check(dot && Math.abs(dot.x - pts[0].x) < 3 && Math.abs(dot.y - pts[0].y) < 3, "the now dot sits on the first point")

        // ---------- Air & UV ----------
        t.check(one(full, "airSection").visible, "the air section shows")
        var aqi = one(full, "aqiChip")
        t.equal(aqi.text, "AQI 53 · Fair", "the AQI chip")
        t.check(sameColor(aqi.toneColor, Aranea.DesignTokens.accent), "a good AQI reads accent")
        var uv = one(full, "uvChip")
        t.check(uv.visible && uv.text === "UV 0 · Low", "the UV chip")
        t.check(!sameColor(uv.toneColor, Aranea.DesignTokens.accent) && !sameColor(uv.toneColor, Aranea.DesignTokens.urgent), "UV is plain")
        t.check(sameColor(one(partial, "aqiChip").toneColor, Aranea.DesignTokens.urgent), "a poor AQI reads urgent")
        t.check(!one(partial, "uvChip").visible, "a missing UV hides its chip alone")
        full.view = viewOf({
          aqi: {
            visible: true,
            text: "AQI 45 · Moderate",
            tone: "plain"
          }
        })
        t.check(!sameColor(one(full, "aqiChip").toneColor, Aranea.DesignTokens.accent) && !sameColor(one(full, "aqiChip").toneColor, Aranea.DesignTokens.urgent), "a moderate AQI is plain")
        full.view = viewOf({})

        // ---------- Forecast days ----------
        var days = shown(full, "dayCell")
        t.equal(days.map(function (d) {
          return d.key
        }), ["2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05"], "a cell per day, keyed by date")
        t.equal(t.findChildren(full, "dayLabel").map(function (l) {
          return l.text
        }), ["Today", "Sat", "Sun", "Mon"], "with their labels")
        t.equal(t.findChildren(full, "dayHi").map(function (l) {
          return l.text
        }), ["19°", "16°", "18°", "15°"], "highs")
        t.equal(t.findChildren(full, "dayLo").map(function (l) {
          return l.text
        }), ["11°", "10°", "9°", "8°"], "lows")
        t.equal(one(full, "dayGlyph").text, String.fromCodePoint(0xf0595), "and glyphs")
        t.check(Math.abs(days[0].width - days[3].width) < 0.5, "equal widths")
        t.equal(one(full, "keyHint").text, "enter select · e edit place · r refresh", "the key hint is the view's")

        // ---------- Sections hide individually ----------
        t.check(!one(bare, "rainSoonRow").visible, "rain soon hides when empty")
        t.check(!one(bare, "detailsSection").visible, "details hide without rows")
        t.check(!one(bare, "hourlySection").visible, "the hourly section hides when not visible")
        t.check(!one(partial, "hourlySection").visible, "and without points")
        t.check(!one(bare, "airSection").visible, "air hides with both chips gone")
        t.check(!one(bare, "daysSection").visible, "days hide without rows")
        t.equal(shown(bare, "separator").length, 0, "no separator without a section")
        t.check(one(bare, "heroTemp").visible && one(bare, "placeLabel").visible, "the hero stays")
        t.check(!one(full, "placeEdit").visible && !one(full, "suggestionsSection").visible, "no edit field or suggestions while not editing")

        // ---------- Outlines ----------
        t.equal(litOutlines(full), 0, "no outline without the cursor")
        full.view = viewOf({
          cursor: {
            active: false,
            section: "place",
            index: 0
          }
        })
        t.equal(litOutlines(full), 0, "no outline while cursor.active is false")
        full.view = viewOf({
          cursor: {
            active: true,
            section: "place",
            index: 0
          }
        })
        t.equal(litOutlines(full), 1, "one outline with it")
        t.equal(litOutlines(one(full, "placeLabel")), 1, "on the place label")
        full.view = viewOf({
          cursor: {
            active: true,
            section: "refresh",
            index: 0
          }
        })
        t.equal(litOutlines(one(full, "updatedLabel")), 1, "or on the updated label")
        full.view = viewOf({})
      }], [100, function () {
        // ---------- One right content edge (once laid out) ----------
        var edge = rightEdge(full, full)
        var values = t.findChildren(full, "detailCell")
        var trailing = [["place", one(full, "placeLabel")], ["updated", one(full, "updatedLabel")], ["rain soon", one(full, "rainSoonText")], ["second detail", values[1]], ["last detail", values[5]], ["hourly caption", one(full, "hourlyCaption")], ["trace", one(full, "hourlyTrace")], ["last hour", t.findChildren(full, "hourLabel")[4]], ["uv chip", one(full, "uvChip")], ["last day", shown(full, "dayCell")[3]]]
        for (var j = 0; j < trailing.length; j++)
          t.check(trailing[j][1] && Math.abs(rightEdge(trailing[j][1], full) - edge) < 0.5, trailing[j][0] + " ends on the content edge")
        t.check(Math.abs(rightEdge(one(bare, "placeLabel"), bare) - rightEdge(bare, bare)) < 0.5, "the bare place ends on the content edge")
        t.check(Math.abs(rightEdge(one(partial, "aqiChip"), partial) - rightEdge(partial, partial)) < 0.5, "a lone AQI chip ends on the content edge")
      }], [350, function () {
        // ---------- Pointer actions ----------
        actions = []
        pointer.mouseClick(one(full, "placeLabel"))
        t.check(reported("editPlace", {}) && nonHover().length === 1, "the place label asks to edit")
        actions = []
        pointer.mouseClick(one(full, "updatedLabel"))
        t.check(reported("refresh", {}) && nonHover().length === 1, "the updated label asks to refresh")
        actions = []
        pointer.mouseClick(one(full, "dayCell"))
        pointer.mouseClick(one(full, "aqiChip"))
        t.equal(nonHover().length, 0, "days and chips are not clickable")

        // ---------- Edit: open ----------
        full.editText = "Amsterdam"
        actions = []
        full.view = viewOf({
          edit: editing(amsterdam, 0)
        })
      }], [150, function () {
        var field = one(full, "placeField")
        t.check(one(full, "placeEdit").visible && field.visible, "editing shows the field")
        t.check(!one(full, "placeLabel").visible, "in the place label's stead")
        t.equal(field.text, "Amsterdam", "seeded with editText")
        t.check(field.activeFocus, "the field takes focus")
        t.equal(field.selectedText, "Amsterdam", "with its text selected")
        t.equal(named("query").length, 0, "seeding emits no query")
        t.check(one(full, "suggestionsSection").visible, "the suggestions show")
        var rows = shown(full, "suggestionRow")
        t.equal(rows.map(function (r) {
          return r.key
        }), ["Amsterdam|52.37|4.90", "Amstelveen|52.30|4.86"], "a row per suggestion, keyed")
        t.equal(t.findChildren(full, "suggestionName").map(function (n) {
          return n.text
        }), ["Amsterdam", "Amstelveen"], "with names")
        t.check(rows[0].highlighted && !rows[1].highlighted, "the edit cursor highlights the first")
        t.check(litOutlines(full) === 1 && litOutlines(rows[0]) === 1, "and the outline marks it from the start: Enter commits it")

        // ---------- Edit: typing ----------
        pointer.keyClick(Qt.Key_End)
        pointer.keyClick(Qt.Key_X)
        t.check(reported("query", {
          text: "Amsterdamx"
        }), "typing emits query with the text")
        full.editText = "Amsterdamx"
        t.equal(named("query").length, 1, "an echoed editText emits no second query")
        full.editText = "Amst"
        t.equal(one(full, "placeField").text, "Amsterdamx", "a stale echo never overwrites the focused field")
        pointer.keyClick(Qt.Key_Backspace)
        t.check(reported("query", {
          text: "Amsterdam"
        }), "a backspace emits query too")

        // ---------- Edit: Up and Down step the highlight ----------
        actions = []
        var cursorAt = one(full, "placeField").cursorPosition
        pointer.keyClick(Qt.Key_Up)
        pointer.keyClick(Qt.Key_Down)
        t.equal(nonHover(), [["step",
            {
              delta: -1
            }
          ], ["step",
            {
              delta: 1
            }
          ]], "Up and Down report a step each, Up first")
        t.equal(one(full, "placeField").cursorPosition, cursorAt, "and never move the text cursor")

        // ---------- Edit: Enter and Esc ----------
        actions = []
        pointer.keyClick(Qt.Key_Return)
        t.check(reported("commit", {
          text: "Amsterdam",
          pick: {
            index: 0,
            key: "Amsterdam|52.37|4.90"
          }
        }) && nonHover().length === 1, "Enter commits the highlighted suggestion")
        full.view = viewOf({
          edit: editing(amsterdam, -1)
        })
        actions = []
        pointer.keyClick(Qt.Key_Enter)
        t.check(reported("commit", {
          text: "Amsterdam",
          pick: null
        }), "with no highlight Enter commits the raw text")
        one(full, "placeField").selectAll()
        pointer.keyClick(Qt.Key_Backspace)
        t.check(reported("query", {
          text: ""
        }), "emptying the field queries empty")
        full.view = viewOf({
          edit: editing(amsterdam, 0)
        })
        actions = []
        pointer.keyClick(Qt.Key_Return)
        t.check(reported("commit", {
          text: "",
          pick: null
        }), "an empty commit carries no pick (back to automatic)")
        actions = []
        pointer.keyClick(Qt.Key_Escape)
        t.check(reported("cancel", {}) && nonHover().length === 1, "Esc cancels")

        // ---------- Edit: suggestions change stamps ----------
        stampBefore = full.layoutChangedAt
        full.view = viewOf({
          edit: editing(amsterdam.slice().reverse(), 0)
        })
        t.check(full.layoutChangedAt > stampBefore, "the suggestions changing stamps the layout")
        stampBefore = full.layoutChangedAt
        full.view = viewOf({
          edit: editing(amsterdam.slice().reverse(), 1)
        })
        t.equal(full.layoutChangedAt, stampBefore, "an equal list with a new highlight does not")
        t.check(shown(full, "suggestionRow")[1].highlighted, "but moves the highlight")
        actions = []
        pointer.mouseClick(shown(full, "suggestionRow")[1])
        pointer.mouseClick(one(full, "clearPlace"))
        t.equal(nonHover().length, 0, "clicks right after the stamp are refused")
      }], [350, function () {
        actions = []
        pointer.mouseClick(shown(full, "suggestionRow")[1])
        t.check(reported("pick", {
          index: 1,
          key: "Amsterdam|52.37|4.90"
        }), "a settled click picks with its index and key")
        actions = []
        full.pickAt(1, "Utrecht|52.09|5.12")
        t.equal(nonHover().length, 0, "a pick whose key no longer matches its row is refused")
        actions = []
        pointer.mouseClick(one(full, "clearPlace"))
        t.check(reported("clearPlace", {}), "the clear button asks to clear the place")

        // ---------- Key mismatch under a held press ----------
        actions = []
        var row = shown(full, "suggestionRow")[0]
        pointer.mousePress(row)
        full.view = viewOf({
          edit: editing([
            {
              key: "Utrecht|52.09|5.12",
              name: "Utrecht",
              description: "Utrecht, NL"
            },
            amsterdam[1]], 0)
        })
      }], [350, function () {
        pointer.mouseRelease(shown(full, "suggestionRow")[0])
        t.equal(named("pick").length, 0, "a press on one key released on another is refused")

        // ---------- Still pointer ----------
        full.view = viewOf({
          edit: editing(amsterdam, 0)
        })
        full.disarmPointer()
        var r1 = shown(full, "suggestionRow")[1]
        stillPoint = r1.mapToItem(full, r1.width / 2, r1.height / 2)
        actions = []
        pointer.mouseMove(full, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          section: "suggestions",
          index: 1,
          key: "Amstelveen|52.30|4.86"
        }), "a real move over a suggestion reports hover with its key")
        t.check(t.findChild(shown(full, "suggestionRow")[1], "hoverFill").visible && !t.findChild(shown(full, "suggestionRow")[0], "hoverFill").visible, "and draws its hover fill")
        t.check(litOutlines(full) === 1 && litOutlines(shown(full, "suggestionRow")[0]) === 1, "hover never moves the outline off the highlighted suggestion")
        actions = []
        full.view = viewOf({
          edit: editing(amsterdam.slice().reverse(), 0)
        })
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.equal(named("hover").length, 0, "rows changing under a still pointer emit no hover")
        pointer.mouseMove(full, stillPoint.x, stillPoint.y + 2)
      }], [80, function () {
        t.check(reported("hover", {
          section: "suggestions",
          index: 1,
          key: "Amsterdam|52.37|4.90"
        }), "a real move afterwards reports hover again")

        // ---------- The keyboard cursor on a suggestion ----------
        full.view = viewOf({
          edit: editing(amsterdam, 1),
          cursor: {
            active: true,
            section: "suggestions",
            index: 1
          }
        })
        t.equal(litOutlines(full), 1, "one outline with cursor.active")
        t.equal(litOutlines(shown(full, "suggestionRow")[1]), 1, "on the highlighted suggestion")

        // ---------- Saving pulses ----------
        full.view = viewOf({
          place: "Utrecht",
          edit: {
            active: false,
            suggestions: [],
            saving: true,
            cursor: -1
          }
        })
        var place = one(full, "placeLabel")
        t.check(place.visible && place.text === "UTRECHT " + String.fromCodePoint(0xf03eb), "the new place shows at once")
        t.check(place.busy, "and pulses while saving")
        t.equal(one(place, "busyPulse").running, Aranea.DesignTokens.motionEnabled, "the pulse runs with motion")
        t.check(!one(full, "placeEdit").visible && !one(full, "suggestionsSection").visible, "the editor is gone")
        full.view = viewOf({})
        t.check(!one(full, "placeLabel").busy, "it stops when saved")

        // ---------- Layout stamps and ClickSettle ----------
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf({
          aqi: {
            visible: false,
            text: "",
            tone: "plain"
          },
          uv: false
        })
        t.check(full.layoutChangedAt > stampBefore, "the air section hiding stamps the layout")
        actions = []
        pointer.mouseClick(one(full, "placeLabel"))
        pointer.mouseClick(one(full, "updatedLabel"))
        t.equal(nonHover().length, 0, "clicks right after the stamp are refused")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf({})
        t.check(full.layoutChangedAt > stampBefore, "the air section showing stamps the layout")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.hourlyPoints = null
        t.check(full.layoutChangedAt > stampBefore, "the hourly section hiding stamps the layout")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf({
          rainSoon: ""
        })
        t.check(full.layoutChangedAt > stampBefore, "rain soon hiding stamps the layout")
        full.hourlyPoints = points
        full.view = viewOf({})
      }], [20, function () {
        full.view = viewOf({
          updated: ""
        })
      }], [350, function () {
        stampBefore = full.layoutChangedAt
        full.view = viewOf({})
        t.check(full.layoutChangedAt > stampBefore, "the updated label appearing stamps the layout")
        actions = []
        pointer.mouseClick(one(full, "placeLabel"))
        t.equal(nonHover().length, 0, "a place click right after it moved is refused")
      }], [350, function () {
        actions = []
        pointer.mouseClick(one(full, "placeLabel"))
        t.check(reported("editPlace", {}), "a click 300 ms later is accepted")

        // ---------- Opening and closing the editor ----------
        stampBefore = full.layoutChangedAt
        actions = []
        full.view = viewOf({
          edit: editing([], -1)
        })
        t.check(!one(full, "suggestionsSection").visible, "opened with no suggestions yet")
        t.check(full.layoutChangedAt > stampBefore, "opening the editor stamps the layout")
      }], [40, function () {
        // Once laid out, still well inside the settle window.
        pointer.mouseClick(one(full, "clearPlace"))
        t.equal(nonHover().length, 0, "a click on the clear button right after opening is refused")
      }], [350, function () {
        pointer.mouseClick(one(full, "clearPlace"))
        t.check(reported("clearPlace", {}), "and accepted 300 ms later")
        stampBefore = full.layoutChangedAt
        actions = []
        full.view = viewOf({})
        t.check(full.layoutChangedAt > stampBefore, "closing the editor stamps the layout")
      }], [40, function () {
        pointer.mouseClick(one(full, "placeLabel"))
        t.equal(nonHover().length, 0, "a click on the place right after closing is refused")
        full.editText = "Utrecht"
        t.equal(one(full, "placeField").text, "Utrecht", "a closed field takes a new editText")
        full.view = viewOf({
          place: "Utrecht",
          edit: {
            active: false,
            suggestions: [],
            saving: true,
            cursor: -1
          }
        })
      }], [350, function () {
        actions = []
        pointer.mouseClick(one(full, "placeLabel"))
        t.equal(nonHover().length, 0, "the place label does not ask to edit while saving")
        full.view = viewOf({})

        // ---------- The trace paints ----------
        var file = Qt.resolvedUrl("trace-grab.png")
        one(full, "hourlyTrace").grabToImage(function (result) {
          result.saveToFile(decodeURIComponent(String(file).replace(/^file:\/\//, "")))
          probe.src = String(file)
          probe.loadImage(probe.src)
        })
      }], [600, function () {
        t.check(probe.lit > 50, "the trace grab has drawn pixels (" + probe.lit + ")")
      }]])
}
