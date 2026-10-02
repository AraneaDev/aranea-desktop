// The Aranea Power dropdown's charge history: the last 24 h of battery
// percentage as an accent to strandEnd line, broken between segments (a
// gap in UPower's history), over a faint 50% line, with a glowing dot at
// the current charge on the right edge. Segments come from
// PowerLogic.historyPoints in unit coordinates (width 1, height 1, y down),
// so they scale to whatever width the dropdown has. Pure view: inputs in,
// nothing out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Canvas {
  id: graph

  // Polyline segments in unit coordinates, oldest first: [[{x, y}]].
  property var segments: []
  // The current charge in percent for the dot at the right edge; below 0
  // puts the dot on the newest history point instead.
  property real nowPercent: -1

  // The dot's position in pixels, or null when there is nothing to mark.
  function dotPoint() {
    if (graph.nowPercent >= 0)
      return {
        x: graph.width,
        y: graph.height - (Math.min(100, graph.nowPercent) * graph.height) / 100
      }
    var segs = Array.isArray(graph.segments) ? graph.segments : []
    for (var i = segs.length - 1; i >= 0; i--) {
      var seg = segs[i]
      if (Array.isArray(seg) && seg.length > 0)
        return {
          x: seg[seg.length - 1].x * graph.width,
          y: seg[seg.length - 1].y * graph.height
        }
    }
    return null
  }

  objectName: "powerHistory"
  height: Style.space(44)
  onSegmentsChanged: requestPaint()
  onNowPercentChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.lineJoin = "round"
    ctx.lineCap = "round"

    ctx.globalAlpha = 0.12
    ctx.strokeStyle = String(Aranea.DesignTokens.foreground)
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(0, Math.round(graph.height / 2) + 0.5)
    ctx.lineTo(graph.width, Math.round(graph.height / 2) + 0.5)
    ctx.stroke()

    ctx.globalAlpha = 1
    var gradient = ctx.createLinearGradient(0, 0, graph.width, 0)
    gradient.addColorStop(0, String(Aranea.DesignTokens.accent))
    gradient.addColorStop(1, String(Aranea.DesignTokens.strandEnd))
    ctx.strokeStyle = gradient
    ctx.lineWidth = 1.6
    var segs = Array.isArray(graph.segments) ? graph.segments : []
    for (var i = 0; i < segs.length; i++) {
      var seg = segs[i]
      if (!Array.isArray(seg) || seg.length === 0)
        continue
      ctx.beginPath()
      ctx.moveTo(seg[0].x * graph.width, seg[0].y * graph.height)
      // A lone point still shows, as a short tick.
      if (seg.length === 1)
        ctx.lineTo(seg[0].x * graph.width + 1, seg[0].y * graph.height)
      for (var j = 1; j < seg.length; j++)
        ctx.lineTo(seg[j].x * graph.width, seg[j].y * graph.height)
      ctx.stroke()
    }

    var dot = graph.dotPoint()
    if (!dot)
      return
    ctx.fillStyle = String(Aranea.DesignTokens.accent)
    ctx.shadowColor = String(Aranea.DesignTokens.accent)
    ctx.shadowBlur = 6
    ctx.beginPath()
    ctx.arc(Math.min(dot.x, graph.width - 2.5), Math.max(2.5, Math.min(dot.y, graph.height - 2.5)), 2.5, 0, 2 * Math.PI)
    ctx.fill()
  }
}
