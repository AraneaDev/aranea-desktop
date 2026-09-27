// Pure rules for the System health monitor (Monitor.qml): parse command
// output, derive open problems and word them for the health dropdown.
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

/**
 * One filesystem row from `df` (parseDf).
 * @typedef {object} DfRow
 * @property {string} source - device or filesystem source
 * @property {string} target - mount point
 * @property {number} size - total size in bytes
 * @property {number} used - used bytes
 * @property {number} avail - available bytes
 * @property {number} percent - df's use percentage
 */

/**
 * A container lifecycle event from `docker events` (parseDockerEvent).
 * @typedef {object} DockerEvent
 * @property {string} action - "die", "start" or "destroy"
 * @property {string} name - container name
 * @property {string} image - image name, "" when absent
 * @property {number} exitCode - exit code (0 when absent or not a die event)
 * @property {number} time - event time in ms since the epoch
 */

/**
 * Per-container state kept between events.
 * @typedef {object} DockerHistoryEntry
 * @property {string} image - image name
 * @property {Array<number>} exits - times (ms) of non-zero exits
 * @property {string} last - last action seen: "die" or "start"
 * @property {number} lastExit - exit code of the last die (0 when running)
 * @property {boolean} [oomKilled] - the kernel killed it for memory since its last start
 */

/**
 * One container from `docker ps -a` (parseDockerPs).
 * @typedef {object} DockerContainer
 * @property {string} name - container name
 * @property {string} image - image name
 * @property {boolean} running - State is "running"
 * @property {number} exitCode - code from "Exited (n)" in Status, else 0
 */

/**
 * An open problem from one of the checks. Which optional fields are set
 * depends on `check`; annotated rows (annotateProblems) also fit this shape.
 * @typedef {object} Problem
 * @property {string} key - unique id, "<check>:..." or "reboot"
 * @property {string} check - "unit", "disk", "reboot" or "container"
 * @property {string} [unit] - unit: the failed unit's name
 * @property {string} [scope] - unit: "system" or "user"
 * @property {string} [target] - disk: mount point
 * @property {number} [percent] - disk: use percentage
 * @property {number} [size] - disk: total bytes
 * @property {number} [avail] - disk: available bytes
 * @property {string} [level] - disk: "normal" or "critical"
 * @property {string} [release] - reboot: running kernel release
 * @property {string} [name] - container: name
 * @property {string} [image] - container: image
 * @property {number} [exitCode] - container: last exit code
 * @property {number} [exits] - container: exits within the loop window
 * @property {boolean} [loop] - container: restart loop detected
 * @property {number} [urgency] - annotated rows only: 1 or 2
 */

/**
 * Which external tools the click actions may use.
 * @typedef {object} Tools
 * @property {boolean} terminal - whether xdg-terminal-exec exists
 */

/**
 * Dropdown copy and click action for one problem (itemFor).
 * @typedef {object} ProblemItem
 * @property {string} summary - headline
 * @property {string} body - detail line
 * @property {number} urgency - 1 normal, 2 critical
 * @property {string} glyph - Nerd Font icon
 * @property {Array<string>} execArgv - command run on click; empty for none
 */

/**
 * Returns the check name of a problem key ("disk:/home" gives "disk").
 * @param {string} key - problem key
 * @returns {string} the part before the first ":"
 */
function checkOf(key) {
  return String(key || "").split(":")[0]
}

/**
 * Turns `systemctl list-units --failed --output=json` output into unit problems.
 * @param {string} text - the JSON output
 * @param {string} scope - "system" or "user"
 * @returns {?Array<Problem>} one problem per failed unit, or null if the output is not a JSON array
 */
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
/**
 * Parses df output into one row per source, skipping filesystems that never alert.
 * @param {string} text - df output including its header line
 * @returns {?Array<DfRow>} rows in df order, or null when there is no usable row
 */
