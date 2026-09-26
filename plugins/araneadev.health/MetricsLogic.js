// Pure maths for the health dropdown's metrics: parse /proc and ps output,
// turn two samples into rates. No QML, no I/O; tests/metrics.test.sh.

function num(v) {
  var n = Number(v)
  return isFinite(n) ? n : NaN
}

function parseCpuStat(text) {
  var line = String(text || "").split("\n")[0]
  var f = line.trim().split(/\s+/)
  if (f[0] !== "cpu" || f.length < 8) return null
  var v = f.slice(1, 9).map(num)
  if (v.some(function(x) { return isNaN(x) })) return null
  var idle = v[3] + v[4]
  var total = v.reduce(function(s, x) { return s + x }, 0)
  return { busy: total - idle, total: total }
}

function cpuPercent(prev, next) {
  if (!prev || !next) return null
  var dt = next.total - prev.total
  var db = next.busy - prev.busy
  if (dt <= 0 || db < 0) return 0
  return Math.round(Math.min(100, db * 100 / dt))
}

function pushHistory(list, value, max) {
  var next = (list || []).concat([value])
  var cap = max || 60
  return next.length > cap ? next.slice(next.length - cap) : next
}

function parseLoadavg(text) {
  var f = String(text || "").trim().split(/\s+/)
  if (f.length < 3) return null
  var v = f.slice(0, 3).map(num)
  return v.some(function(x) { return isNaN(x) }) ? null : v
}

function parseMeminfo(text) {
  var fields = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^(\w+):\s+(\d+)/.exec(lines[i])
    if (m) fields[m[1]] = Number(m[2]) * 1024
  }
  if (!fields.MemTotal || fields.MemAvailable === undefined) return null
  var swapTotal = fields.SwapTotal || 0
  return {
    memTotal: fields.MemTotal, memUsed: fields.MemTotal - fields.MemAvailable,
    swapTotal: swapTotal, swapUsed: Math.max(0, swapTotal - (fields.SwapFree || 0))
  }
}

function defaultInterface(routeText) {
  var lines = String(routeText || "").split("\n")
  for (var i = 1; i < lines.length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length > 1 && f[1] === "00000000") return f[0]
  }
  return ""
}

function parseNetDev(text, iface) {
  if (!iface) return null
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf(":")
    if (idx < 0 || lines[i].slice(0, idx).trim() !== iface) continue
    var f = lines[i].slice(idx + 1).trim().split(/\s+/).map(num)
    if (f.length < 9 || isNaN(f[0]) || isNaN(f[8])) return null
    return { rx: f[0], tx: f[8] }
  }
  return null
}

function netRates(prev, next, elapsedMs) {
  if (!prev || !next || !(elapsedMs > 0)) return { up: 0, down: 0 }
  var s = elapsedMs / 1000
  return {
    down: Math.max(0, Math.round((next.rx - prev.rx) / s)),
    up: Math.max(0, Math.round((next.tx - prev.tx) / s))
  }
}

// `ps -eo pid=,rss=,cputimes=,comm=`: rss in KiB, cputimes in seconds.
function parsePs(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(.+?)\s*$/.exec(lines[i])
    if (!m) continue
    out.push({ pid: Number(m[1]), rss: Number(m[2]) * 1024, cpu: Number(m[3]), comm: m[4] })
  }
  return out
}

// CPU % = cputime delta over wall time (100 % = one core); only processes
// present in both samples get a figure.
function topProcesses(prev, next, elapsedMs, count) {
  var n = count || 3
  var before = {}
  for (var i = 0; i < (prev || []).length; i++) before[prev[i].pid] = prev[i]
  var cpu = []
  var s = elapsedMs / 1000
  for (var j = 0; j < (next || []).length; j++) {
    var p = next[j]
    var old = before[p.pid]
    if (!old || !(s > 0)) continue
    cpu.push({ comm: p.comm, percent: Math.max(0, Math.round((p.cpu - old.cpu) * 100 / s)) })
  }
  cpu.sort(function(a, b) { return b.percent - a.percent })
  var mem = (next || []).map(function(p) { return { comm: p.comm, rss: p.rss } })
  mem.sort(function(a, b) { return b.rss - a.rss })
  return { cpu: cpu.slice(0, n), mem: mem.slice(0, n) }
}

function formatUptime(seconds) {
  var t = Math.max(0, Math.floor(Number(seconds) || 0))
  var d = Math.floor(t / 86400), h = Math.floor((t % 86400) / 3600), m = Math.floor((t % 3600) / 60)
  if (d > 0) return "up " + d + "d " + h + "h"
  if (h > 0) return "up " + h + "h " + m + "m"
  return "up " + m + "m"
}

function usageLevel(percent) {
  var p = Number(percent)
  if (p >= 97) return "critical"
  if (p >= 90) return "attention"
  return "normal"
}

function humanBytes(n) {
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var v = Math.max(0, Number(n) || 0)
  var i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  var text = v >= 10 || i === 0 ? String(Math.round(v)) : v.toFixed(1).replace(/\.0$/, "")
  return text + " " + units[i]
}

function formatRate(bytesPerSec) {
  return humanBytes(bytesPerSec) + "/s"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseCpuStat: parseCpuStat, cpuPercent: cpuPercent, pushHistory: pushHistory,
    parseLoadavg: parseLoadavg, parseMeminfo: parseMeminfo, defaultInterface: defaultInterface,
    parseNetDev: parseNetDev, netRates: netRates, parsePs: parsePs, topProcesses: topProcesses,
    formatUptime: formatUptime, usageLevel: usageLevel, humanBytes: humanBytes, formatRate: formatRate
  }
}
