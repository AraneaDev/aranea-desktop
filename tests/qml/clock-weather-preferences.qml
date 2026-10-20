// The unified Weather page retains unit and refresh controls without a bar entry.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.clock" as Clock

ShellRoot {
  // Settings patches observed at the production view's persistence boundary.
  property var patches: []
  QmlTest {
    id: t
  }
  Clock.ClockWeatherPreferences {
    id: preferences
    width: 440
    unit: "imperial"
    refreshMinutes: 17
    onSettingsRequested: function (values) {
      patches = patches.concat([values])
    }
  }
  Component.onCompleted: {
    t.check(t.findChild(preferences, "imperialUnits").selected, "current imperial preference is selected")
    t.equal(t.findChild(preferences, "refreshMinutes").text, "17", "custom refresh minutes are retained")
    preferences.unit = "unknown"
    t.check(t.findChild(preferences, "automaticUnits").selected, "an unknown override follows automatic units like the weather model")
    preferences.unit = " METRIC "
    t.check(t.findChild(preferences, "metricUnits").selected, "unit selection follows native case and whitespace normalization")

    t.findChild(preferences, "metricUnits").activate()
    t.equal(patches[0], {
      unit: "metric"
    }, "metric control requests only its own setting")
    t.findChild(preferences, "automaticUnits").activate()
    t.equal(patches[1], {
      unit: ""
    }, "automatic units clear the explicit override")
    var input = t.findChild(preferences, "refreshMinutes")
    var invalid = ["0", "1441", "17x", "2.5", ""]
    for (var i = 0; i < invalid.length; i++) {
      input.text = invalid[i]
      preferences.commitRefresh()
      t.equal(patches.length, 2, "invalid refresh does not write preferences: " + invalid[i])
      t.check(preferences.validationMessage.length > 0, "invalid refresh gives a correction: " + invalid[i])
    }
    input.text = "30"
    preferences.commitRefresh()
    t.equal(patches[2], {
      refreshMinutes: 30
    }, "refresh commits a bounded integer patch")
    t.equal(preferences.validationMessage, "", "valid refresh clears its correction")
    t.done()
  }
}
