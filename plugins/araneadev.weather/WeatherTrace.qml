// The Aranea Weather dropdown's next-24h trace: the temperature as an
// accent to strandEnd line (the Filament gradient) with a faint fill
// under it, faint violet rain-chance bars standing on the floor in the
// lower half, and a glowing dot on the first point (now). Points come from
// WeatherLogic.hourlyPoints, normalised 0..1 (x across, y up: 1 is the
// warmest), so they scale to whatever width the dropdown has; the plot
// area is inset so the extremes are fully stroked. Pure view: inputs in,
// nothing out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Canvas {
  id: trace

  // WeatherLogic.hourlyPoints's result: {temp: [{x, y}], rain: [{x, h}],
  // min, max, now}, or null.
  property var points: null
  // The plot area's top/bottom pixel inset.
  property real inset: 3

  // The temperature points in pixels, oldest first.
  function tracePoints() {
    var temp = trace.points && Array.isArray(trace.points.temp) ? trace.points.temp : []
    var top = trace.inset
    var span = Math.max(0, trace.height - 2 * trace.inset)
    return temp.map(function (p) {
      return {
        x: Number(p.x) * trace.width,
        y: top + (1 - Number(p.y)) * span
      }
    })
  }

  // The rain-chance bars in pixels ({x, y, w, h}), one per slot with a
  // chance above zero, standing on the floor and at most half the height.
  function rainBars() {
    var rain = trace.points && Array.isArray(trace.points.rain) ? trace.points.rain : []
    var w = Math.max(2, trace.width / Math.max(1, rain.length) * 0.6)
    var out = []
    for (var i = 0; i < rain.length; i++) {
      var h = Math.max(0, Math.min(1, Number(rain[i].h) || 0)) * trace.height * 0.5
      if (h <= 0)
        continue
      var cx = Number(rain[i].x) * trace.width
      var x = Math.max(0, Math.min(trace.width - w, cx - w / 2))
      out.push({
        x: x,
        y: trace.height - h,
        w: w,
        h: h
      })
    }
    return out
  }

  // The now dot in pixels (kept inside the canvas), or null.
  function dotPoint() {
    var pts = trace.tracePoints()
    if (pts.length === 0)
      return null
    return {
      x: Math.max(2.5, Math.min(pts[0].x, trace.width - 2.5)),
      y: Math.max(2.5, Math.min(pts[0].y, trace.height - 2.5))
    }
  }

  objectName: "hourlyTrace"
  height: Style.space(52)
  onPointsChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.lineJoin = "round"
    ctx.lineCap = "round"

    var bars = trace.rainBars()
    ctx.globalAlpha = 0.28
    ctx.fillStyle = String(Aranea.DesignTokens.strandEnd)
    for (var b = 0; b < bars.length; b++)
      ctx.fillRect(bars[b].x, bars[b].y, bars[b].w, bars[b].h)

    var pts = trace.tracePoints()
    if (pts.length === 0)
      return
    ctx.globalAlpha = 0.12
    var fillGradient = ctx.createLinearGradient(0, 0, trace.width, 0)
    fillGradient.addColorStop(0, String(Aranea.DesignTokens.accent))
    fillGradient.addColorStop(1, String(Aranea.DesignTokens.strandEnd))
    ctx.fillStyle = fillGradient
    ctx.beginPath()
    ctx.moveTo(pts[0].x, trace.height)
    for (var f = 0; f < pts.length; f++)
      ctx.lineTo(pts[f].x, pts[f].y)
    ctx.lineTo(pts[pts.length - 1].x, trace.height)
    ctx.closePath()
    ctx.fill()

    ctx.globalAlpha = 1
    var gradient = ctx.createLinearGradient(0, 0, trace.width, 0)
    gradient.addColorStop(0, String(Aranea.DesignTokens.accent))
    gradient.addColorStop(1, String(Aranea.DesignTokens.strandEnd))
    ctx.strokeStyle = gradient
    ctx.lineWidth = 1.6
    ctx.beginPath()
    ctx.moveTo(pts[0].x, pts[0].y)
    // A lone point still shows, as a short tick.
    if (pts.length === 1)
      ctx.lineTo(pts[0].x + 1, pts[0].y)
    for (var i = 1; i < pts.length; i++)
      ctx.lineTo(pts[i].x, pts[i].y)
    ctx.stroke()

    var dot = trace.dotPoint()
    ctx.fillStyle = String(Aranea.DesignTokens.accent)
    ctx.shadowColor = String(Aranea.DesignTokens.accent)
    ctx.shadowBlur = 6
    ctx.beginPath()
    ctx.arc(dot.x, dot.y, 2.5, 0, 2 * Math.PI)
    ctx.fill()
  }
}
