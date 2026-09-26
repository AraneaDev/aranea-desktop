// Pure rules for the System health monitor (Health.qml): parse command
// output, derive open problems, word them, and reconcile them with the inbox.
// No QML, no I/O; tests/health.test.sh runs this under Node.

var DISK_ALERT = 90
var DISK_CRITICAL = 97
var DISK_CLEAR = 88
var LOOP_EXITS = 3
var LOOP_WINDOW_MS = 5 * 60 * 1000

var GLYPH_UNIT = "󰒓"
var GLYPH_DISK = "󰋊"
var GLYPH_REBOOT = "󰜉"
var GLYPH_CONTAINER = "󰡨"

function checkOf(key) {
  return String(key || "").split(":")[0]
}

function parseFailedUnits(text, scope) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed)) return null
  var out = []
  for (var i = 0; i < parsed.length; i++) {
    var unit = parsed[i] && parsed[i].unit
    if (!unit) continue
    out.push({ key: "unit:" + scope + ":" + unit, check: "unit", unit: String(unit), scope: scope })
  }
  return out
}

// `df --output=source,target,fstype,size,used,avail,pcent -B1`, header first.
// Subvolumes and bind mounts share a source: keep the shortest mount point.
function parseDf(text) {
  var lines = String(text || "").split("\n").filter(function(l) { return l.trim() })
  if (lines.length < 2) return null
  var bySource = {}
  var order = []
  for (var i = 1; i < lines.length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length < 7) continue
    var row = {
      source: f[0], target: f[1], size: Number(f[3]), used: Number(f[4]),
      avail: Number(f[5]), percent: parseInt(f[6], 10)
    }
    if (!isFinite(row.size) || !isFinite(row.percent)) continue
    if (!alertableFsType(f[2])) continue
    var seen = bySource[row.source]
    if (!seen) { bySource[row.source] = row; order.push(row.source) }
    else if (row.target.length < seen.target.length) bySource[row.source] = row
  }
  if (order.length === 0) return null
  return order.map(function(s) { return bySource[s] })
}

// Read-only images (ISO/UDF) and FUSE app mounts (AppImages) are always
// "100% full" by design. fuseblk (NTFS/exFAT disks) is real storage.
function alertableFsType(fstype) {
  var t = String(fstype || "")
  if (t === "iso9660" || t === "udf") return false
  if (t.indexOf("fuse.") === 0) return false
  return true
}

function diskLevel(previous, percent) {
  var p = Number(percent)
  if (p >= DISK_CRITICAL) return "critical"
  if (p >= DISK_ALERT) return "normal"
  if (previous !== "ok" && previous !== undefined && p >= DISK_CLEAR) return "normal"
  return "ok"
}

function diskProblems(rows, levels) {
  var previous = levels || {}
  var next = {}
  var problems = []
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    var level = diskLevel(previous[r.target] || "ok", r.percent)
    next[r.target] = level
    if (level === "ok") continue
    problems.push({ key: "disk:" + r.target, check: "disk", target: r.target, percent: r.percent,
      size: r.size, avail: r.avail, level: level })
  }
  return { problems: problems, levels: next }
}

function rebootProblem(modulesPresent, release) {
  return modulesPresent ? [] : [{ key: "reboot", check: "reboot", release: String(release || "") }]
}

function parseDockerEvent(line) {
  var e
  try {
    e = JSON.parse(String(line || ""))
  } catch (err) {
    return null
  }
  var attrs = e && e.Actor && e.Actor.Attributes
  if (!attrs || !attrs.name) return null
  var action = String(e.Action || e.status || "")
  if (action !== "die" && action !== "start" && action !== "destroy") return null
  return {
    action: action, name: String(attrs.name), image: String(attrs.image || ""),
    exitCode: parseInt(attrs.exitCode || "0", 10) || 0,
    time: (Number(e.time) || 0) * 1000
  }
}

// history: name -> { image, exits: [ms], last: "die"|"start", lastExit: int }
function recordDockerEvent(history, event, now) {
  var next = {}
  for (var k in (history || {})) next[k] = history[k]
  if (!event) return next
  if (event.action === "destroy") {
    delete next[event.name]
    return next
  }
  var prev = next[event.name] || { image: event.image, exits: [], last: "start", lastExit: 0 }
  var exits = prev.exits.filter(function(t) { return now - t <= LOOP_WINDOW_MS })
  if (event.action === "die" && event.exitCode !== 0) exits.push(now)
  next[event.name] = {
    image: event.image || prev.image, exits: exits, last: event.action,
    lastExit: event.action === "die" ? event.exitCode : prev.lastExit
  }
  return next
}

// `docker ps -a --format '{{json .}}'`, one object per line.
function parseDockerPs(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].trim()) continue
    var c
    try {
      c = JSON.parse(lines[i])
    } catch (e) {
      return null
    }
    var code = /Exited \((-?\d+)\)/.exec(String(c.Status || ""))
    out.push({ name: String(c.Names || ""), image: String(c.Image || ""),
      running: String(c.State || "") === "running", exitCode: code ? parseInt(code[1], 10) : 0 })
  }
  return out
}