function parseDf(text) {
  var lines = String(text || "")
    .split("\n")
    .filter(function (l) {
      return l.trim()
    })
  if (lines.length < 2) return null
  /** @type {{[key: string]: DfRow}} */
  var bySource = {}
  var order = []
  for (var i = 1; i < lines.length; i++) {
    // Read the fixed-width tail (fstype size used avail pcent) from the end,
    // so a mount point with spaces keeps its whole name.
    var f = lines[i].trim().split(/\s+/)
    if (f.length < 7) continue
    var n = f.length
    var row = {
      source: f[0],
      target: f.slice(1, n - 5).join(" "),
      size: Number(f[n - 4]),
      used: Number(f[n - 3]),
      avail: Number(f[n - 2]),
      percent: parseInt(f[n - 1], 10)
    }
    if (!isFinite(row.size) || !isFinite(row.percent)) continue
    if (!alertableFsType(f[n - 5])) continue
    var seen = bySource[row.source]
    if (!seen) {
      bySource[row.source] = row
      order.push(row.source)
    } else if (row.target.length < seen.target.length) bySource[row.source] = row
  }
  if (order.length === 0) return null
  return order.map(function (s) {
    return bySource[s]
  })
}

// Read-only images (ISO/UDF) and FUSE app mounts (AppImages) are always
// "100% full" by design. fuseblk (NTFS/exFAT disks) is real storage.
/**
 * Tells whether a filesystem type can raise a disk-full problem.
 * @param {string} fstype - df's fstype column
 * @returns {boolean} false for iso9660, udf and fuse.* mounts
 */
function alertableFsType(fstype) {
  var t = String(fstype || "")
  if (t === "iso9660" || t === "udf") return false
  if (t.indexOf("fuse.") === 0) return false
  return true
}

/**
 * Classifies disk usage with hysteresis: once alerted, a disk stays alerted
 * until it drops below DISK_CLEAR.
 * @param {?string} previous - the mount's previous level ("ok", "normal", "critical"), undefined if unseen
 * @param {number} percent - current use percentage
 * @returns {string} "critical", "normal" (alert) or "ok"
 */
function diskLevel(previous, percent) {
  var p = Number(percent)
  if (p >= DISK_CRITICAL) return "critical"
  if (p >= DISK_ALERT) return "normal"
  if (previous !== "ok" && previous !== undefined && p >= DISK_CLEAR) return "normal"
  return "ok"
}

/**
 * Derives disk problems from df rows and the previous levels per mount point.
 * @param {Array<DfRow>} rows - parseDf output
 * @param {?{[key: string]: string}} levels - previous level per mount point
 * @returns {{problems: Array<Problem>, levels: {[key: string]: string}}} open disk problems and the new levels
 */
function diskProblems(rows, levels) {
  var previous = levels || {}
  /** @type {{[key: string]: string}} */
  var next = {}
  var problems = []
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    var level = diskLevel(previous[r.target] || "ok", r.percent)
    next[r.target] = level
    if (level === "ok") continue
    problems.push({
      key: "disk:" + r.target,
      check: "disk",
      target: r.target,
      percent: r.percent,
      size: r.size,
      avail: r.avail,
      level: level
    })
  }
  return { problems: problems, levels: next }
}

/**
 * Reports a pending reboot when the running kernel's modules are gone.
 * @param {boolean} modulesPresent - whether /usr/lib/modules/<release> exists
 * @param {string} release - running kernel release (uname -r)
 * @returns {Array<Problem>} empty, or one reboot problem
 */
function rebootProblem(modulesPresent, release) {
  return modulesPresent ? [] : [{ key: "reboot", check: "reboot", release: String(release || "") }]
}

/**
 * Parses one `docker events --format '{{json .}}'` line.
 * @param {string} line - one JSON event
 * @returns {?DockerEvent} the event, or null for bad JSON, a missing name or another action
 */
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
  if (action !== "die" && action !== "start" && action !== "destroy" && action !== "oom")
    return null
  return {
    action: action,
    name: String(attrs.name),
    image: String(attrs.image || ""),
    exitCode: parseInt(attrs.exitCode || "0", 10) || 0,
    time: (Number(e.time) || 0) * 1000
  }
}

