// Real controller lifecycle with sandboxed command and wallpaper boundaries.
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
  Bar.BarForegroundController {
    id: controller
    position: "left"
    barSize: 32
    themeForeground: "#123456"
    themeContrastForeground: "#abcdef"
  }

  // An invalid response cannot replace the theme or enable the sampled color.
  function startInvalidProbe() {
    controller.setRequestedTransparency(true)
    t.check(controller.transparent, "controller applies transparency before any process result")
    t.check(!controller.useTransparentForeground, "pending contrast keeps the theme foreground")
    controller.position = "right"
    controller.themeForeground = "#234567"
    controller.scheduleTransparentForegroundRefresh()
    t.step(60, function () {
      t.equal(fixture.state.started, 0, "refresh burst waits for the debounce")
      t.waitFor(function () {
        return fixture.state.started === 1
      }, 2000, "debounced command starts", function () {
        t.equal(fixture.state.calls, [["right", "32", "#234567", "#abcdef"]], "probe gets latest edge, size and exact theme color arguments")
        controller.position = "bottom"
        controller.refreshTransparentForeground()
        controller.scheduleTransparentForegroundRefresh()
        t.waitFor(function () {
          return fixture.state.finished === 1
        }, 2000, "invalid probe exits", function () {
          t.check(!controller.useTransparentForeground, "invalid probe output never enables sampled foreground")
          t.check(Qt.colorEqual(controller.transparentForeground, "#123456"), "invalid probe output cannot overwrite the retained color")
          t.step(180, function () {
            t.equal(fixture.state.started, 1, "refresh during an in-flight probe is skipped without adding a queued retry")
            startWallpaperProbe()
          })
        })
      })
    })
  }

  // FileView changes restart the same debounce; a late valid read stays alive.
  function startWallpaperProbe() {
    fixture.configure({
      delay: 0.4,
      response: "  #AaBbcC  "
    }, function () {
      fixture.changeWallpaper(function () {
        t.waitFor(function () {
          return fixture.state.started === 2
        }, 2000, "wallpaper watcher starts the next probe", function () {
          t.equal(fixture.state.calls[1], ["bottom", "32", "#234567", "#abcdef"], "wallpaper refresh uses current edge and theme")
          controller.setRequestedTransparency(false)
          t.check(!controller.transparent && !controller.useTransparentForeground, "opaque request applies while contrast command is in flight")
          t.check(Qt.colorEqual(controller.transparentForeground, "#234567"), "opaque request immediately restores current theme foreground")
          t.check(!controller.foregroundAnimationEnabled, "opaque request disables foreground animation before the reset")
          Qt.callLater(function () {
            t.check(!controller.foregroundAnimationEnabled, "controller keeps animation disabled for the first deferred turn")
            Qt.callLater(function () {
              t.check(controller.foregroundAnimationEnabled, "controller restores animation on the second deferred turn")
              t.waitFor(function () {
                return fixture.state.finished === 2 && Qt.colorEqual(controller.transparentForeground, "#aabbcc")
              }, 2000, "late valid result is retained", function () {
                t.check(!controller.transparent && !controller.useTransparentForeground, "late result cannot make an opaque bar transparent")
                t.waitFor(function () {
                  return controller.foregroundAnimationEnabled
                }, 1000, "late result restores foreground animation", startValidProbe)
              })
            })
          })
        })
      })
    })
  }

  // Reopening reuses the persistent controller and accepts a fresh valid color.
  function startValidProbe() {
    fixture.configure({
      delay: 0,
      response: "#667788"
    }, function () {
      controller.barSize = 46
      controller.themeContrastForeground = "#fedcba"
      controller.setRequestedTransparency(true)
      t.check(controller.transparent && !controller.useTransparentForeground, "reenabling transparency is immediate before the new result")
      t.waitFor(function () {
        return controller.useTransparentForeground && fixture.state.finished === 3
      }, 2000, "new valid probe refines transparency", function () {
        t.check(Qt.colorEqual(controller.transparentForeground, "#667788"), "trimmed valid hex result becomes the current foreground")
        t.equal(fixture.state.calls[2], ["bottom", "46", "#234567", "#fedcba"], "subsequent probe consumes latest size and alternative color")
        controller.barSize = 48
        t.step(200, function () {
          t.equal(fixture.state.started, 3, "size alone does not add a new refresh trigger")
          controller.setRequestedTransparency(false)
          controller.themeForeground = "#345678"
          t.check(Qt.colorEqual(controller.transparentForeground, "#345678"), "theme updates while opaque reset the retained foreground")
          controller.setRequestedTransparency(true)
          controller.setRequestedTransparency(false)
          t.step(200, function () {
            t.equal(fixture.state.started, 3, "opaque request suppresses a pending debounced probe")
            t.done()
          })
        })
      })
    })
  }

  Component.onCompleted: fixture.configure({
    started: 0,
    finished: 0,
    calls: [],
    delay: 0.5,
    response: "#12345\n#12345678\nnot a color"
  }, function () {
    t.check(Qt.colorEqual(controller.transparentForeground, "#123456"), "controller starts from explicit theme foreground")
    t.equal(controller.colorHex(Qt.rgba(1, 0.5, 0, 0.25)), "#ff8000", "probe color formatting rounds RGB and ignores alpha")
    controller.scheduleTransparentForegroundRefresh()
    t.step(160, function () {
      t.equal(fixture.state.started, 0, "opaque refresh does not start a probe")
      startInvalidProbe()
    })
  })
}
