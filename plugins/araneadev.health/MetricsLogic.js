// Pure maths for the health dropdown's metrics: parse /proc and ps output,
// turn two samples into rates. No QML, no I/O; tests/metrics.test.sh.

/**
 * Aggregate CPU jiffies from the first line of /proc/stat.
 * @typedef {object} CpuSample
 * @property {number} busy - all jiffies except idle and iowait
 * @property {number} total - sum of the first eight counters
 */

/**
 * Memory figures in bytes from /proc/meminfo.
 * @typedef {object} MemInfo
 * @property {number} memTotal - MemTotal
 * @property {number} memUsed - MemTotal minus MemAvailable
 * @property {number} swapTotal - SwapTotal (0 when absent)
 * @property {number} swapUsed - SwapTotal minus SwapFree, at least 0
 */

/**
 * Byte counters of one interface from /proc/net/dev.
 * @typedef {object} NetCounters
 * @property {number} rx - bytes received
 * @property {number} tx - bytes transmitted
 */

/**
 * One process from /proc/<pid>/stat.
 * @typedef {object} ProcSample
 * @property {number} pid - process id
 * @property {string} comm - command name
 * @property {number} ticks - utime plus stime, in clock ticks
 * @property {number} rss - resident memory in bytes
 */

/**
 * Converts a value to a finite number.
 * @param {*} v - value to convert
 * @returns {number} the number, or NaN when not finite
 */
function num(v) {
  var n = Number(v)
  return isFinite(n) ? n : NaN
}

/**
 * Reads the aggregate "cpu" line of /proc/stat.
 * @param {string} text - /proc/stat contents
 * @returns {?CpuSample} busy and total jiffies, or null if the line is missing or malformed
 */
function parseCpuStat(text) {
  var line = String(text || "").split("\n")[0]
  var f = line.trim().split(/\s+/)
  if (f[0] !== "cpu" || f.length < 8) return null
  var v = f.slice(1, 9).map(num)
  if (
    v.some(function (x) {
      return isNaN(x)
    })
  )
    return null
  var idle = v[3] + v[4]
  var total = v.reduce(function (s, x) {
    return s + x
  }, 0)
  return { busy: total - idle, total: total }
}

/**
 * Computes CPU use between two samples.
 * @param {?CpuSample} prev - earlier sample
 * @param {?CpuSample} next - later sample
 * @returns {?number} whole percent 0-100, 0 when the counters did not advance, null without both samples
 */
function cpuPercent(prev, next) {
  if (!prev || !next) return null
  var dt = next.total - prev.total
  var db = next.busy - prev.busy
  if (dt <= 0 || db < 0) return 0
  return Math.round(Math.min(100, (db * 100) / dt))
}

/**
 * Appends a value to a history list, keeping only the newest entries.
 * @param {?Array<number>} list - current history (not modified)
 * @param {number} value - value to append
 * @param {number} [max] - list length cap, 60 when omitted or 0
 * @returns {Array<number>} the new list
 */
function pushHistory(list, value, max) {
  var next = (list || []).concat([value])
  var cap = max || 60
  return next.length > cap ? next.slice(next.length - cap) : next
}

/**
 * Reads the 1, 5 and 15 minute load averages.
 * @param {string} text - /proc/loadavg contents
 * @returns {?Array<number>} the three averages, or null if malformed
 */
function parseLoadavg(text) {
  var f = String(text || "")
    .trim()
    .split(/\s+/)
  if (f.length < 3) return null
  var v = f.slice(0, 3).map(num)
  return v.some(function (x) {
    return isNaN(x)
  })
    ? null
    : v
}

/**
 * Reads memory and swap totals and usage.
 * @param {string} text - /proc/meminfo contents (values in kB)
 * @returns {?MemInfo} the figures in bytes, or null without MemTotal/MemAvailable
 */
function parseMeminfo(text) {
  /** @type {{[key: string]: number}} */
  var fields = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^(\w+):\s+(\d+)/.exec(lines[i])
    if (m) fields[m[1]] = Number(m[2]) * 1024
  }
  if (!fields.MemTotal || fields.MemAvailable === undefined) return null
  var swapTotal = fields.SwapTotal || 0
  return {
    memTotal: fields.MemTotal,
    memUsed: fields.MemTotal - fields.MemAvailable,
    swapTotal: swapTotal,
    swapUsed: Math.max(0, swapTotal - (fields.SwapFree || 0))
  }
}

/**
 * Finds the interface of the default IPv4 route.
 * @param {string} routeText - /proc/net/route contents
 * @returns {string} the interface name, "" when there is no default route
 */
function defaultInterface(routeText) {
  var lines = String(routeText || "").split("\n")
  for (var i = 1; i < lines.length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length > 1 && f[1] === "00000000") return f[0]
  }
  return ""
}

/**
 * Reads the byte counters of one interface.
 * @param {string} text - /proc/net/dev contents
 * @param {string} iface - interface name
 * @returns {?NetCounters} received and transmitted bytes, or null if the interface is missing or malformed
 */
function parseNetDev(text, iface) {
  if (!iface) return null
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf(":")
    if (idx < 0 || lines[i].slice(0, idx).trim() !== iface) continue
    var f = lines[i]
      .slice(idx + 1)
      .trim()
      .split(/\s+/)
      .map(num)
    if (f.length < 9 || isNaN(f[0]) || isNaN(f[8])) return null
    return { rx: f[0], tx: f[8] }
  }
  return null
}