/**
 * Whether a container's last exit is a failure: nonzero, except 137
 * (SIGKILL) and 143 (SIGTERM), which `docker stop` produces, unless the
 * kernel killed it for memory (oomKilled).
 * @param {{lastExit: number, oomKilled?: boolean}} entry - the container's history entry
 * @returns {boolean} true when the exit should be reported
 */
function isFailedExit(entry) {
  var code = Number(entry && entry.lastExit) || 0
  if (code === 0) return false
  if ((code === 137 || code === 143) && !(entry && entry.oomKilled)) return false
  return true
}

// history: name -> { image, exits: [ms], last: "die"|"start", lastExit: int, oomKilled }
/**
 * Applies one docker event to a copy of the history: destroy forgets the
 * container, oom marks it killed for memory (until its next start), a failed
 * die (see isFailedExit) records an exit, exits older than the loop window drop.
 * @param {?{[key: string]: DockerHistoryEntry}} history - current history by container name
 * @param {?DockerEvent} event - the event; null returns an unchanged copy
 * @param {number} now - current time in ms
 * @returns {{[key: string]: DockerHistoryEntry}} the new history
 */
function recordDockerEvent(history, event, now) {
  /** @type {{[key: string]: DockerHistoryEntry}} */
  var next = {}
  for (var k in history || {}) next[k] = history[k]
  if (!event) return next
  if (event.action === "destroy") {
    delete next[event.name]
    return next
  }
  var prev = next[event.name] || {
    image: event.image,
    exits: [],
    last: "start",
    lastExit: 0,
    oomKilled: false
  }
  if (event.action === "oom") {
    // The die event that follows reports the kill (usually 137); remember
    // why, so it is not taken for a `docker stop`.
    next[event.name] = {
      image: prev.image,
      exits: prev.exits,
      last: prev.last,
      lastExit: prev.lastExit,
      oomKilled: true
    }
    return next
  }
  var oomKilled = event.action === "start" ? false : !!prev.oomKilled
  var exits = prev.exits.filter(function (t) {
    return now - t <= LOOP_WINDOW_MS
  })
  if (event.action === "die" && isFailedExit({ lastExit: event.exitCode, oomKilled: oomKilled }))
    exits.push(now)
  next[event.name] = {
    image: event.image || prev.image,
    exits: exits,
    last: event.action,
    lastExit: event.action === "die" ? event.exitCode : prev.lastExit,
    oomKilled: oomKilled
  }
  return next
}

// `docker ps -a --format '{{json .}}'`, one object per line.
/**
 * Parses `docker ps -a` JSON lines into container snapshots.
 * @param {string} text - the command output
 * @returns {?Array<DockerContainer>} the containers, or null if any line is not JSON
 */
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
    out.push({
      name: String(c.Names || ""),
      image: String(c.Image || ""),
      running: String(c.State || "") === "running",
      exitCode: code ? parseInt(code[1], 10) : 0
    })
  }
  return out
}

// Rebuild container state from a `docker ps -a` snapshot, taken when the
// events stream (re)connects: after a shell restart or a stream gap the
// snapshot is the truth. Exit timestamps already counted are kept so a
// restart loop spanning the gap is still recognised.
/**
 * Builds a fresh history from a container snapshot, keeping recent exits.
 * @param {?{[key: string]: DockerHistoryEntry}} history - previous history by container name
 * @param {?Array<DockerContainer>} containers - parseDockerPs output
 * @param {number} now - current time in ms
 * @returns {{[key: string]: DockerHistoryEntry}} one entry per named container
 */
