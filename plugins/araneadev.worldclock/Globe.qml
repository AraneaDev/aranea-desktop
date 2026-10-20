// The World Clock's sun-lit globe: an orthographic Earth centred on
// (centerLat, centerLon). The surface (land, day and night, the gold
// terminator band, the rim tint, faint 30 degree meridians) is a
// ShaderEffect, shaders/globe.frag over the land mask land.png (both built
// by tools/build-worldclock-globe); a Canvas overlay draws the sun's gold
// glow when it faces the viewer, the city diamonds (home accent, selected
// violet and labelled, others foreground; night-side cities get a gold city
// light) and the thin accent outline. easeTo spins the view to a place the
// short way round; a pointer drag spins it (lon free, lat clamped to 70
// degrees either way) and, after 4 s idle, it eases home (homeLon, 30N).
// Nothing runs while hidden: the idle timer and the ease stop, an ease
// requested then jumps, and the overlay repaints only on a change while
// visible.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "WorldClockLogic.js" as Logic

Item {
  id: globe

  // The view centre, degrees. centerLon may pass 180 mid-ease and is back in
  // [-180, 180) when the ease ends.
  property real centerLon: 0
  // The view latitude, degrees north.
  property real centerLat: homeViewLat
  // The subsolar point, {lat, lon} degrees.
  property var sun: ({
      lat: 0,
      lon: 0
    })
  // The cities: {lat, lon, role: "home"|"selected"|"other", label, night}.
  property var markers: []
  // Whether a pointer drag spins the globe.
  property bool interactive: true
  // The home view's longitude (the home city's), degrees.
  property real homeLon: 0
  // The home view's latitude: the spec's "lat about 30N".
  readonly property real homeViewLat: 30
  // How far either way a view may tilt, degrees.
  readonly property real latLimit: 70
  // An ease's duration, ms.
  readonly property int easeDuration: 600
  // How far a drag spins the view per pixel, degrees.
  readonly property real degreesPerPixel: 0.5
  // How long the view rests after a drag before it eases home, ms.
  readonly property int idleDelay: 4000
  // The disc's radius, pixels (112 in the 300x236 dropdown area).
  readonly property real radius: Math.max(0, Math.min(width, height) / 2 - 6)
  // Aranea ceremony gold, shared with the daylight rows.
  readonly property color ceremonyGold: Aranea.DesignTokens.ceremonyGold
  // The facing markers as the overlay draws them: {x, y, role, label, night},
  // label "" for all but the selected one.
  readonly property var overlayMarkers: globe.overlayFor(markers, centerLon, centerLat, radius, width, height)

  // A drag started moving the view.
  signal dragged

  implicitWidth: 300
  implicitHeight: 236

  /**
   * Wraps a longitude into [-180, 180).
   * @param {number} lon - degrees
   * @returns {number} the same meridian in [-180, 180)
   */
  function wrapLon(lon) {
    return ((lon + 180) % 360 + 360) % 360 - 180
  }

  /**
   * Clamps a view latitude to the tilt limit.
   * @param {number} lat - degrees
   * @returns {number} lat within [-latLimit, latLimit]
   */
  function clampLat(lat) {
    return Math.max(-latLimit, Math.min(latLimit, lat))
  }

  /**
   * Projects a place onto a view (orthographic).
   * @param {number} lat - the place's latitude, degrees
   * @param {number} lon - the place's longitude, degrees
   * @param {number} cLon - the view centre's longitude, degrees
   * @param {number} cLat - the view centre's latitude, degrees
   * @param {number} r - the disc radius, pixels
   * @param {number} w - the item width, pixels
   * @param {number} h - the item height, pixels
   * @returns {{x: number, y: number, visible: boolean}} item coordinates and whether the place faces the viewer
   */
  function projectOn(lat, lon, cLon, cLat, r, w, h) {
    var rad = Math.PI / 180
    var l = (lon - cLon) * rad
    var p = lat * rad
    var p0 = cLat * rad
    return {
      x: w / 2 + r * Math.cos(p) * Math.sin(l),
      y: h / 2 - r * (Math.cos(p0) * Math.sin(p) - Math.sin(p0) * Math.cos(p) * Math.cos(l)),
      visible: Math.sin(p0) * Math.sin(p) + Math.cos(p0) * Math.cos(p) * Math.cos(l) > 0
    }
  }

  /**
   * Projects a place onto the current view.
   * @param {number} lat - degrees
   * @param {number} lon - degrees
   * @returns {{x: number, y: number, visible: boolean}} item coordinates and whether it faces the viewer
   */
  function project(lat, lon) {
    return projectOn(lat, lon, centerLon, centerLat, radius, width, height)
  }

  /**
   * The overlay model: the markers with coordinates that face the viewer,
   * projected; only the selected one keeps its label.
   * @param {Array} list - the markers
   * @param {number} cLon - the view centre's longitude, degrees
   * @param {number} cLat - the view centre's latitude, degrees
   * @param {number} r - the disc radius, pixels
   * @param {number} w - the item width, pixels
   * @param {number} h - the item height, pixels
   * @returns {Array} {x, y, role, label, night} per facing marker, in order
   */
  function overlayFor(list, cLon, cLat, r, w, h) {
    var out = []
    var items = list || []
    for (let i = 0; i < items.length; i++) {
      const m = items[i]
      if (!m || typeof m.lat !== "number" || typeof m.lon !== "number")
        continue
      const p = projectOn(m.lat, m.lon, cLon, cLat, r, w, h)
      if (!p.visible)
        continue
      const role = m.role === "home" || m.role === "selected" ? m.role : "other"
      out.push({
        x: p.x,
        y: p.y,
        role: role,
        label: role === "selected" ? String(m.label || "") : "",
        night: !!m.night
      })
    }
    return out
  }

  /**
   * Eases the view to a place, the short way round in longitude; the
   * latitude is clamped to the tilt limit. Hidden, it jumps there.
   * @param {number} lat - degrees
   * @param {number} lon - degrees
   */
  function easeTo(lat, lon) {
    ease.stop()
    idle.stop()
    var from = wrapLon(centerLon)
    var to = from + wrapLon(lon - from)
    var toLat = clampLat(lat)
    if (!visible) {
      centerLon = wrapLon(to)
      centerLat = toLat
      return
    }
    centerLon = from
    easeLon.from = from
    easeLon.to = to
    easeLat.from = centerLat
    easeLat.to = toLat
    ease.start()
  }

  /** Eases the view home: (homeViewLat, homeLon). */
  function easeHome() {
    easeTo(homeViewLat, homeLon)
  }

  /**
   * Previews a city, then returns the view home after the idle delay.
   * @param {number} lat - degrees
   * @param {number} lon - degrees
   */
  function previewTo(lat, lon) {
    easeTo(lat, lon)
    if (visible)
      idle.restart()
  }

  // Repaints the overlay, only while it can be seen.
  function repaint() {
    if (visible)
      overlay.requestPaint()
  }

  onVisibleChanged: {
    if (!visible) {
      idle.stop()
      ease.stop()
    } else {
      repaint()
    }
  }
  onOverlayMarkersChanged: repaint()
  onSunChanged: repaint()

  ParallelAnimation {
    id: ease
    objectName: "ease"

    onRunningChanged: if (!running)
      globe.centerLon = globe.wrapLon(globe.centerLon)

    NumberAnimation {
      id: easeLon
      target: globe
      property: "centerLon"
      duration: globe.easeDuration
      easing.type: Easing.InOutCubic
    }
    NumberAnimation {
      id: easeLat
      target: globe
      property: "centerLat"
      duration: globe.easeDuration
      easing.type: Easing.InOutCubic
    }
  }

  Timer {
    id: idle
    objectName: "idleTimer"
    interval: globe.idleDelay
    onTriggered: globe.easeHome()
  }

  // The land mask as a repeating, mipmapped texture, so the shader samples
  // straight across the antimeridian.
  Image {
    id: land
    source: "land.png"
    smooth: true
  }
  ShaderEffectSource {
    id: landTexture
    sourceItem: land
    hideSource: true
    textureSize: Qt.size(2048, 1024)
    wrapMode: ShaderEffectSource.Repeat
    mipmap: true
    smooth: true
    visible: false
  }

  ShaderEffect {
    id: surface
    objectName: "globeShader"

    property real centerLon: globe.centerLon
    property real centerLat: globe.centerLat
    property real radiusPx: globe.radius
    property size viewSize: Qt.size(width, height)
    property vector3d sunDir: {
      var rad = Math.PI / 180
      var s = globe.sun || ({
          lat: 0,
          lon: 0
        })
      return Qt.vector3d(Math.cos(s.lat * rad) * Math.cos(s.lon * rad), Math.cos(s.lat * rad) * Math.sin(s.lon * rad), Math.sin(s.lat * rad))
    }
    property color background: Aranea.DesignTokens.background
    property color foreground: Aranea.DesignTokens.foreground
    property color accent: Aranea.DesignTokens.accent
    property color violet: Aranea.DesignTokens.strandEnd
    property color ceremony: globe.ceremonyGold
    property var source: landTexture

    anchors.fill: parent
    fragmentShader: "shaders/globe.frag.qsb"
  }

  Canvas {
    id: overlay
    anchors.fill: parent

    // TOKEN as a CSS rgba() string at ALPHA.
    function css(token, alpha) {
      var c = Util.alpha(token, alpha)
      return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + alpha + ")"
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var tau = Math.PI * 2
      var gold = globe.ceremonyGold
      var s = globe.sun
      if (s && typeof s.lat === "number" && Logic.sunElevation(globe.centerLat, globe.centerLon, s) > 0) {
        const sp = globe.project(s.lat, s.lon)
        const glow = ctx.createRadialGradient(sp.x, sp.y, 0, sp.x, sp.y, 26)
        glow.addColorStop(0, css(Qt.tint(gold, Util.alpha(Aranea.DesignTokens.foreground, 0.45)), 1))
        glow.addColorStop(0.18, css(gold, 0.7))
        glow.addColorStop(1, css(gold, 0))
        ctx.fillStyle = glow
        ctx.beginPath()
        ctx.arc(sp.x, sp.y, 26, 0, tau)
        ctx.fill()
      }
      var shown = globe.overlayMarkers
      for (let i = 0; i < shown.length; i++) {
        const m = shown[i]
        if (m.night) {
          const light = ctx.createRadialGradient(m.x, m.y, 0, m.x, m.y, 8)
          light.addColorStop(0, css(gold, 0.7))
          light.addColorStop(1, css(gold, 0))
          ctx.fillStyle = light
          ctx.beginPath()
          ctx.arc(m.x, m.y, 8, 0, tau)
          ctx.fill()
        }
        const k = m.role === "selected" ? 4.5 : 3
        ctx.save()
        ctx.translate(m.x, m.y)
        ctx.rotate(Math.PI / 4)
        ctx.fillStyle = css(m.role === "selected" ? Aranea.DesignTokens.strandEnd : m.role === "home" ? Aranea.DesignTokens.accent : Aranea.DesignTokens.foreground, 1)
        ctx.fillRect(-k, -k, 2 * k, 2 * k)
        ctx.restore()
        if (m.label !== "") {
          ctx.font = "600 11px \"" + Aranea.Typography.uiFamily + "\""
          ctx.fillStyle = css(Aranea.DesignTokens.foreground, 1)
          ctx.fillText(m.label, m.x + 8, m.y + 4)
        }
      }
      ctx.strokeStyle = css(Aranea.DesignTokens.accent, 0.35)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.arc(width / 2, height / 2, globe.radius, 0, tau)
      ctx.stroke()
    }
  }

  MouseArea {
    id: dragArea

    // The press point and the view then.
    property real pressX: 0
    property real pressY: 0
    property real startLon: 0
    property real startLat: 0
    // Whether this press has moved the view (dragged() is sent once).
    property bool moved: false

    anchors.fill: parent
    enabled: globe.interactive

    onPressed: mouse => {
      pressX = mouse.x
      pressY = mouse.y
      startLon = globe.centerLon
      startLat = globe.centerLat
      moved = false
    }
    onPositionChanged: mouse => {
      if (!moved) {
        moved = true
        ease.stop()
        startLon = globe.centerLon
        startLat = globe.centerLat
        globe.dragged()
      }
      idle.stop()
      globe.centerLon = globe.wrapLon(startLon - (mouse.x - pressX) * globe.degreesPerPixel)
      globe.centerLat = globe.clampLat(startLat + (mouse.y - pressY) * globe.degreesPerPixel)
    }
    onReleased: if (moved)
      idle.restart()
    onCanceled: if (moved)
      idle.restart()
  }
}