/**
 * Computes network throughput between two counter samples.
 * @param {?NetCounters} prev - earlier counters
 * @param {?NetCounters} next - later counters
 * @param {number} elapsedMs - time between the samples in ms
 * @returns {{up: number, down: number}} bytes per second, never negative; zeros without both samples
 */
function netRates(prev, next, elapsedMs) {
  if (!prev || !next || !(elapsedMs > 0)) return { up: 0, down: 0 }
  var s = elapsedMs / 1000
  return {
    down: Math.max(0, Math.round((next.rx - prev.rx) / s)),
    up: Math.max(0, Math.round((next.tx - prev.tx) / s))
  }
}

// A dump of /proc/<pid>/stat lines. comm sits in parentheses and may itself
// contain spaces or ')', so split on the last ')'. After it: state (field 3)
// ... utime (14), stime (15), rss in pages (24).
/**
 * Parses a dump of /proc/<pid>/stat lines, skipping malformed ones.
 * @param {string} text - the concatenated stat lines
 * @param {number} [pageSize] - page size in bytes, 4096 when omitted
 * @returns {Array<ProcSample>} one entry per parsed process
 */
function parseProcStat(text, pageSize) {
  var page = pageSize || 4096
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var open = line.indexOf(" (")
    var close = line.lastIndexOf(")")
    if (open < 0 || close < open) continue
    var rest = line.slice(close + 2).split(" ")
    if (rest.length < 22) continue
    out.push({
      pid: Number(line.slice(0, open)),
      comm: line.slice(open + 2, close),
      ticks: Number(rest[11]) + Number(rest[12]),
      rss: Number(rest[21]) * page
    })
  }
  return out
}

// CPU % = tick delta over wall time (100 % = one core); only processes
// present in both samples, and busy ones, get a CPU row.
/**
 * Picks the top processes by CPU (between two dumps) and by resident memory.
 * @param {?Array<ProcSample>} prev - earlier dump
 * @param {?Array<ProcSample>} next - later dump
 * @param {number} elapsedMs - time between the dumps in ms
 * @param {number} [count] - entries per list, 3 when omitted
 * @param {number} [ticksPerSecond] - clock ticks per second, 100 when omitted
 * @returns {{cpu: Array<{comm: string, percent: number}>, mem: Array<{comm: string, rss: number}>}} the top entries of each list
 */
function topProcesses(prev, next, elapsedMs, count, ticksPerSecond) {
  var n = count || 3
  var hz = ticksPerSecond || 100
  /** @type {{[key: number]: ProcSample}} */
  var before = {}
  for (var i = 0; i < (prev || []).length; i++) before[prev[i].pid] = prev[i]
  var cpu = []
  var s = elapsedMs / 1000
  for (var j = 0; j < (next || []).length; j++) {
    var p = next[j]
    var old = before[p.pid]
    if (!old || !(s > 0)) continue
    var percent = Math.round(((p.ticks - old.ticks) * 100) / hz / s)
    if (percent > 0) cpu.push({ comm: p.comm, percent: percent })
  }
  cpu.sort(function (a, b) {
    return b.percent - a.percent
  })
  var mem = (next || []).map(function (p) {
    return { comm: p.comm, rss: p.rss }
  })
  mem.sort(function (a, b) {
    return b.rss - a.rss
  })
  return { cpu: cpu.slice(0, n), mem: mem.slice(0, n) }
}

/**
 * Formats an uptime as "up 2d 3h", "up 3h 12m" or "up 12m".
 * @param {number} seconds - uptime in seconds
 * @returns {string} the formatted uptime
 */
function formatUptime(seconds) {
  var t = Math.max(0, Math.floor(Number(seconds) || 0))
  var d = Math.floor(t / 86400),
    h = Math.floor((t % 86400) / 3600),
    m = Math.floor((t % 3600) / 60)
  if (d > 0) return "up " + d + "d " + h + "h"
  if (h > 0) return "up " + h + "h " + m + "m"
  return "up " + m + "m"
}

/**
 * Maps a usage percentage to a display level.
 * @param {number} percent - usage percentage
 * @returns {string} "critical" from 97, "attention" from 90, else "normal"
 */
function usageLevel(percent) {
  var p = Number(percent)
  if (p >= 97) return "critical"
  if (p >= 90) return "attention"
  return "normal"
}

/**
 * Formats a byte count with 1024-based units ("1.5 GB", "12 MB").
 * @param {number} n - bytes; negative or non-numeric counts as 0
 * @returns {string} the formatted size
 */
function humanBytes(n) {
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var v = Math.max(0, Number(n) || 0)
  var i = 0
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i++
  }
  var text = v >= 10 || i === 0 ? String(Math.round(v)) : v.toFixed(1).replace(/\.0$/, "")
  return text + " " + units[i]
}

/**
 * Formats a throughput as a size per second.
 * @param {number} bytesPerSec - bytes per second
 * @returns {string} e.g. "1.2 MB/s"
 */
function formatRate(bytesPerSec) {
  return humanBytes(bytesPerSec) + "/s"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseCpuStat: parseCpuStat,
    cpuPercent: cpuPercent,
    pushHistory: pushHistory,
    parseLoadavg: parseLoadavg,
    parseMeminfo: parseMeminfo,
    defaultInterface: defaultInterface,
    parseNetDev: parseNetDev,
    netRates: netRates,
    parseProcStat: parseProcStat,
    topProcesses: topProcesses,
    formatUptime: formatUptime,
    usageLevel: usageLevel,
    humanBytes: humanBytes,
    formatRate: formatRate
  }
}