// Rebuild container state from a `docker ps -a` snapshot, taken when the
// events stream (re)connects: after a shell restart or a stream gap the
// snapshot is the truth. Exit timestamps already counted are kept so a
// restart loop spanning the gap is still recognised.
function seedDockerHistory(history, containers, now) {
  var next = {}
  for (var i = 0; i < (containers || []).length; i++) {
    var c = containers[i]
    if (!c.name) continue
    var prev = (history || {})[c.name]
    var exits = prev ? prev.exits.filter(function(t) { return now - t <= LOOP_WINDOW_MS }) : []
    next[c.name] = { image: c.image || (prev && prev.image) || "", exits: exits,
      last: c.running ? "start" : "die", lastExit: c.running ? 0 : c.exitCode }
  }
  return next
}

function containerProblems(history, now) {
  var out = []
  for (var name in (history || {})) {
    var h = history[name]
    var exits = h.exits.filter(function(t) { return now - t <= LOOP_WINDOW_MS }).length
    var loop = exits >= LOOP_EXITS
    if (!loop && !(h.last === "die" && h.lastExit !== 0)) continue
    out.push({ key: "container:" + name, check: "container", name: name, image: h.image,
      exitCode: h.lastExit, exits: exits, loop: loop })
  }
  return out
}

function humanBytes(n) {
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var v = Math.max(0, Number(n) || 0)
  var i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  var text = v >= 10 || i === 0 ? String(Math.round(v)) : v.toFixed(1).replace(/\.0$/, "")
  return text + " " + units[i]
}

function itemFor(p) {
  if (p.check === "unit") {
    var journal = ["xdg-terminal-exec", "journalctl"]
    if (p.scope === "user") journal.push("--user")
    return { summary: p.unit + " failed", body: p.scope === "user" ? "User service" : "System service",
      urgency: 2, glyph: GLYPH_UNIT, execArgv: journal.concat(["-u", p.unit, "-e"]) }
  }
  if (p.check === "disk") {
    return { summary: p.target + " is " + p.percent + "% full",
      body: humanBytes(p.avail) + " free of " + humanBytes(p.size),
      urgency: p.level === "critical" ? 2 : 1, glyph: GLYPH_DISK, execArgv: ["xdg-open", p.target] }
  }
  if (p.check === "reboot") {
    return { summary: "Reboot to finish the kernel update",
      body: "Running " + p.release + "; its modules were removed",
      urgency: 1, glyph: GLYPH_REBOOT, execArgv: ["omarchy-menu", "toggle", "system"] }
  }
  var logs = ["xdg-terminal-exec", "docker", "logs", "--tail", "200", "-f", p.name]
  if (p.loop) {
    return { summary: "Container " + p.name + " keeps restarting", body: p.exits + " exits in 5 minutes",
      urgency: 2, glyph: GLYPH_CONTAINER, execArgv: logs }
  }
  return { summary: "Container " + p.name + " exited (code " + p.exitCode + ")", body: "Image " + p.image,
    urgency: 1, glyph: GLYPH_CONTAINER, execArgv: logs }
}

function toSet(list) {
  var s = {}
  for (var i = 0; i < (list || []).length; i++) s[list[i]] = true
  return s
}

// open: problems from checks whose last result is known (the caller keeps the
// last known problems of a check that is currently unknown).
// knownChecks: checks that have completed at least once and whose last result
// was readable; only their items may be resolved and their mutes lifted.
function reconcile(open, knownChecks, previousExpected, presentKeys, muted) {
  var known = toSet(knownChecks)
  var present = toSet(presentKeys)
  var openByKey = {}
  for (var i = 0; i < (open || []).length; i++) openByKey[open[i].key] = open[i]

  var mutedSet = {}
  for (var m = 0; m < (muted || []).length; m++) {
    var key = muted[m]
    // A mute lasts while its problem is open (or its check cannot tell).
    if (openByKey[key] || !known[checkOf(key)]) mutedSet[key] = true
  }
  for (var e = 0; e < (previousExpected || []).length; e++) {
    var exp = previousExpected[e]
    if (!present[exp] && openByKey[exp]) mutedSet[exp] = true
  }

  var upsert = []
  var expected = []
  for (var k in openByKey) {
    if (mutedSet[k]) continue
    upsert.push(openByKey[k])
    expected.push(k)
  }
  var resolve = []
  for (var p in present) {
    if (!known[checkOf(p)]) {
      if (!mutedSet[p]) expected.push(p)
      continue
    }
    if (!openByKey[p] || mutedSet[p]) resolve.push(p)
  }
  return { upsert: upsert, resolve: resolve, muted: Object.keys(mutedSet).sort(), expected: expected }
}

function parseMuteFile(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    return parsed && Array.isArray(parsed.muted) ? parsed.muted.filter(function(k) { return typeof k === "string" }) : []
  } catch (e) {
    return []
  }
}

function serializeMuteFile(muted) {
  return JSON.stringify({ version: 1, muted: (muted || []).slice().sort() }, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    checkOf: checkOf,
    parseFailedUnits: parseFailedUnits,
    parseDf: parseDf,
    diskLevel: diskLevel,
    diskProblems: diskProblems,
    rebootProblem: rebootProblem,
    parseDockerEvent: parseDockerEvent,
    recordDockerEvent: recordDockerEvent,
    containerProblems: containerProblems,
    parseDockerPs: parseDockerPs,
    seedDockerHistory: seedDockerHistory,
    humanBytes: humanBytes,
    itemFor: itemFor,
    reconcile: reconcile,
    parseMuteFile: parseMuteFile,
    serializeMuteFile: serializeMuteFile
  }
}
