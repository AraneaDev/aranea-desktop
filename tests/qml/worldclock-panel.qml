// Real panel and keyboard frame; only native layer-shell and zone probe are injected.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.worldclock" as World
import "plugins/araneadev.worldclock/WorldCities.js" as Cities

ShellRoot {
  id: testRoot
  // Inline host writes recorded for persistence assertions.
  property var writes: []
  // Fixed real timezone observations isolate the operating-system boundary.
  readonly property var probe: ({
      "Europe/Amsterdam": {
        abbr: "CEST",
        offsetMinutes: 120
      },
      "Europe/London": {
        abbr: "BST",
        offsetMinutes: 60
      },
      "UTC": {
        abbr: "UTC",
        offsetMinutes: 0
      },
      "America/New_York": {
        abbr: "EDT",
        offsetMinutes: -240
      },
      "America/Los_Angeles": {
        abbr: "PDT",
        offsetMinutes: -420
      },
      "Asia/Kolkata": {
        abbr: "IST",
        offsetMinutes: 330
      },
      "Asia/Tokyo": {
        abbr: "JST",
        offsetMinutes: 540
      }
    })
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    name: "input"
    when: false
  }
  QtObject {
    id: shell
    function updateEntryInline(id, entry) {
      testRoot.writes.push({
        id: id,
        entry: entry
      })
      host.settings = entry
    }
  }
  QtObject {
    id: bar
    property QtObject shell: shell
    property string position: "top"
    property bool vertical: false
    property int barSize: 32
    property color barForeground: "white"
  }
  Item {
    id: host
    property string moduleName: "araneadev.worldclock"
    property var settings: ({})
  }
  FloatingWindow {
    visible: true
    width: 1000
    height: 850
    Item {
      id: anchor
      width: 30
      height: 30
    }
    World.Panel {
      id: panel
      bar: bar
      hostWidget: host
      anchorItem: anchor
      systemZone: "Europe/Amsterdam"
      probeData: testRoot.probe
    }
    World.Panel {
      id: peer
      bar: bar
      hostWidget: host
      anchorItem: anchor
      systemZone: "Europe/Amsterdam"
      probeData: testRoot.probe
    }
  }
  // Loads new raw host settings and opens a fresh panel interaction.
  function reset(raw) {
    panel.close()
    host.settings = raw === undefined ? {} : {
      cities: raw
    }
    panel.settings = host.settings
    testRoot.writes = []
    panel.selected = 0
    panel.open()
  }
  // Gives real key events to the production shared key catcher.
  function focusKeys() {
    t.findChild(panel, "worldClockFrame").focusTarget.forceActiveFocus()
  }
  // Extracts visible city order for behavior assertions.
  function names(list) {
    return list.map(function (c) {
      return c.name
    })
  }
  Component.onCompleted: t.step(250, function () {
    reset(undefined)
    t.equal(names(panel.cities), names(Cities.SEED), "empty settings seed five zones")
    t.equal(writes.length, 1, "seed persists once")
    t.equal(writes[0].id, "araneadev.worldclock", "write uses host entry id")
    panel.close()
    panel.open()
    t.equal(writes.length, 1, "reopening does not rewrite normalized settings")
    reset([
      {
        name: "Amsterdam",
        zone: "Europe/Amsterdam"
      },
      {
        name: "Delhi",
        zone: "Asia/Kolkata"
      },
      {
        name: "Tokyo",
        zone: "Asia/Tokyo"
      },
      {
        name: "Los Angeles",
        zone: "America/Los_Angeles"
      },
      {
        name: "New York",
        zone: "America/New_York"
      }
    ])
    t.equal(names(panel.cities), names(Cities.SEED), "untouched upstream seed replaced")
    t.equal(writes.length, 1, "migration persists once")
    reset([
      {
        name: "Amsterdam",
        zone: "Europe/Amsterdam"
      },
      {
        name: "Tokyo",
        zone: "Asia/Tokyo"
      }
    ])
    t.equal(names(panel.cities), ["Amsterdam", "Tokyo"], "edited list preserved")
    t.check(panel.cities[0].home, "system city becomes home")
    t.equal(writes.length, 1, "normalizing adds home once")
    var beforeShowcase = JSON.stringify(host.settings)
    t.equal(panel.showcase('{"nowMs":1792491180000}'), "ok", "showcase accepts fixed time")
    t.equal(names(panel.displayCities), names(Cities.SEED), "showcase defaults to seed cities")
    t.equal(panel.worldView.homeTime, "12:13", "showcase uses fixed local time")
    t.equal(JSON.stringify(host.settings), beforeShowcase, "showcase never writes settings")
    panel.selected = 1;
    ["remove", "moveUp", "moveDown", "setHome", "addStart", "queryChanged", "add"].forEach(function (name) {
      panel.handleAction(name, name === "queryChanged" ? "tok" : 0)
    })
    t.equal(JSON.stringify(host.settings), beforeShowcase, "showcase editing actions cannot change saved cities")
    t.check(!panel.adding && panel.query === "", "showcase cannot start an editing flow")
    panel.close()
    panel.open()
    t.equal(writes.length, 1, "normalized edited list writes no more")
    reset(Cities.serialize(Cities.SEED))
    var savedBeforeLoading = JSON.stringify(host.settings)
    panel.awaitingLoad = true
    panel.selected = 1;
    ["remove", "moveDown", "setHome", "addStart", "queryChanged", "add"].forEach(function (name) {
      panel.handleAction(name, name === "queryChanged" ? "tok" : 0)
    })
    t.equal(JSON.stringify(host.settings), savedBeforeLoading, "pending initial probe cannot overwrite saved cities")
    t.check(!panel.adding && panel.query === "", "pending initial probe cannot start editing")
    panel.awaitingLoad = false
    panel.close()
    panel.handleAction("remove", null)
    t.equal(JSON.stringify(host.settings), savedBeforeLoading, "closed panel actions cannot edit settings")
    reset(Cities.serialize(Cities.SEED))
    focusKeys()
    input.keyClick(Qt.Key_X)
    t.equal(writes.length, 0, "remove home refuses write")
    panel.selected = 4
    input.keyClick(Qt.Key_X)
    t.equal(names(panel.cities), ["Amsterdam", "London", "UTC", "New York"], "x removes chosen last city")
    t.equal(writes.length, 1, "remove persists")
    reset(Cities.serialize(Cities.SEED))
    focusKeys()
    panel.selected = 1
    input.keyClick(Qt.Key_BracketRight)
    t.equal(names(panel.cities), ["Amsterdam", "UTC", "London", "New York", "Los Angeles"], "reorder swaps London and UTC")
    t.equal(panel.selected, 2, "cursor follows moved city")
    reset(Cities.serialize(Cities.SEED))
    focusKeys()
    panel.selected = 3
    input.keyClick(Qt.Key_H)
    t.equal(panel.cities.filter(function (c) {
      return c.home
    }).map(function (c) {
      return c.name
    }), ["New York"], "h marks New York as sole home")
    t.equal(writes.length, 1, "set home persists")
    reset(Cities.serialize(Cities.SEED))
    focusKeys()
    input.keyClick(Qt.Key_A)
    t.check(panel.adding, "a starts search")
    t.step(80, function () {
      input.keyClick(Qt.Key_T)
      input.keyClick(Qt.Key_O)
      input.keyClick(Qt.Key_K)
      t.equal(panel.query, "tok", "typing updates query")
      t.waitFor(function () {
        return panel.matches.length > 0
      }, 2000, "catalog search loads", function () {
        input.keyClick(Qt.Key_Return)
        t.equal(panel.cities[panel.selected].name, "Tokyo", "Enter appends and selects Tokyo")
        t.equal(writes.length, 1, "add writes once")
        panel.close()
        peer.open()
        t.equal(names(peer.cities), names(panel.cities), "second instance sees shared settings on open")
        peer.close()
        panel.open()
        focusKeys()
        input.keyClick(Qt.Key_A)
        t.step(80, function () {
          input.keyClick(Qt.Key_T)
          panel.close()
          t.equal(panel.query, "", "close discards query")
          t.check(!panel.adding, "close exits add mode")
          t.equal(writes.length, 1, "cancelled search never writes")
          t.check(!t.findChild(panel, "worldMinuteClock").enabled, "closed panel does not tick")
          t.check(!t.findChild(panel, "worldGlobe").visible, "closed panel immediately hides globe")
          t.equal(panel.showcase('{"nowMs":1792491180000}'), "closed", "closed showcase refuses overrides")
          var many = []
          for (var i = 0; i < 25; i++)
            many.push({
              name: "City " + i,
              zone: "Europe/Amsterdam",
              home: i === 0
            })
          reset(many)
          focusKeys()
          panel.handleAction("select", 24)
          t.step(80, function () {
            var content = t.findChild(panel, "worldContent")
            t.check(content !== null && content.contentHeight > content.height, "long city lists can scroll")
            t.check(content !== null && content.contentY > 0, "keyboard selection reveals lower rows")
            panel.handleAction("addStart", null)
            t.step(80, function () {
              var field = t.findChild(panel, "cityQuery")
              t.check(field.mapToItem(content, 0, 0).y >= 0 && field.mapToItem(content, 0, field.height).y <= content.height, "search stays visible below long list: y=" + field.mapToItem(content, 0, 0).y + " viewport=" + content.height + " contentY=" + content.contentY + " total=" + content.contentHeight)
              panel.close()
              panel.probeData = null
              panel.systemZone = ""
              panel.systemProbed = false
              panel.open()
              panel.close()
              t.check(!panel.systemProbed && panel.systemZone === "", "interrupted discovery remains unresolved")
              panel.open()
              var retry = t.findChild(panel, "worldZoneProbe")
              t.check(retry.command[2].indexOf("timedatectl") >= 0, "interrupted discovery retries system zone on reopen")
              panel.close()
              panel.probeData = testRoot.probe
              panel.systemZone = "Europe/Amsterdam"
              t.done()
            })
          })
        })
      })
    })
  })
}
