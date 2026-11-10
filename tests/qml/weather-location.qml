// Production weather controller with sandboxed Process/collector I/O only.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.weather" as Weather

ShellRoot {
  id: testRoot
  QmlTest {
    id: t
  }
  WeatherFixture {
    id: fixture
  }
  QtObject {
    id: host
    property bool opened: false
    property string activePage: "weather"
  }
  Weather.Panel {
    id: weather
    readyDefers: 6
    embedded: true
    embeddingHost: host
  }
  QtObject {
    id: peerHost
    property bool opened: false
    property string activePage: "calendar"
  }
  Weather.Panel {
    id: peer
    embedded: true
    embeddingHost: peerHost
  }
  // Stale primary data must survive detection failures and failed forecasts.
  readonly property var staleReport: ({
      current_condition: [
        {
          temp_C: "17"
        }
      ],
      weather: [],
      nearest_area: [
        {
          latitude: "52.37",
          longitude: "4.9",
          areaName: [
            {
              value: "Amsterdam"
            }
          ]
        }
      ]
    })
  // Last good extras remain visible through failed automatic discovery.
  property var staleForecast: null
  // Last good daily response retained during malformed and failed refreshes.
  property var staleDaily: null
  // Current malformed, empty or timeout scenario.
  property int failureIndex: 0
  // Bounded location command outcomes, including valid-looking timeout output.
  readonly property var failures: [
    {
      geoBody: "{}",
      geoExit: 0
    },
    {
      geoBody: "{bad json",
      geoExit: 0
    },
    {
      geoBody: '{"name":"Timed out city","latitude":1,"longitude":2}',
      geoExit: 28
    }
  ]
  // Location request count before the next scenario.
  property int geoBefore: 0
  // Primary forecast request count before the next scenario.
  property int forecastBefore: 0
  // Exercise each failure through real Process completion and collector state.
  function failDetection() {
    if (failureIndex >= failures.length) {
      testSavedWins()
      return
    }
    geoBefore = fixture.state.geoStarted || 0
    forecastBefore = fixture.state.forecastStarted || 0
    var failure = Object.assign({
      forecastBody: "",
      dailyBody: ""
    }, failures[failureIndex])
    fixture.configure(failure, function () {
      var cycleBefore = weather.refreshCycle
      weather.refresh()
      t.check(weather.isFetching(), "discovery claims process ownership synchronously")
      weather.refresh()
      t.equal(weather.refreshCycle, cycleBefore + 1, "duplicate refresh cannot claim another cycle")
      t.waitFor(function () {
        return fixture.state.geoFinished === geoBefore + 1
      }, 2000, "failed detection exits", function () {
        t.waitFor(function () {
          return fixture.state.forecastStarted === forecastBefore + 1
        }, 1500, "failure continues one fallback forecast", function () {
          t.step(350, function () {
            t.equal(fixture.state.geoStarted, geoBefore + 1, "failed detection has no immediate recursive retry at " + failureIndex)
            t.equal(weather.report, staleReport, "failed response retains stale primary data")
            t.equal(weather.forecast, staleForecast, "failed response retains last-good forecast extras")
            t.equal(weather.dailyForecastReport, staleDaily, "failed response retains last-good daily forecast")
            t.equal(weather.detectedLocationState.name, "Amsterdam", "failed response retains previous detected place")
            t.equal(weather.configuredLocationState, {
              name: "",
              latitude: null,
              longitude: null
            }, "automatic detection leaves saved state unset")
            failureIndex++
            failDetection()
          })
        })
      })
    })
  }
  // Replace a pending automatic lookup with coordinates read from the saved file.
  function testSavedWins() {
    weather.deactivateEmbedded()
    host.opened = false
    // A pending automatic lookup is superseded by an explicit user location.
    fixture.configure({
      geoBody: '{"name":"Wrong city","latitude":1,"longitude":2}',
      geoDelay: 0.8
    }, function () {
      geoBefore = fixture.state.geoStarted
      host.opened = true
      weather.activateEmbedded()
      weather.refresh()
      t.waitFor(function () {
        return fixture.state.geoStarted === geoBefore + 1
      }, 1500, "new automatic lookup starts", function () {
        fixture.configure({
          locationFile: {
            name: "London",
            latitude: 51.5,
            longitude: -0.12
          }
        }, function () {
          weather.locationFile.reload()
        })
        t.waitFor(function () {
          return weather.locationQuery === "51.5,-0.12" && fixture.state.calls.some(function (call) {
            return call.kind === "daily" && call.argv[call.argv.length - 1].indexOf("latitude=51.5&longitude=-0.12") !== -1
          })
        }, 2000, "explicit coordinates start their own forecast", function () {
          t.step(900, function () {
            t.equal(weather.configuredLocationState, {
              name: "London",
              latitude: 51.5,
              longitude: -0.12
            }, "late auto-detect cannot overwrite explicit coordinates")
            t.equal(weather.locationQuery, "51.5,-0.12", "saved coordinates always win")
            t.equal(fixture.state.saved || [], [], "discovery never invokes persistence")
            testIpFallback()
          })
        })
      })
    })
  }
  // A first failed lookup falls back once to wttr's IP query, keeping stale data.
  function testIpFallback() {
    weather.deactivateEmbedded()
    host.opened = false
    fixture.configure({
      locationFile: null,
      geoBody: "{}",
      geoExit: 0,
      geoDelay: 0.15
    }, function () {
      weather.detectedLocationState = {
        name: "",
        latitude: null,
        longitude: null
      }
      weather.report = staleReport
      weather.locationFile.reload()
      geoBefore = fixture.state.geoStarted
      forecastBefore = fixture.state.forecastStarted
      t.waitFor(function () {
        return weather.configuredLocation === ""
      }, 1000, "cleared saved location loads", function () {
        host.opened = true
        weather.activateEmbedded()
        weather.refresh()
        t.waitFor(function () {
          return fixture.state.forecastStarted === forecastBefore + 1
        }, 2000, "first detection failure starts IP fallback", function () {
          t.step(350, function () {
            t.equal(fixture.state.geoStarted, geoBefore + 1, "first failure has one bounded discovery attempt")
            var call = fixture.state.calls.filter(function (entry) {
              return entry.kind === "forecast"
            }).slice(-1)[0]
            t.equal(call.argv.slice(-1)[0], "https://wttr.in/?format=j1", "empty discovery uses existing wttr IP fallback")
            t.equal(weather.report, staleReport, "IP fallback failure keeps stale forecast")
            weather.deactivateEmbedded()
            host.opened = false
            t.done()
          })
        })
      })
    })
  }
  Component.onCompleted: fixture.configure({
    geoBody: '{"name":"Amsterdam","latitude":52.37,"longitude":4.9}',
    geoDelay: 0.3,
    forecastBody: JSON.stringify(staleReport),
    forecastDelay: 0.1,
    dailyBody: JSON.stringify({
      current: {
        temperature_2m: 17,
        weather_code: 2,
        is_day: 1
      },
      daily: {
        time: [],
        weather_code: [],
        temperature_2m_max: [],
        temperature_2m_min: []
      }
    }),
    airBody: '{"current":{"european_aqi":21,"uv_index":1}}'
  }, function () {
    host.opened = true
    weather.report = staleReport
    weather.activateEmbedded()
    weather.refresh()
    t.waitFor(function () {
      return fixture.state.geoStarted === 1
    }, 1500, "automatic lookup starts", function () {
      weather.refresh()
      t.equal(fixture.state.forecastStarted || 0, 0, "forecast waits for location discovery")
      t.waitFor(function () {
        return weather.detectedLocationState.name === "Amsterdam" && fixture.state.forecastStarted === 1
      }, 2000, "city and coordinates drive one forecast", function () {
        t.equal(weather.locationQuery, "52.37,4.9", "detected coordinates drive the forecast query")
        t.equal(weather.configuredLocationState, {
          name: "",
          latitude: null,
          longitude: null
        }, "detected place is ephemeral")
        var geoCall = fixture.state.calls.filter(function (call) {
          return call.kind === "geo"
        })[0]
        t.check(geoCall.argv.indexOf("--max-time") >= 0 && geoCall.argv[geoCall.argv.indexOf("--max-time") + 1] === "4", "location request has a bounded deadline")
        t.check(geoCall.argv.indexOf("--max-filesize") >= 0, "location response size is bounded")
        t.step(250, function () {
          t.equal(fixture.state.dailyStarted, 1, "wttr completion cannot duplicate the daily request for detected coordinates")
          t.equal(fixture.state.airStarted, 1, "one air request owns each coordinate refresh")
          t.equal(weather.sharedWeather.locationQuery, "", "automatic peers share the configured query identity")
          peer.offerShared(weather.sharedWeather)
          t.equal(peer.detectedLocationState.name, "Amsterdam", "an unresolved automatic peer adopts detected location")
          t.equal(peer.forecast, weather.forecast, "automatic peer adopts the owner's forecast")
          staleForecast = weather.forecast
          staleDaily = weather.dailyForecastReport
          t.check(staleForecast !== null && staleDaily !== null, "successful requests establish last-good forecast data")
          failDetection()
        })
      })
    })
  })
}
