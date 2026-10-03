// A link's 60 s throughput trace: receive as a mint to violet line, send as
// a fainter violet line, a glowing node on the newest receive point, and a
// bare baseline strand before there are samples. A host can drop the send
// line (secondary) and lay a soft mint fill under the receive line
// (softFill), as Health's CPU trace does. Points come from
// GraphLogic.graphPoints, so the scale (the larger of both series, floored)
// is tested under Node. Shared by the Network and VPN dropdowns. Pure
// view: samples in, nothing out.
import QtQuick
import qs.Commons
import "GraphLogic.js" as GraphLogic

Canvas {
  id: graph

  // Rate samples, oldest first: [{rx, tx}] in bytes per second.
  property var samples: []
  // How many samples span the full width (60 s at 1.5 s apart).
  property int slots: 40
  // The smallest scale in bytes per second, so an idle link stays flat.
  property real floor: 65536
  // Whether the send (tx) line is drawn.
  property bool secondary: true
  // Whether a soft mint fill fades down from the receive line.
  property bool softFill: false
  // The last GraphLogic.graphPoints result ({rx, tx, scale}), for tests.
  readonly property var points: GraphLogic.graphPoints(graph.samples, graph.slots, graph.width, graph.height, graph.floor)

  // Strokes PTS as one polyline in CTX.
  function strokeLine(ctx, pts) {
    ctx.beginPath()
    for (var i = 0; i < pts.length; i++) {
      if (i === 0)
        ctx.moveTo(pts[i].x, pts[i].y)
      else
        ctx.lineTo(pts[i].x, pts[i].y)
    }
    ctx.stroke()
  }

  objectName: "linkGraph"
  height: Style.space(34)
  onPointsChanged: requestPaint()
  onSecondaryChanged: requestPaint()
  onSoftFillChanged: requestPaint()
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var rx = graph.points.rx
    var tx = graph.points.tx
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    if (rx.length === 0) {
      ctx.globalAlpha = 0.15
      ctx.strokeStyle = String(DesignTokens.foreground)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(0, graph.height - 0.5)
      ctx.lineTo(graph.width, graph.height - 0.5)
      ctx.stroke()
      return
    }
    if (graph.softFill) {
      var fill = ctx.createLinearGradient(0, 0, 0, graph.height)
      fill.addColorStop(0, String(Util.alpha(DesignTokens.accent, 0.25)))
      fill.addColorStop(1, String(Util.alpha(DesignTokens.accent, 0)))
      ctx.fillStyle = fill
      ctx.beginPath()
      ctx.moveTo(rx[0].x, graph.height)
      for (var i = 0; i < rx.length; i++)
        ctx.lineTo(rx[i].x, rx[i].y)
      ctx.lineTo(rx[rx.length - 1].x, graph.height)
      ctx.closePath()
      ctx.fill()
    }
    if (graph.secondary) {
      ctx.globalAlpha = 0.55
      ctx.strokeStyle = String(DesignTokens.strandEnd)
      ctx.lineWidth = 1
      graph.strokeLine(ctx, tx)
    }

    ctx.globalAlpha = 1
    var gradient = ctx.createLinearGradient(0, 0, graph.width, 0)
    gradient.addColorStop(0, String(DesignTokens.accent))
    gradient.addColorStop(1, String(DesignTokens.strandEnd))
    ctx.strokeStyle = gradient
    ctx.lineWidth = 1.6
    graph.strokeLine(ctx, rx)

    var newest = rx[rx.length - 1]
    ctx.fillStyle = String(DesignTokens.accent)
    ctx.shadowColor = String(DesignTokens.accent)
    ctx.shadowBlur = 6
    ctx.beginPath()
    ctx.arc(newest.x, newest.y, 2.5, 0, 2 * Math.PI)
    ctx.fill()
  }
}