function seedDockerHistory(history, containers, now) {
  /** @type {{[key: string]: DockerHistoryEntry}} */
  var next = {}
  for (var i = 0; i < (containers || []).length; i++) {
    var c = containers[i]
    if (!c.name) continue
    var prev = (history || {})[c.name]
    var exits = prev
      ? prev.exits.filter(function (t) {
          return now - t <= LOOP_WINDOW_MS
        })
      : []
    next[c.name] = {
      image: c.image || (prev && prev.image) || "",
      exits: exits,
      last: c.running ? "start" : "die",
      lastExit: c.running ? 0 : c.exitCode,
      oomKilled: prev ? !!prev.oomKilled && !c.running : false
    }
  }
  return next
}

// Forget containers that are neither a problem nor counting recent exits;
// their next event starts a fresh entry.
/**
 * Drops history entries with no exits in the loop window and no failed last exit.
 * @param {?{[key: string]: DockerHistoryEntry}} history - history by container name
 * @param {number} now - current time in ms
 * @returns {{[key: string]: DockerHistoryEntry}} the entries still worth keeping
 */
function pruneDockerHistory(history, now) {
  /** @type {{[key: string]: DockerHistoryEntry}} */
  var next = {}
  for (var name in history || {}) {
    var h = history[name]
    var recent = h.exits.filter(function (t) {
      return now - t <= LOOP_WINDOW_MS
    }).length
    if (recent > 0 || (h.last === "die" && isFailedExit(h))) next[name] = h
  }
  return next
}

/**
 * Lists container problems: a restart loop (LOOP_EXITS exits within the
 * window) or a last exit with a non-zero code.
 * @param {?{[key: string]: DockerHistoryEntry}} history - history by container name
 * @param {number} now - current time in ms
 * @returns {Array<Problem>} container problems
 */
function containerProblems(history, now) {
  var out = []
  for (var name in history || {}) {
    var h = history[name]
    var exits = h.exits.filter(function (t) {
      return now - t <= LOOP_WINDOW_MS
    }).length
    var loop = exits >= LOOP_EXITS
    if (!loop && !(h.last === "die" && isFailedExit(h))) continue
    out.push({
      key: "container:" + name,
      check: "container",
      name: name,
      image: h.image,
      exitCode: h.lastExit,
      exits: exits,
      loop: loop
    })
  }
  return out
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

// tools.terminal: whether xdg-terminal-exec exists (default true). Without it
// the journal/log actions are left out; clicking then just focuses/dismisses.
/**
 * Words a problem for the dropdown and picks its click command.
 * @param {Problem} p - a problem from one of the checks (unit, disk, reboot, container)
 * @param {Tools} [tools] - available tools; `terminal: false` drops the terminal commands
 * @returns {ProblemItem} the problem's copy, urgency, glyph and command
 */
function itemFor(p, tools) {
  var terminal = !tools || tools.terminal !== false
  if (p.check === "unit") {
    var journal = ["xdg-terminal-exec", "journalctl"]
    if (p.scope === "user") journal.push("--user")
    return {
      summary: p.unit + " failed",
      body: p.scope === "user" ? "User service" : "System service",
      urgency: 2,
      glyph: GLYPH_UNIT,
      execArgv: terminal ? journal.concat(["-u", p.unit, "-e"]) : []
    }
  }
  if (p.check === "disk") {
    return {
      summary: p.target + " is " + p.percent + "% full",
      body: humanBytes(p.avail) + " free of " + humanBytes(p.size),
      urgency: p.level === "critical" ? 2 : 1,
      glyph: GLYPH_DISK,
      execArgv: ["xdg-open", p.target]
    }
  }
  if (p.check === "reboot") {
    return {
      summary: "Reboot to finish the kernel update",
      body: "Running " + p.release + "; its modules were removed",
      urgency: 1,
      glyph: GLYPH_REBOOT,
      execArgv: ["omarchy-menu", "toggle", "system"]
    }
  }
  var logs = terminal ? ["xdg-terminal-exec", "docker", "logs", "--tail", "200", "-f", p.name] : []
  if (p.loop) {
    return {
      summary: "Container " + p.name + " keeps restarting",
      body: p.exits + " exits in 5 minutes",
      urgency: 2,
      glyph: GLYPH_CONTAINER,
      execArgv: logs
    }
  }
  return {
    summary: "Container " + p.name + " exited (code " + p.exitCode + ")",
    body: "Image " + p.image,
    urgency: 1,
    glyph: GLYPH_CONTAINER,
    execArgv: logs
  }
}

// The status icon: any open problem counts.
/**
 * A dropdown row: a problem's key and check plus its itemFor fields.
 * @typedef {object} ProblemRow
 * @property {string} key - the problem's key
 * @property {string} check - the problem's check
 * @property {string} summary - headline
 * @property {string} body - detail line
 * @property {number} urgency - 1 normal, 2 critical
 * @property {string} glyph - Nerd Font icon
 * @property {Array<string>} execArgv - command run on click; empty for none
 */

/**
 * Summarises open problems into the bar icon's status.
 * @param {Array<Problem>} open - raw problems or annotated rows
 * @returns {string} "critical" if any is urgency 2, "attention" if any other, else "healthy"
 */
function statusFor(open) {
  var status = "healthy"
  for (var i = 0; i < (open || []).length; i++) {
    // Accepts raw problems and annotated rows (which carry urgency already).
    var u = typeof open[i].urgency === "number" ? open[i].urgency : itemFor(open[i]).urgency
    if (u === 2) return "critical"
    status = "attention"
  }
  return status
}

// Rows for the dropdown's problem list (copy, urgency, click action).
/**
 * Turns open problems into dropdown rows, most urgent first, then by key.
 * @param {Array<Problem>} open - raw problems
 * @param {Tools} [tools] - available tools, passed to itemFor
 * @returns {Array<ProblemRow>} rows with key, check and the itemFor fields
 */
function annotateProblems(open, tools) {
  var rows = (open || []).map(function (p) {
    var item = itemFor(p, tools)
    return {
      key: p.key,
      check: p.check,
      summary: item.summary,
      body: item.body,
      urgency: item.urgency,
      glyph: item.glyph,
      execArgv: item.execArgv
    }
  })
  rows.sort(function (a, b) {
    return b.urgency - a.urgency || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0)
  })
  return rows
}

