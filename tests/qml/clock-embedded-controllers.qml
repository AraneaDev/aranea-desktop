// Real optional clock controllers must remain idle until their host selects them.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.weather"
import "plugins/araneadev.worldclock"

ShellRoot {
  id: testRoot
  QmlTest {
    id: t
  }
  Loader {
    id: weatherLoader
  }
  Loader {
    id: worldLoader
  }
  FileView {
    id: calls
    path: Quickshell.env("ARANEA_TEST_SANDBOX") + "/clock-calls.log"
    printErrors: false
  }
  QtObject {
    id: host
    property bool opened: false
    property string activePage: "calendar"
    property string lastSection: ""
    property var lastValues: null
    property var worldSettings: ({
        cities: [
          {
            name: "London",
            zone: "Europe/London",
            home: true
          }
        ]
      })
    function openSection(page) {
      if (weatherLoader.item)
        weatherLoader.item.deactivateEmbedded()
      if (worldLoader.item)
        worldLoader.item.deactivateEmbedded()
      activePage = page
      opened = true
      if (page === "weather")
        weatherLoader.item.activateEmbedded()
      if (page === "worldclock")
        worldLoader.item.activateEmbedded()
    }
    function close() {
      opened = false
      weatherLoader.item.deactivateEmbedded()
      worldLoader.item.deactivateEmbedded()
    }
    function persistSection(page, values) {
      lastSection = page
      lastValues = values
      worldSettings = values
    }
  }
  // Keyboard focus is captured only at the external host surface.
  QtObject {
    id: focusTarget
    property int requests: 0
    function forceActiveFocus() {
      requests++
    }
  }
  // Inspect issued production requests at the inert external-process boundary.
  function pendingWeatherUrls(weather) {
    var urls = []
    t.findChildren(weather, "").forEach(function (child) {
      if ("running" in child && "command" in child && child.running) {
        var command = child.command
        if (command.length && command[0] === "curl")
          urls.push(command[command.length - 1])
      }
    })
    return urls
  }
  // A fresh primary must not strand canceled secondary requests on reopen.
  function checkCanceledWeather(weather) {
    weather.readyDefers = 6
    weather.configuredLocationState = {
      name: "",
      latitude: null,
      longitude: null
    }
    weather.autoCoords = {
      lat: 1,
      lon: 2
    }
    weather.report = {
      current_condition: [
        {
          temp_C: "12"
        }
      ]
    }
    weather.publishShared(true)
    weather.open()
    weather.refreshDailyForecast({
      lat: 1,
      lon: 2
    })
    var primaryTime = weather.fetchedAtMs
    var cycle = weather.refreshCycle
    t.check(pendingWeatherUrls(weather).some(function (url) {
      return url.indexOf("api.open-meteo.com/v1/forecast") >= 0
    }), "fresh primary has an outstanding secondary forecast")
    t.check(pendingWeatherUrls(weather).some(function (url) {
      return url.indexOf("air-quality-api.open-meteo.com") >= 0
    }), "fresh primary has an outstanding air request")
    weather.close()
    calls.reload()
    t.step(150, function () {
      calls.reload()
      t.step(100, function () {
        t.equal(pendingWeatherUrls(weather), [], "hidden weather cancels outstanding secondary commands")
        var hiddenCalls = calls.text()
        t.step(300, function () {
          calls.reload()
          t.step(100, function () {
            t.equal(calls.text(), hiddenCalls, "canceled secondary work issues no commands while hidden")
            weather.open()
            var resumed = pendingWeatherUrls(weather)
            t.check(resumed.some(function (url) {
              return url.indexOf("api.open-meteo.com/v1/forecast") >= 0
            }), "reopening resumes the canceled secondary forecast")
            t.check(resumed.some(function (url) {
              return url.indexOf("air-quality-api.open-meteo.com") >= 0
            }), "reopening resumes the canceled air request")
            t.check(!resumed.some(function (url) {
              return url.indexOf("wttr.in") >= 0
            }), "reopening retains the fresh primary without another primary request")
            t.equal(weather.refreshCycle, cycle, "resuming canceled extras retains the existing refresh cycle")
            t.equal(weather.fetchedAtMs, primaryTime, "resuming canceled extras preserves primary freshness")
            weather.close()
            t.done()
          })
        })
      })
    })
  }
  Component.onCompleted: {
    weatherLoader.setSource("plugins/araneadev.weather/Panel.qml", {
      embedded: true,
      embeddingHost: host,
      hostedFocusTarget: focusTarget
    })
    worldLoader.setSource("plugins/araneadev.worldclock/Panel.qml", {
      embedded: true,
      embeddingHost: host,
      hostedFocusTarget: focusTarget,
      settings: Qt.binding(function () {
        return host.worldSettings
      }),
      systemZone: "UTC",
      probeData: {
        UTC: {
          offsetMinutes: 0,
          abbrev: "UTC"
        }
      }
    })
    t.step(1750, function () {
      var weather = weatherLoader.item, world = worldLoader.item
      t.check(weather !== null && world !== null, "controllers accept initial embedded host properties")
      if (!weather || !world) {
        t.done()
        return
      }
      calls.reload()
      t.step(100, function () {
        t.equal(calls.text(), "", "embedded construction performs no external commands")
        t.check(!weather.opened && !world.opened, "embedded lifecycles start closed")
        weather.refresh()
        weather.autoRefresh()
        weather.refreshDailyForecast({
          lat: 1,
          lon: 2
        })
        weather.configuredLocationState = {
          name: "Fixture",
          latitude: 1,
          longitude: 2
        }
        t.step(100, function () {
          calls.reload()
          t.step(100, function () {
            t.equal(calls.text(), "", "inactive explicit and location-change refreshes stay idle")
            world.open()
            t.equal(host.activePage, "worldclock", "public world open selects its host section")
            t.check(world.opened && !weather.opened, "selected embedded controller drives inherited opened state")
            t.equal(world.cities, [
              {
                name: "London",
                zone: "Europe/London",
                home: true
              }
            ], "activation reads nested city settings")
            world.writeCities([
              {
                name: "London",
                zone: "Europe/London",
                home: true
              }
            ])
            t.equal(host.lastSection, "worldclock", "embedded city writes target the host page token")
            t.equal(host.lastValues, {
              cities: [
                {
                  name: "London",
                  zone: "Europe/London",
                  home: true
                }
              ]
            }, "real city writer delegates literal saved cities")
            host.worldSettings = {
              cities: [
                {
                  name: "Tokyo",
                  zone: "Asia/Tokyo",
                  home: true
                }
              ]
            }
            world.close()
            world.open()
            t.equal(world.cities, [
              {
                name: "Tokyo",
                zone: "Asia/Tokyo",
                home: true
              }
            ], "city writes preserve reactive nested settings binding")
            world.textKeyboard("a")
            t.check(world.adding, "host keyboard adapter starts the real city editor")
            var before = focusTarget.requests
            host.activePage = "calendar"
            world.deactivateEmbedded()
            t.check(host.opened && !world.opened && !world.adding && world.query === "", "deactivation cancels edits without closing host")
            t.equal(world.showcase('{"nowMs":1792491180000}'), "closed", "inactive showcase cannot select a section")
            t.step(100, function () {
              t.equal(focusTarget.requests, before, "deferred city focus cannot steal the new section")
              weather.open()
              t.equal(host.activePage, "weather", "public weather open selects its host section")
              t.check(weather.opened, "weather activation drives inherited lifecycle")
              weather.textKeyboard("e")
              t.check(weather.editingLocation, "weather keyboard adapter starts the real location editor")
              host.activePage = "calendar"
              weather.deactivateEmbedded()
              before = focusTarget.requests
              t.check(host.opened && !weather.opened && !weather.editingLocation && !weather.fetchInFlight && !weather.awaitingPeer, "weather deactivation cancels editing and fetching without closing host")
              t.step(350, function () {
                t.equal(focusTarget.requests, before, "deferred weather focus cannot steal the new section")
                weather.toggle()
                t.check(host.opened && host.activePage === "weather" && weather.opened, "weather toggle selects its inactive section")
                weather.close()
                t.check(!host.opened && !weather.opened, "embedded close delegates to its owner")
                checkCanceledWeather(weather)
              })
            })
          })
        })
      })
    })
  }
}
