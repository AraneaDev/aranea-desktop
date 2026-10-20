// The pure world clock view exercised with real input and plain fixtures.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.worldclock" as World
import "plugins/araneadev.shared" as Aranea
import "plugins/araneadev.worldclock/WorldCities.js" as Cities

ShellRoot {
  id: testRoot
  // Actions emitted by the pure dropdown in input order.
  property var actions: []
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    name: "input"
    when: false
  }
  // Builds the seed presentation state, including coordinate-free UTC.
  function fixture(adding) {
    return {
      homeName: "Amsterdam",
      homeTime: "12:13",
      utcTime: "10:13",
      sunCaption: "overhead 10°S 22°E",
      sun: {
        lat: -10.6,
        lon: 22
      },
      rows: Cities.SEED.map(function (c, i) {
        return {
          name: c.name,
          abbrev: ["CEST", "BST", "UTC", "EDT", "PDT"][i],
          time: "12:13",
          offset: i === 0 ? "home" : "−1 h",
          node: ["day", "dusk", "none", "night", "night"][i],
          stops: [
            {
              at: 0,
              tone: "night"
            },
            {
              at: 1,
              tone: "day"
            }
          ],
          now: 0.5,
          home: !!c.home,
          selected: i === 1,
          place: i === 2 ? null : c
        }
      }),
      adding: adding,
      query: "",
      matches: [
        {
          name: "Tokyo",
          country: "Japan",
          abbrev: "JST",
          offset: "+7 h",
          time: "19:13",
          selected: true
        }
      ],
      selectedPlace: null
    }
  }
  FloatingWindow {
    id: win
    visible: true
    width: 500
    height: 900
    World.WorldClockDropdown {
      id: dropdown
      x: 20
      y: 20
      width: 380
      view: testRoot.fixture(false)
      onAction: function (name, arg) {
        testRoot.actions.push([name, arg])
      }
    }
  }
  // Checks the last action emitted through the view contract.
  function last(name, arg) {
    t.equal(actions[actions.length - 1], [name, arg], name + " action")
  }
  Component.onCompleted: t.step(250, function () {
    var rows = t.findChildren(dropdown, "zoneRow")
    t.equal(rows.map(function (r) {
      return r.row.name
    }), Cities.SEED.map(function (c) {
      return c.name
    }), "seed rows keep order")
    t.equal(String(t.findChild(rows[0], "zoneName").color), String(Aranea.DesignTokens.accent), "home name is accent")
    t.check(t.findChild(rows[1], "selectionBar").visible, "selection has left bar")
    t.equal(rows.map(function (r) {
      return t.findChild(r, "zoneNode").text
    }), ["◆", "◆", "◇", "◇", "◇"], "node glyphs map day/dusk/night/none")
    t.equal(String(t.findChild(rows[1], "zoneNode").color), String(Aranea.DesignTokens.ceremonyGold), "dusk is ceremony")
    var globe = t.findChild(dropdown, "worldGlobe")
    t.equal(globe.markers.length, 4, "coordinate-free UTC has no marker")
    t.equal(t.findChild(dropdown, "keyHint").text, "↑↓ move · a add · x remove · [ ] reorder · h set home", "normal hint copy")
    var right = t.findChild(dropdown, "headerTrailing").mapToItem(dropdown, t.findChild(dropdown, "headerTrailing").width, 0).x
    rows.forEach(function (r) {
      var time = t.findChild(r, "zoneTime")
      t.check(Math.abs(time.mapToItem(dropdown, time.width, 0).x - right) < 0.5, "row time shares right edge")
    })
    input.mouseMove(rows[3], rows[3].width / 2, rows[3].height / 2)
    last("select", 3)
    var add = t.findChild(dropdown, "addCity")
    input.mouseClick(add, add.width / 2, add.height / 2)
    last("addStart", null)
    dropdown.view = testRoot.fixture(true)
    t.step(100, function () {
      var field = t.findChild(dropdown, "cityQuery")
      t.check(field.activeFocus, "search takes focus")
      input.keyClick(Qt.Key_T)
      last("queryChanged", "t")
      var match = t.findChild(dropdown, "cityMatch")
      t.check(match !== null, "search match renders")
      input.mouseMove(match, match.width / 2, match.height / 2)
      last("matchSelect", 0)
      t.equal(t.findChild(match, "matchOffset").text, "+7 h", "match offset renders")
      t.equal(t.findChild(match, "matchTime").text, "19:13", "match time renders")
      input.keyClick(Qt.Key_Return)
      last("add", 0)
      input.keyClick(Qt.Key_Escape)
      last("cancelAdd", null)
      t.equal(t.findChild(dropdown, "keyHint").text, "↑↓ choose · enter add · esc cancel", "adding hint copy")
      t.done()
    })
  })
}
