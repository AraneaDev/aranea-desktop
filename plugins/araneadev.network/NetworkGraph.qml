// The Link section's 60 s throughput trace: receive as a mint to violet
// line, send as a fainter violet line, a glowing node on the newest receive
// point, and a bare baseline strand before there are samples. Points come
// from NetworkLogic.graphPoints, so the scale (the larger of both series,
// floored) is tested under Node. Pure view: samples in, nothing out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "NetworkLogic.js" as NetworkLogic

Canvas {
  id: graph

  // Rate samples, oldest first: [{rx, tx}] in bytes per second.
  property var samples: []
  // How many samples span the full width (60 s at 1.5 s apart).
  property int slots: 40
  // The smallest scale in bytes per second, so an idle link stays flat.
  property real floor: 65536
  // The last NetworkLogic.graphPoints result ({rx, tx, scale}), for tests.
  readonly property var points: NetworkLogic.graphPoints(graph.samples, graph.slots, graph.width, graph.height, graph.floor)

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
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var rx = graph.points.rx
    var tx = graph.points.tx
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    if (rx.length === 0) {
      ctx.globalAlpha = 0.15
      ctx.strokeStyle = String(Aranea.DesignTokens.foreground)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(0, graph.height - 0.5)
      ctx.lineTo(graph.width, graph.height - 0.5)
      ctx.stroke()
      return
    }
    ctx.globalAlpha = 0.55
    ctx.strokeStyle = String(Aranea.DesignTokens.strandEnd)
    ctx.lineWidth = 1
    graph.strokeLine(ctx, tx)

    ctx.globalAlpha = 1
    var gradient = ctx.createLinearGradient(0, 0, graph.width, 0)
    gradient.addColorStop(0, String(Aranea.DesignTokens.accent))
    gradient.addColorStop(1, String(Aranea.DesignTokens.strandEnd))
    ctx.strokeStyle = gradient
    ctx.lineWidth = 1.6
    graph.strokeLine(ctx, rx)

    var newest = rx[rx.length - 1]
    ctx.fillStyle = String(Aranea.DesignTokens.accent)
    ctx.shadowColor = String(Aranea.DesignTokens.accent)
    ctx.shadowBlur = 6
    ctx.beginPath()
    ctx.arc(newest.x, newest.y, 2.5, 0, 2 * Math.PI)
    ctx.fill()
  }
}
