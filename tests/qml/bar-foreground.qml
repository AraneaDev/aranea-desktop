// Characterize the production Bar API before and after controller extraction.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.bar" as Bar

ShellRoot {
  QmlTest {
    id: t
  }
  BarForegroundFixture {
    id: fixture
  }
  Bar.Bar {
    id: owner
    motionEnabled: false
    themeForeground: "#123456"
    themeContrastForeground: "#abcdef"
    barConfig: ({
        transparent: false
      })
  }

  Component.onCompleted: fixture.configure({
    started: 0,
    finished: 0,
    calls: [],
    delay: 0.5,
    response: "  #AaBbcC  "
  }, function () {
    owner.setRequestedTransparency(true)
    t.check(owner.transparent, "bar surface becomes transparent before its probe completes")
    t.check(!owner.useTransparentForeground, "pending bar probe keeps the theme foreground")
    t.waitFor(function () {
      return owner.useTransparentForeground
    }, 2000, "bar API receives the contrast result", function () {
      t.check(Qt.colorEqual(owner.barForeground, "#aabbcc"), "plugin-facing foreground uses the probed color")
      var api = owner.pluginBarApiFor("araneadev.clock", "araneadev.clock", true)
      t.check(Qt.colorEqual(api.barForeground, "#aabbcc") && api.transparent, "plugin API observes live transparent appearance")
      owner.setRequestedTransparency(false)
      t.check(!owner.transparent && !owner.useTransparentForeground, "opaque request resets the bar synchronously")
      t.check(Qt.colorEqual(owner.transparentForeground, "#123456") && Qt.colorEqual(api.barForeground, "#123456"), "opaque request resets both root and plugin foreground")
      t.check(!owner.foregroundAnimationEnabled, "opaque foreground jumps without animation")
      Qt.callLater(function () {
        t.check(!owner.foregroundAnimationEnabled, "foreground animation stays disabled through the first deferred turn")
        Qt.callLater(function () {
          t.check(owner.foregroundAnimationEnabled && api.foregroundAnimationEnabled, "foreground animation returns on the second deferred turn")
          t.done()
        })
      })
    })
  })
}
