// The World Clock globe in a real window with real pointer events: the
// overlay model projects only the facing markers and labels exactly the
// selected one; easeTo spins the view to a city the short way round and
// lands within half a degree; a drag spins it (100 px right = 50 degrees
// west, latitude clamped to +-70), reports dragged() and, after 4 s idle,
// eases back to the home view (homeLon, 30N); hidden, nothing runs. Where
// the scene graph can run shaders, the globe's ShaderEffect compiles and the
// grab is warmer (R - B) at the subsolar point than at the limb opposite
// it; the offscreen runner's software backend cannot, so those checks are
// reported as QMLTEST SKIP there (the property, model and pointer checks
// always run).
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.worldclock" as WorldClock

ShellRoot {
  id: host

  QmlTest {
    id: t
  }

  // How many times the globe reported a drag.
  property int drags: 0
  // The view before a drag.
  property real lonBefore: 0
  // True only when an RHI window accepted a real render readback.
  property bool renderChecks: false

  // Synthesizes pointer events (TestCase's helpers), never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then finishes.
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

  // The signed difference A - B between longitudes, in (-180, 180].
  function lonDiff(a, b) {
    var d = ((a - b) % 360 + 360) % 360
    return d > 180 ? d - 360 : d
  }

  // Whether the scene graph can run the globe's shader at all.
  function shadersRun() {
    var api = shader().GraphicsInfo.api
    return api !== GraphicsInfo.Software && api !== GraphicsInfo.Unknown
  }

  // The globe's ShaderEffect.
  function shader() {
    return t.findChild(globe, "globeShader")
  }

  FloatingWindow {
    implicitWidth: 320
    implicitHeight: 256
    visible: true

    // Reads a grabbed image's pixels back.
    Canvas {
      id: probe
      // The grabbed image's url.
      property string src: ""
      // RGBA at the subsolar point and at the limb opposite, once read.
      property var sunPixel: null
      property var limbPixel: null
      // The two points, item coordinates.
      property var sunAt: null
      property var limbAt: null
      width: 1
      height: 1
      z: -1
      onImageLoaded: requestPaint()
      onPaint: {
        if (probe.src === "" || !probe.isImageLoaded(probe.src))
          return
        // The grab's own pixels, never drawn: on a scaled screen (a
        // real-GPU run) the grab is larger than the item.
        var image = getContext("2d").createImageData(probe.src)
        var ratio = image.width / globe.width
        function pixel(at) {
          var i = (Math.round(at.y * ratio) * image.width + Math.round(at.x * ratio)) * 4
          return [image.data[i], image.data[i + 1], image.data[i + 2], image.data[i + 3]]
        }
        probe.sunPixel = pixel(sunAt)
        probe.limbPixel = pixel(limbAt)
      }
    }

    WorldClock.Globe {
      id: globe
      x: 10
      y: 10
      width: 300
      height: 236
      sun: ({
          lat: -10.6,
          lon: 22
        })
      centerLon: 4.9
      centerLat: 30
      homeLon: 4.9
      markers: [
        {
          lat: 52.37,
          lon: 4.9,
          role: "home",
          label: "Amsterdam",
          night: false
        },
        {
          lat: 51.51,
          lon: -0.13,
          role: "selected",
          label: "London",
          night: false
        },
        {
          lat: 40.71,
          lon: -74.01,
          role: "other",
          label: "New York",
          night: true
        },
        {
          lat: 35.68,
          lon: 139.69,
          role: "other",
          label: "Tokyo",
          night: true
        }
      ]
      onDragged: host.drags += 1
    }
  }

  Component.onCompleted: run([[300, function () {
        // ---------- The overlay model ----------
        var shown = globe.overlayMarkers
        t.equal(shown.map(function (m) {
          return m.role
        }), ["home", "selected", "other"], "the facing markers are projected, Tokyo (behind) is not")
        var labelled = shown.filter(function (m) {
          return m.label !== ""
        })
        t.equal(labelled.length, 1, "exactly one marker is labelled")
        t.equal(labelled[0].label, "London", "and it is the selected one")
        t.check(shown[2].night && !shown[0].night, "night-side markers keep their night flag (the gold glow)")
        var home = globe.project(52.37, 4.9)
        t.check(home.visible && Math.abs(home.x - 150) < 0.5 && home.y < 118, "home projects on the centre meridian, north of the centre")
        t.check(Math.abs(shown[0].x - home.x) < 0.01 && Math.abs(shown[0].y - home.y) < 0.01, "the overlay marker sits at its projection")
        t.check(globe.radius === 112, "the globe radius is 112 in a 300x236 area")

        // ---------- The shader (only where shaders run) ----------
        if (!shadersRun()) {
          t.skip("the globe shader compiles", "the scene graph runs the software backend (GraphicsInfo.api " + shader().GraphicsInfo.api + "), which has no shaders")
          t.skip("the subsolar point is warmer than the limb opposite it", "no shaders on the software backend")
          return
        }
        var sun = globe.project(-10.6, 22)
        var dx = sun.x - globe.width / 2
        var dy = sun.y - globe.height / 2
        var len = Math.sqrt(dx * dx + dy * dy) || 1
        probe.sunAt = sun
        probe.limbAt = {
          x: globe.width / 2 - dx / len * (globe.radius - 4),
          y: globe.height / 2 - dy / len * (globe.radius - 4)
        }
        var file = Qt.resolvedUrl("worldclock-globe-grab.png")
        host.renderChecks = globe.grabToImage(function (result) {
          t.check(result.saveToFile(decodeURIComponent(String(file).replace(/^file:\/\//, ""))), "the globe grab is saved for pixel readback")
          probe.src = String(file)
          probe.loadImage(probe.src)
        })
        if (!host.renderChecks) {
          // Offscreen OpenGL can report an API even when QRhi context
          // creation failed. Shader status alone does not prove a frame ran.
          t.skip("the globe shader compiles", "the window cannot render a grab (no functional graphics context)")
          t.skip("the subsolar point is warmer than the limb opposite it", "the window cannot render a grab")
        }
      }], [600, function () {
        if (host.renderChecks) {
          t.check(shader().status === ShaderEffect.Compiled, "the globe shader compiles after rendering (" + shader().log + ")")
          var s = probe.sunPixel
          var l = probe.limbPixel
          t.check(!!s && !!l && s[3] > 0 && l[3] > 0, "both pixels were read from the grab")
          t.check(!!s && s[0] > s[2] && s[0] - s[2] > l[0] - l[2], "the subsolar point " + JSON.stringify(s) + " is warmer than the limb opposite " + JSON.stringify(l))
        }

        // ---------- Easing ----------
        globe.easeTo(51.51, -0.13)
      }], [globe.easeDuration + 200, function () {
        t.check(Math.abs(lonDiff(globe.centerLon, -0.13)) < 0.5, "easeTo lands on the city's longitude (" + globe.centerLon + ")")
        t.check(Math.abs(globe.centerLat - 51.51) < 0.5, "and on its latitude (" + globe.centerLat + ")")
        globe.easeTo(35.68, 139.69)
      }], [globe.easeDuration + 200, function () {
        globe.easeTo(0, -170)
      }], [globe.easeDuration / 2, function () {
        // 139.69 to -170 is 50 degrees east across the antimeridian, not
        // 310 west: halfway sits between them on the short side.
        var along = lonDiff(globe.centerLon, 139.69)
        t.check(along > 5 && along < 45, "an ease takes the short way across the antimeridian (" + globe.centerLon + ")")
      }], [globe.easeDuration / 2 + 200, function () {
        t.check(Math.abs(lonDiff(globe.centerLon, -170)) < 0.5, "and lands (" + globe.centerLon + ")")
        t.check(globe.centerLon >= -180 && globe.centerLon < 180, "the view longitude ends in [-180, 180)")

        // ---------- Dragging ----------
        globe.easeTo(30, 4.9)
      }], [globe.easeDuration + 200, function () {
        host.lonBefore = globe.centerLon
        pointer.mousePress(globe, 150, 118)
        pointer.mouseMove(globe, 200, 118)
        pointer.mouseMove(globe, 250, 118)
        pointer.mouseRelease(globe, 250, 118)
      }], [50, function () {
        t.check(Math.abs(lonDiff(globe.centerLon, host.lonBefore) + 50) < 1.5, "a 100 px drag right spins the view 50 degrees west (" + lonDiff(globe.centerLon, host.lonBefore) + ")")
        t.check(Math.abs(globe.centerLat - 30) < 0.01, "a horizontal drag keeps the latitude")
        t.equal(host.drags, 1, "the drag is reported once")
        t.check(t.findChild(globe, "idleTimer").running, "the idle timer starts after the drag")
        pointer.mousePress(globe, 150, 20)
        pointer.mouseMove(globe, 150, 120)
        pointer.mouseMove(globe, 150, 230)
        pointer.mouseRelease(globe, 150, 230)
      }], [50, function () {
        t.equal(globe.centerLat, 70, "a long drag down clamps the latitude at 70")
        pointer.mousePress(globe, 150, 230)
        pointer.mouseMove(globe, 150, 120)
        pointer.mouseMove(globe, 150, 0)
        pointer.mouseMove(globe, 150, -200)
        pointer.mouseRelease(globe, 150, -200)
      }], [50, function () {
        t.equal(globe.centerLat, -70, "a long drag up clamps the latitude at -70")
        t.equal(host.drags, 3, "each drag is reported once")
        globe.homeLon = 139.69
      }], [4000 + globe.easeDuration + 300, function () {
        t.check(Math.abs(lonDiff(globe.centerLon, 139.69)) < 0.5 && Math.abs(globe.centerLat - 30) < 0.5, "after 4 s idle the view eases home to (30, homeLon) (" + globe.centerLat + ", " + globe.centerLon + ")")
        t.check(!t.findChild(globe, "idleTimer").running, "the idle timer has stopped")

        // A city preview returns the view home without changing its marker.
        globe.previewTo(51.51, -0.13)
      }], [globe.easeDuration + 200, function () {
        t.check(Math.abs(lonDiff(globe.centerLon, -0.13)) < 0.5 && Math.abs(globe.centerLat - 51.51) < 0.5, "a city preview eases to the city")
        t.check(t.findChild(globe, "idleTimer").running, "a city preview schedules the idle return")
      }], [4000 + globe.easeDuration, function () {
        t.check(Math.abs(lonDiff(globe.centerLon, 139.69)) < 0.5 && Math.abs(globe.centerLat - 30) < 0.5, "a city preview returns the view home after 4 s idle")
        t.equal(globe.overlayMarkers.filter(function (m) {
          return m.role === "selected"
        }).length, 0, "returning the view home keeps the selected marker behind the globe")

        // ---------- Hidden ----------
        pointer.mousePress(globe, 150, 118)
        pointer.mouseMove(globe, 180, 118)
        pointer.mouseRelease(globe, 180, 118)
        globe.easeTo(0, 0)
        globe.visible = false
        t.check(!t.findChild(globe, "idleTimer").running, "hiding stops the idle timer")
        t.check(!t.findChild(globe, "ease").running, "hiding stops the ease")
        globe.previewTo(51.51, -0.13)
        t.check(!t.findChild(globe, "idleTimer").running, "a hidden preview does not start an idle timer")
        globe.interactive = false
        globe.visible = true
        var before = globe.centerLon
        pointer.mousePress(globe, 150, 118)
        pointer.mouseMove(globe, 250, 118)
        pointer.mouseRelease(globe, 250, 118)
        t.equal(globe.centerLon, before, "a non-interactive globe ignores drags")
      }]])
}
