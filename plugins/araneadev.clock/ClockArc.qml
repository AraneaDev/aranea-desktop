// The Aranea Clock dropdown's sun arc: a faint horizon line and the day's
// arc over it from sunrise (left) to sunset (right). By day the arc runs
// accent to strandEnd and a glowing dot sits at arcT along it; at night
// (ClockLogic.sunArcPosition's night) the arc is dim and a dim dot walks
// the horizon from sunset to the next sunrise. A polar day lights the
// whole arc and a polar night dims it, both without a dot (there is no
// sunrise to measure from). Pure view: inputs in, nothing out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Canvas {
  id: arc

  // The fraction along the day arc (or along the night, when night).
  property real arcT: 0
  // Whether the sun is down.
  property bool night: false
  // "day" or "night" for a sun that neither rises nor sets today, else "".
  property string polar: ""
  // Whether the arc reads lit (accent): by day, or all through a polar day.
  readonly property bool lit: arc.polar === "day" || (arc.polar === "" && !arc.night)
  // Where the horizon sits, in px from the top.
  readonly property real horizonY: arc.height - Style.space(4)
  // The arc's ends and control point, in px.
  readonly property real startX: arc.width * 0.09
  // The arc's right end, in px.
  readonly property real endX: arc.width * 0.91
  // The control point's y, so the arc peaks a few px under the top.
  readonly property real controlY: 2 * Style.space(6) - arc.horizonY

  // The point T (0..1) along the arc, in px.
  function arcPoint(t) {
    var u = 1 - t
    return {
      x: u * u * arc.startX + 2 * u * t * (arc.width / 2) + t * t * arc.endX,
      y: u * u * arc.horizonY + 2 * u * t * arc.controlY + t * t * arc.horizonY
    }
  }

  // The dot: {x, y, dim}, or null for a polar day or night.
  function dotPoint() {
    if (arc.polar !== "")
      return null
    var t = Math.max(0, Math.min(1, Number(arc.arcT) || 0))
    if (arc.night)
      return {
        x: arc.startX + (arc.endX - arc.startX) * t,
        y: arc.horizonY,
        dim: true
      }
    var p = arc.arcPoint(t)
    return {
      x: p.x,
      y: p.y,
      dim: false
    }
  }

  objectName: "sunArc"
  height: Style.space(40)
  onArcTChanged: requestPaint()
  onNightChanged: requestPaint()
  onPolarChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.lineCap = "round"

    ctx.globalAlpha = 0.15
    ctx.strokeStyle = String(Aranea.DesignTokens.foreground)
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(0, Math.round(arc.horizonY) + 0.5)
    ctx.lineTo(arc.width, Math.round(arc.horizonY) + 0.5)
    ctx.stroke()

    if (arc.lit) {
      ctx.globalAlpha = 1
      var gradient = ctx.createLinearGradient(0, 0, arc.width, 0)
      gradient.addColorStop(0, String(Aranea.DesignTokens.accent))
      gradient.addColorStop(1, String(Aranea.DesignTokens.strandEnd))
      ctx.strokeStyle = gradient
    } else {
      ctx.globalAlpha = 0.25
      ctx.strokeStyle = String(Aranea.DesignTokens.foreground)
    }
    ctx.lineWidth = 1.5
    ctx.beginPath()
    ctx.moveTo(arc.startX, arc.horizonY)
    ctx.quadraticCurveTo(arc.width / 2, arc.controlY, arc.endX, arc.horizonY)
    ctx.stroke()

    var dot = arc.dotPoint()
    if (!dot)
      return
    if (dot.dim) {
      ctx.globalAlpha = 0.35
      ctx.fillStyle = String(Aranea.DesignTokens.foreground)
    } else {
      ctx.globalAlpha = 1
      ctx.fillStyle = String(Aranea.DesignTokens.accent)
      ctx.shadowColor = String(Aranea.DesignTokens.accent)
      ctx.shadowBlur = 6
    }
    ctx.beginPath()
    ctx.arc(dot.x, dot.y, 3.5, 0, 2 * Math.PI)
    ctx.fill()
  }
}