/**
 * Position of the row with this key.
 * @param {?Array<{key: string}>} rows - dropdown rows
 * @param {string} key - the row key, e.g. "disk:/"
 * @returns {number} its index, or -1
 */
function indexOfKey(rows, key) {
  var list = rows || []
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].key === key) return i
  return -1
}

/**
 * Key of the row delta steps from the row with this key, wrapping; the first
 * (delta > 0) or last row when the key is empty or gone.
 * @param {?Array<{key: string}>} rows - dropdown rows
 * @param {string} key - the current cursor key, or ""
 * @param {number} delta - rows to move (sign matters)
 * @returns {string} the new cursor key, or "" when there are no rows
 */
function moveCursorKey(rows, key, delta) {
  var list = rows || []
  if (list.length === 0) return ""
  var i = key ? indexOfKey(list, key) : -1
  if (i < 0) return list[delta < 0 ? list.length - 1 : 0].key
  return list[(i + delta + list.length) % list.length].key
}

if (typeof module !== "undefined") {
  module.exports = {
    isFailedExit: isFailedExit,
    indexOfKey: indexOfKey,
    moveCursorKey: moveCursorKey,
    checkOf: checkOf,
    parseFailedUnits: parseFailedUnits,
    parseDf: parseDf,
    diskLevel: diskLevel,
    diskProblems: diskProblems,
    rebootProblem: rebootProblem,
    parseDockerEvent: parseDockerEvent,
    recordDockerEvent: recordDockerEvent,
    containerProblems: containerProblems,
    pruneDockerHistory: pruneDockerHistory,
    parseDockerPs: parseDockerPs,
    seedDockerHistory: seedDockerHistory,
    humanBytes: humanBytes,
    itemFor: itemFor,
    statusFor: statusFor,
    annotateProblems: annotateProblems
  }
}
