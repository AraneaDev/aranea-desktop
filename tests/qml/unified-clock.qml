// Real default Clock loader, hosted dropdowns and own-entry settings transport.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.clock" as Clock
import "plugins/araneadev.weather"
import "plugins/araneadev.worldclock"

ShellRoot {
  id: fixture
  // Last full entry captured at the shell persistence boundary.
  property var written: null
  // Entry identity captured alongside that write.
  property string writtenId: ""
  // Every scoped peer lookup made by production controllers.
  property var requestedIds: []
  // Detect focus acquired by a hidden Calendar editor.
  property bool staleLifeFocus: false
  QmlTest {
    id: t
  }
  TestCase {
    id: pointer
    when: false
  }
  // Commands invoked by the real clock middle-click handler.
  property var barCommands: []
  FileView {
    id: calls
    path: Quickshell.env("ARANEA_TEST_SANDBOX") + "/clock-calls.log"
    printErrors: false
  }
  QtObject {
    id: bar
    property string position: "top"
    property bool vertical: false
    property int barSize: 26
    property color foreground: "white"
    property color barForeground: "white"
    property color urgent: "#ff6688"
    property color background: "#17151f"
    property string fontFamily: "monospace"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property bool centerHoverRevealSuppressed: false
    property var layoutConfig: ({
        center: ["araneadev.clock"]
      })
    property QtObject shell: QtObject {
      function updateEntryInline(id, entry) {
        fixture.writtenId = id
        fixture.written = entry
      }
    }
    function run(command) {
      fixture.barCommands = fixture.barCommands.concat([command])
    }
    function requestPopout(owner) {
      activePopout = owner
    }
    function releasePopout(owner) {
      if (activePopout === owner)
        activePopout = null
    }
    function hideTooltip(owner) {
    }
    function showTooltip(owner, text) {
    }
    function setCenterHoverRevealSuppressed(value) {
      centerHoverRevealSuppressed = value
    }
    function moduleWidgets(id) {
      fixture.requestedIds = fixture.requestedIds.concat([id])
      return id === "araneadev.clock" ? [clock, peer] : []
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 1000
    implicitHeight: 800
    Clock.BarWidget {
      id: clock
      moduleName: "araneadev.clock"
      bar: bar
      settings: ({
          format: "HH:mm",
          weekStartDay: 1,
          metadata: "keep",
          weather: {
            unit: "f"
          },
          worldClock: {
            cities: [
              {
                name: "UTC",
                zone: "UTC",
                home: true
              }
            ]
          }
        })
    }
    Clock.BarWidget {
      id: peer
      x: 300
      moduleName: "araneadev.clock"
      bar: bar
      settings: clock.settings
    }
  }
  // Hold actual pointer presses through the host WidgetButton animation and
  // inspect the painted Text's transformed bounds, then its real actions.
  function checkClockPresses() {
    var button = t.childrenOf(clock).filter(function (child) {
      return child.heldButtons !== undefined
    })[0]
    var label = t.childrenOf(button).filter(function (child) {
      return child.text === clock.displayText && child.font !== undefined
    })[0]
    t.check(label && label.visible && label.paintedWidth > 0, "clock has an actual painted label")
    var originalSettings = clock.settings
    var buttons = [Qt.LeftButton, Qt.RightButton, Qt.MiddleButton]
    for (var i = 0; i < buttons.length; i++) {
      clock.close()
      pointer.wait(220)
      var before = label.mapToItem(clock, 0, 0, label.width, label.height)
      pointer.mousePress(button, button.width / 2, button.height / 2, buttons[i])
      pointer.wait(220)
      t.equal(label.scale, 1, "held clock label keeps its painted scale for button " + buttons[i])
      var after = label.mapToItem(clock, 0, 0, label.width, label.height)
      t.equal([after.x, after.y, after.width, after.height], [before.x, before.y, before.width, before.height], "held clock label keeps transformed geometry for button " + buttons[i])
      pointer.mouseRelease(button, button.width / 2, button.height / 2, buttons[i])
      pointer.wait(30)
      if (buttons[i] === Qt.LeftButton) {
        t.check(clock.opened && bar.activePopout === clock, "real left click opens the shared popup")
        pointer.mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton)
        t.check(!clock.opened, "second real left click closes the shared popup")
      } else if (buttons[i] === Qt.RightButton) {
        t.equal(clock.configuredFormat, "h:mm AP", "real right click advances the configured format ring")
        t.equal(fixture.written.format, clock.configuredFormat, "format click persists through the actual shell boundary")
        clock.settings = originalSettings
      } else {
        t.equal(fixture.barCommands, ["omarchy-menu-timezone"], "real middle click invokes timezone picker once")
      }
      // The bar drag owner can hold a button without delivering MouseArea input.
      button.heldButtons = buttons[i]
      pointer.wait(220)
      t.equal(label.scale, 1, "bar-owned held press leaves the actual label still for button " + buttons[i])
      button.heldButtons = Qt.NoButton
    }
    clock.close()
    fixture.written = null
    fixture.writtenId = ""
  }
  Component.onCompleted: t.step(1800, function () {
    var minuteClock = t.childrenOf(clock).filter(function (child) {
      return child.step === 60000
    })[0]
    t.check(!!minuteClock, "bar uses the epoch-aligned minute clock")
    minuteClock.date = new Date(2026, 9, 25, 2, 59)
    t.equal(clock.displayText, "02:59", "minute clock keeps the configured bar format")
    clock.refresh()
    t.check(Math.abs(clock.displayDate.getTime() - Date.now()) < 1000, "explicit bar refresh restores the current epoch")
    var p = clock.clockPanel
    t.check(p !== null, "default production panel loads")
    t.check(p && typeof p.openSection === "function", "default panel exposes unified sections")
    if (!p || typeof p.openSection !== "function") {
      t.done()
      return
    }
    t.check(clock.weatherPanel && clock.worldClockPanel, "own-ID aliases expose both real embedded controllers")
    calls.reload()
    t.step(100, function () {
      t.equal(calls.text(), "", "closed construction starts no page commands")
      var frame = t.findChild(p, "clockFrame")
      t.check(frame !== null && frame.owner === clock && frame.anchorItem === p.anchorItem && !frame.centerOnBar, "single frame anchors to the actual mounted clock owner")
      clock.openSection("worldclock")
      t.check(p.opened && clock.worldClockPanel.opened && !clock.weatherPanel.opened, "direct world open activates only selected controller")
      t.check(bar.activePopout === clock, "shared coordinator owns the mounted clock")
      calls.reload()
      t.waitFor(function () {
        return !clock.worldClockPanel.awaitingLoad
      }, 4000, "World Clock finishes real probe", function () {
        t.check(calls.text().indexOf("curl") < 0, "direct world open never starts Calendar or Weather requests")
        clock.worldClockPanel.writeCities([
          {
            name: "London",
            zone: "Europe/London",
            home: true
          }
        ])
        t.equal(fixture.writtenId, "araneadev.clock", "nested city writer uses own clock entry")
        t.equal(fixture.written, {
          id: "araneadev.clock",
          format: "HH:mm",
          weekStartDay: 1,
          metadata: "keep",
          weather: {
            unit: "f"
          },
          worldClock: {
            cities: [
              {
                name: "London",
                zone: "Europe/London",
                home: true
              }
            ]
          }
        }, "actual city writes preserve Calendar Weather and metadata")
        clock.worldClockPanel.persistCities([
          {
            name: "London",
            zone: "Europe/London",
            home: true
          },
          {
            name: "Tokyo",
            zone: "Asia/Tokyo"
          }
        ])
        frame.moveRequested(0, 1)
        frame.textKey("h")
        frame.textKey("[")
        t.equal(fixture.written.worldClock.cities, [
          {
            name: "Tokyo",
            zone: "Asia/Tokyo",
            home: true
          },
          {
            name: "London",
            zone: "Europe/London"
          }
        ], "shared frame routes city selection home and reorder to nested persistence")
        t.equal(fixture.written.weather, {
          unit: "f"
        }, "city home and reorder retain Weather preferences")
        clock.worldClockPanel.persistCities([
          {
            name: "London",
            zone: "Europe/London",
            home: true
          }
        ])
        p.persistSettings({
          birthYear: 1980
        })
        t.equal(fixture.written.worldClock.cities, [
          {
            name: "London",
            zone: "Europe/London",
            home: true
          }
        ], "Calendar writer preserves latest city write")
        p.persistSection("weather", {
          refreshMinutes: 20
        })
        t.equal(fixture.written.weather, {
          unit: "f",
          refreshMinutes: 20
        }, "section writer merges nested preferences")
        t.equal(fixture.written.birthYear, 1980, "Weather writer preserves Calendar changes")
        clock.worldClockPanel.handleAction("addStart", null)
        t.check(clock.worldClockPanel.adding, "real hosted city editor starts before switching")
        var cityEditor = t.findChild(frame, "cityQuery")
        cityEditor.focus = false
        p.selectPage("weather")
        t.check(bar.centerHoverRevealSuppressed, "World to Weather retains shared owner hover suppression")
        t.check(!clock.worldClockPanel.adding && clock.weatherPanel.opened, "page changes cancel city edits and activate Weather")
        var preferences = t.findChild(frame, "clockWeatherPreferences")
        t.check(preferences !== null, "Weather page retains its unit and refresh controls")
        if (!preferences) {
          t.done()
          return
        }
        t.findChild(preferences, "metricUnits").activate()
        t.equal(fixture.written.weather, {
          unit: "metric",
          refreshMinutes: 20
        }, "real Weather unit control patches only nested preferences")
        var refreshInput = t.findChild(preferences, "refreshMinutes")
        refreshInput.text = "25"
        preferences.commitRefresh()
        t.equal(fixture.written.weather, {
          unit: "metric",
          refreshMinutes: 25
        }, "real refresh control preserves the current unit")
        t.equal(fixture.written.birthYear, 1980, "Weather controls preserve Calendar settings")
        t.equal(fixture.written.worldClock.cities, [
          {
            name: "London",
            zone: "Europe/London",
            home: true
          }
        ], "Weather controls preserve edited cities")
        refreshInput.forceActiveFocus()
        refreshInput.text = "42"
        p.selectPage("calendar")
        t.check(!refreshInput.focus, "leaving Weather releases its numeric editor focus")
        t.equal(refreshInput.text, "25", "leaving Weather cancels unsubmitted refresh input")
        p.selectPage("weather")
        t.equal(fixture.written.weather, {
          unit: "metric",
          refreshMinutes: 25
        }, "cancelled refresh never changes saved preferences")
        clock.weatherPanel.startEditingLocation()
        p.selectPage("calendar")
        t.check(!clock.weatherPanel.editingLocation && p.activePageController === p, "Calendar selection cancels Weather edits")
        var compat = t.findChild(clock, "clockCompatIpc")
        t.check(compat.weatherEnabled && compat.worldClockEnabled, "legacy targets enabled without standalone entries")
        bar.layoutConfig = {
          left: ["omarchy.weather"],
          right: [
            {
              id: "araneadev.worldclock"
            }
          ]
        }
        t.check(!compat.weatherEnabled && !compat.worldClockEnabled, "native strings and Aranea objects disable duplicate legacy IPC")
        bar.layoutConfig = {
          center: ["araneadev.clock"]
        }
        compat.closeSection("weather")
        t.check(p.isSectionOpen("calendar"), "legacy Weather close leaves Calendar open")
        t.equal(compat.showcaseWorld('{"nowMs":1792491180000}'), "closed", "legacy showcase never opens a different page")
        p.startEditingLife()
        var born = t.findChild(frame, "bornField")
        born.focus = false
        born.focusChanged.connect(function () {
          if (born.focus && !p.calendarActive)
            fixture.staleLifeFocus = true
        })
        p.selectPage("worldclock")
        t.check(!p.editingLife, "leaving Calendar cancels life edits")
        p.selectPage("calendar")
        t.check(bar.centerHoverRevealSuppressed, "World to Calendar retains shared owner hover suppression")
        p.selectPage("worldclock")
        clock.close()
        t.check(!bar.centerHoverRevealSuppressed, "closing shared Clock clears hover suppression")
        clock.open()
        t.equal(p.activePage, "calendar", "normal clock open always starts on Calendar")
        p.selectPage("worldclock")
        t.waitFor(function () {
          return !clock.worldClockPanel.awaitingLoad
        }, 4000, "reopened World Clock finishes real probe", function () {
          clock.worldClockPanel.handleAction("addStart", null)
          t.check(clock.worldClockPanel.adding, "real hosted city editor starts before immediate close")
          var editor = t.findChild(frame, "cityQuery")
          t.check(editor.parent.parent.visible, "hosted editor is visible before queued focus runs")
          editor.focus = false
          clock.close()
          t.step(150, function () {
            t.check(!fixture.staleLifeFocus, "queued life editor focus cannot steal another page")
            t.check(!editor.focus, "queued real city editor focus cannot survive close")
            t.check(!cityEditor.focus, "queued real city editor focus cannot survive page switch")
            compat.editWeather()
            t.check(clock.isSectionOpen("weather") && clock.weatherPanel.editingLocation, "legacy edit selects Weather before opening its editor")
            clock.weatherPanel.label = "Shared fixture"
            clock.weatherPanel.publishShared(true)
            t.equal(peer.weatherPanel.label, "Shared fixture", "real weather publication reaches the second clock monitor")
            t.check(peer.weatherPanel.instancePanels().indexOf(clock.weatherPanel) >= 0, "second monitor discovers Weather through own clock aliases")
            t.check(fixture.requestedIds.every(function (id) {
              return id === "araneadev.clock"
            }), "peer discovery stays within own entry permission")
            clock.close()
            clock.openSection("worldclock")
            t.waitFor(function () {
              return !clock.worldClockPanel.awaitingLoad
            }, 4000, "normal add awaits real probe", function () {
              clock.worldClockPanel.handleAction("addStart", null)
              t.step(50, function () {
                t.check(editor.focus, "normal visible city add still focuses its real editor")
                clock.open()
                p.startEditingLife()
                t.step(50, function () {
                  t.check(born.focus, "normal visible Calendar life edit still focuses its field")
                  p.cancelEditingLife()
                  p.startEditingLife()
                  born.focus = false
                  clock.close()
                  t.step(50, function () {
                    t.check(!fixture.staleLifeFocus, "immediate Calendar close cancels queued life focus")
                    var children = p.children
                    for (var i = 0; i < children.length; i++) {
                      var child = children[i]
                      if ("source" in child && String(child.source).indexOf("/Panel.qml") >= 0)
                        child.active = false
                    }
                    clock.open()
                    t.check(p.calendarActive && !p.weatherPanel && !p.worldClockPanel, "Calendar remains usable with unavailable optional controllers")
                    t.check(!p.selectPage("weather") && p.calendarActive, "unavailable optional page preserves Calendar")
                    clock.close()
                    peer.close()
                    checkClockPresses()
                    t.done()
                  })
                })
              })
            })
          })
        })
      })
    })
  })
}
