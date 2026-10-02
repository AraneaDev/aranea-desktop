// The Aranea Power dropdown's charge history: the last 24 h of battery
// percentage as an accent to strandEnd step line (UPower only samples on
// change, so the trace holds flat between samples), with a faint
// accent to strandEnd fill under it, over a faint 50% reference line, and a
// glowing dot at the current charge on the right edge. The plot area is
// inset a couple of pixels top and bottom so the 0% and 100% lines are
// fully stroked rather than clipped at the canvas edge. Segments come from
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
  // The plot area's top/bottom pixel inset, so a 0% or 100% stroke never
  // clips at the canvas edge.
  property real inset: 2

  // Maps a unit-space y (0 top, 1 bottom) to the inset plot area's pixel y.
  function plotY(unitY) {
    var top = graph.inset
    var bottom = graph.height - graph.inset
    return top + unitY * Math.max(0, bottom - top)
  }

  // The dot's position in pixels, or null when there is nothing to mark.
  function dotPoint() {
    if (graph.nowPercent >= 0)
      return {
        x: graph.width,
        y: graph.plotY(1 - Math.min(100, graph.nowPercent) / 100)
      }
    var segs = Array.isArray(graph.segments) ? graph.segments : []
    for (var i = segs.length - 1; i >= 0; i--) {
      var seg = segs[i]
      if (Array.isArray(seg) && seg.length > 0)
        return {
          x: seg[seg.length - 1].x * graph.width,
          y: graph.plotY(seg[seg.length - 1].y)
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
    ctx.moveTo(0, Math.round(graph.plotY(0.5)) + 0.5)
    ctx.lineTo(graph.width, Math.round(graph.plotY(0.5)) + 0.5)
    ctx.stroke()

    var segs = Array.isArray(graph.segments) ? graph.segments : []
    var floorY = graph.height - graph.inset

    ctx.globalAlpha = 0.12
    var fillGradient = ctx.createLinearGradient(0, 0, graph.width, 0)
    fillGradient.addColorStop(0, String(Aranea.DesignTokens.accent))
    fillGradient.addColorStop(1, String(Aranea.DesignTokens.strandEnd))
    ctx.fillStyle = fillGradient
    for (var f = 0; f < segs.length; f++) {
      var fillSeg = segs[f]
      if (!Array.isArray(fillSeg) || fillSeg.length === 0)
        continue
      ctx.beginPath()
      ctx.moveTo(fillSeg[0].x * graph.width, floorY)
      ctx.lineTo(fillSeg[0].x * graph.width, graph.plotY(fillSeg[0].y))
      for (var g = 1; g < fillSeg.length; g++)
        ctx.lineTo(fillSeg[g].x * graph.width, graph.plotY(fillSeg[g].y))
      ctx.lineTo(fillSeg[fillSeg.length - 1].x * graph.width, floorY)
      ctx.closePath()
      ctx.fill()
    }

    ctx.globalAlpha = 1
    var gradient = ctx.createLinearGradient(0, 0, graph.width, 0)
    gradient.addColorStop(0, String(Aranea.DesignTokens.accent))
    gradient.addColorStop(1, String(Aranea.DesignTokens.strandEnd))
    ctx.strokeStyle = gradient
    ctx.lineWidth = 1.6
    for (var i = 0; i < segs.length; i++) {
      var seg = segs[i]
      if (!Array.isArray(seg) || seg.length === 0)
        continue
      ctx.beginPath()
      ctx.moveTo(seg[0].x * graph.width, graph.plotY(seg[0].y))
      // A lone point still shows, as a short tick.
      if (seg.length === 1)
        ctx.lineTo(seg[0].x * graph.width + 1, graph.plotY(seg[0].y))
      for (var j = 1; j < seg.length; j++)
        ctx.lineTo(seg[j].x * graph.width, graph.plotY(seg[j].y))
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
