// The Aranea agents bar ring: a thin arc around the bar glyph that fills
// clockwise from the top with the highest limit used across the current
// agent's windows (AgentsLogic.ringFraction), in a token colour by
// AgentsLogic.ringTone: the accent below 80%, amber from 80%, urgent from
// 95%. Tone "none" (no limits, e.g. a prepaid-only agent) draws no ring.
// Display only: it takes no pointer input, so the button under it keeps
// every click.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: ring

  // The arc's fill, 0..1 (clamped); -1 for none.
  property real fraction: -1
  // "none", "accent", "attention" or "urgent" (AgentsLogic.ringTone).
  property string tone: "none"
  // The arc's stroke width.
  property real thickness: Math.max(1, Style.space(2))
  // The lit arc's colour for the tone.
  readonly property color ringColor: ring.tone === "urgent" ? Aranea.DesignTokens.urgent : (ring.tone === "attention" ? Aranea.DesignTokens.attention : Aranea.DesignTokens.accent)
  // The unlit track's colour.
  readonly property color trackColor: Util.alpha(Aranea.DesignTokens.foreground, 0.15)
  // The lit fraction actually drawn, clamped to 0..1.
  readonly property real drawn: isFinite(ring.fraction) ? Math.max(0, Math.min(1, ring.fraction)) : 0

  objectName: "agentsRing"
  implicitWidth: Style.space(22)
  implicitHeight: Style.space(22)
  visible: ring.tone !== "none" && isFinite(ring.fraction) && ring.fraction >= 0
  onDrawnChanged: canvas.requestPaint()
  onRingColorChanged: canvas.requestPaint()
  onTrackColorChanged: canvas.requestPaint()
  onThicknessChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    objectName: "ringCanvas"
    anchors.fill: parent
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onPaint: {
      var ctx = canvas.getContext("2d")
      ctx.reset()
      var radius = Math.min(canvas.width, canvas.height) / 2 - ring.thickness / 2
      if (radius <= 0)
        return
      var cx = canvas.width / 2
      var cy = canvas.height / 2
      var start = -Math.PI / 2
      ctx.lineWidth = ring.thickness
      ctx.lineCap = "butt"
      ctx.strokeStyle = ring.trackColor
      ctx.beginPath()
      ctx.arc(cx, cy, radius, 0, Math.PI * 2, false)
      ctx.stroke()
      if (ring.drawn > 0) {
        ctx.strokeStyle = ring.ringColor
        ctx.beginPath()
        ctx.arc(cx, cy, radius, start, start + Math.PI * 2 * ring.drawn, false)
        ctx.stroke()
      }
    }
  }
}
