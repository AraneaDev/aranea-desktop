// Shared rolling-sample and plot-point math for a link's throughput graph,
// moved out of the Network plugin so araneadev.vpn can reuse it with
// `Aranea.LinkGraph`. No QML, no I/O; tests/js/graph-logic.test.js runs
// this under Node.

/**
 * Appends a throughput sample to the rolling history kept for the graph,
 * resetting it when the sampled interface changes.
 * @param {Array<{iface: string, rx: number, tx: number}>|undefined} history - the samples kept so far
 * @param {{iface: string, rx: number, tx: number}} sample - the new sample
 * @param {number} max - the most samples to keep
 * @returns {Array<{iface: string, rx: number, tx: number}>} a new array; `history` is never mutated
 */
function pushSample(history, sample, max) {
  var hist = Array.isArray(history) ? history : []
  var s = sample
  var last = hist[hist.length - 1]
  if (!last || last.iface !== s.iface) return [s]
  var next = hist.concat([s])
  var limit = Math.max(1, Number(max) || 1)
  if (next.length > limit) next = next.slice(next.length - limit)
  return next
}

/**
 * Turns throughput samples into plot points for the rx/tx graph. A null or
 * non-object entry in `samples` is read as rx/tx 0 rather than thrown on.
 * @param {Array<{iface: string, rx: number, tx: number}>|undefined} samples - the rolling history, oldest first
 * @param {number} slots - the graph's time slots (at least 2)
 * @param {number} width - the plot width, in pixels
 * @param {number} height - the plot height, in pixels
 * @param {number} floor - the minimum scale, so a near-idle graph doesn't look noisy
 * @returns {{rx: Array<{x: number, y: number}>, tx: Array<{x: number, y: number}>, scale: number}} the points and the scale used
 */
function graphPoints(samples, slots, width, height, floor) {
  var list = Array.isArray(samples) ? samples : []
  var f = Number(floor) || 0
  if (list.length === 0) return { rx: [], tx: [], scale: f }

  var scale = f
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    var rxValue = item ? Math.max(0, Number(item.rx) || 0) : 0
    var txValue = item ? Math.max(0, Number(item.tx) || 0) : 0
    if (rxValue > scale) scale = rxValue
    if (txValue > scale) scale = txValue
  }

  var n = list.length
  var w = Number(width) || 0
  var h = Number(height) || 0
  var effectiveSlots = Number(slots) < 2 ? 2 : Number(slots)
  var step = w / (effectiveSlots - 1)

  var rx = []
  var tx = []
  for (var j = 0; j < n; j++) {
    var x = w - (n - 1 - j) * step
    var entry = list[j]
    var rxV = entry ? Math.max(0, Number(entry.rx) || 0) : 0
    var txV = entry ? Math.max(0, Number(entry.tx) || 0) : 0
    rx.push({ x: x, y: h - (rxV / scale) * h })
    tx.push({ x: x, y: h - (txV / scale) * h })
  }

  return { rx: rx, tx: tx, scale: scale }
}

if (typeof module !== "undefined")
  module.exports = {
    pushSample: pushSample,
    graphPoints: graphPoints
  }
