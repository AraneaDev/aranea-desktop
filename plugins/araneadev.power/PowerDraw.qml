// The Aranea Power dropdown's live power draw: one strandEnd trace of the
// battery's EnergyRate while the dropdown is open, scaled by
// GraphLogic.graphPoints (the samples' rx is watts; tx is ignored), or a
// bare baseline before there are samples. Pure view: samples in, nothing
// out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.shared/GraphLogic.js" as GraphLogic

Canvas {
  id: trace

  // Draw samples, oldest first: [{rx: watts, tx: 0}].
  property var samples: []
  // How many samples span the full width (60 s at 1.5 s apart).
  property int slots: 40
  // The smallest scale in watts, so a near-idle draw stays low.
  property real floor: 5
  // The last GraphLogic.graphPoints result ({rx, tx, scale}), for tests.
  readonly property var points: GraphLogic.graphPoints(trace.samples, trace.slots, trace.width, trace.height, trace.floor)

  objectName: "powerDraw"
  height: Style.space(26)
  onPointsChanged: requestPaint()
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    var pts = trace.points.rx
    if (pts.length === 0) {
      ctx.globalAlpha = 0.15
      ctx.strokeStyle = String(Aranea.DesignTokens.foreground)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(0, trace.height - 0.5)
      ctx.lineTo(trace.width, trace.height - 0.5)
      ctx.stroke()
      return
    }
    ctx.strokeStyle = String(Aranea.DesignTokens.strandEnd)
    ctx.lineWidth = 1.4
    ctx.beginPath()
    for (var i = 0; i < pts.length; i++) {
      if (i === 0)
        ctx.moveTo(pts[i].x, pts[i].y)
      else
        ctx.lineTo(pts[i].x, pts[i].y)
    }
    ctx.stroke()
  }
}
