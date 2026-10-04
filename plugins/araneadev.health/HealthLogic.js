// Pure rules for the System health monitor (Monitor.qml): parse command
// output, derive open problems and word them for the health dropdown.
// No QML, no I/O; tests/health.test.sh runs this under Node.
var DISK_ALERT = 90
var DISK_CRITICAL = 97
var DISK_CLEAR = 88
var LOOP_EXITS = 3
var LOOP_WINDOW_MS = 5 * 60 * 1000

var GLYPH_UNIT = String.fromCodePoint(0xf0493)
var GLYPH_DISK = String.fromCodePoint(0xf02ca)
var GLYPH_REBOOT = String.fromCodePoint(0xf0709)
var GLYPH_CONTAINER = String.fromCodePoint(0xf0868)

/* @aranea-facade-start: plugins/araneadev.health/HealthPresentation.js */
// Presentation helpers for health problem rows.

/**
 * Formats a byte count with 1024-based units.
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
 * The key a dropdown row is followed and acted on by: the problem's id,
 * falling back to its text when it has none.
 * @param {?{key?: *, summary?: *}} row - a dropdown row
 * @returns {string} the id, else the summary, else ""
 */
function problemKey(row) {
  if (!row) return ""
  if (typeof row.key === "string" && row.key !== "") return row.key
  return typeof row.summary === "string" ? row.summary : ""
}

/**
 * Every row's problemKey joined by newlines, so a host can tell when the
 * rows really moved (an equal list rebuilt gives the same string).
 * @param {?Array<?{key?: *, summary?: *}>} rows - dropdown rows
 * @returns {string} the joined keys, "" for no rows
 */
function problemKeys(rows) {
  return (rows || []).map(problemKey).join("\n")
}

/**
 * The row a keyed action names: row `index`, but only while it still has
 * `key`, so a click or Enter aimed before a re-sort never opens another
 * problem.
 * @param {?Array<?{key?: *, summary?: *}>} rows - dropdown rows
 * @param {number} index - the row the action names
 * @param {*} key - the key the view saw at that row
 * @returns {?object} the row, or null when it no longer carries the key
 */
function keyedProblem(rows, index, key) {
  if (typeof key !== "string" || key === "") return null
  var row = (rows || [])[index]
  return row && problemKey(row) === key ? row : null
}

/**
 * The lit fraction of a strand bar for a usage percentage.
 * @param {number} percent - usage, 0..100
 * @returns {number} the fraction, clamped to 0..1; 0 for a non-number
 */
function barFraction(percent) {
  var p = Number(percent)
  if (!isFinite(p)) return 0
  return Math.max(0, Math.min(1, p / 100))
}

/**
 * Turns the CPU history (percentages, oldest first) into the shared
 * LinkGraph's samples: the load as the receive line, no send line.
 * @param {?Array<number>} history - CPU percentages
 * @returns {Array<{rx: number, tx: number}>} one sample per entry, clamped to 0..100
 */
function cpuSamples(history) {
  return (history || []).map(function (v) {
    return { rx: Math.max(0, Math.min(100, Number(v) || 0)), tx: 0 }
  })
}

if (typeof module !== "undefined")
  module.exports = {
    humanBytes: humanBytes,
    problemKey: problemKey,
    problemKeys: problemKeys,
    keyedProblem: keyedProblem,
    barFraction: barFraction,
    cpuSamples: cpuSamples
  }
/* @aranea-facade-end */

// Generated copy of the shared cursor rules (tools/js-facade-generator.mjs),
// since there is no cross-.js-file import usable from both QML and Node;
// the keyed cursor helpers below wrap its keyed helpers with problemKey.
/* @aranea-facade-start: plugins/araneadev.shared/CursorLogic.js */
// Shared keyboard-cursor safety rules, moved out of the Network plugin so
// araneadev.vpn can reuse them: a cursor follows the row key it was put on
// (never its position), a lost or evacuated key is refused rather than
// retargeted, and a pointer action only ever lands on the row it names. No
// QML, no I/O; tests/js/cursor-logic.test.js runs this under Node. The
// keyed helpers (keyIndex, keyStep, keyedMove, keyedPress, keyedOutline)
// are Health's and Workspaces' dropdown cursors, keyed by a host function.

/**
 * The index a list cursor should sit on after its rows changed: the row
 * whose `key` equals `key` wherever it moved, else `fallback` clamped into
 * the list. Lets a cursor follow its network or profile across a re-sort
 * instead of staying on a position that now holds another row.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the new rows
 * @param {string|null|undefined} key - the key the cursor was on
 * @param {number} fallback - the index to clamp when the key is gone
 * @returns {number} the index, or -1 when there are no rows
 */
function reselectIndex(rows, key, fallback) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0) return -1
  if (typeof key === "string") {
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (row && row.key === key) return i
    }
  }
  var f = Math.floor(Number(fallback)) || 0
  return Math.max(0, Math.min(list.length - 1, f))
}

/**
 * Where a list cursor goes after its rows changed: onto the row whose `key`
 * equals `key`, wherever it moved. When that row is gone (or there was no
 * key), the index is clamped into the list but the key is dropped, so the
 * row that slid into its place is never adopted as the user's choice.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the new rows
 * @param {string|null|undefined} key - the key the cursor was deliberately put on, or ""
 * @param {number} index - the cursor's index before the change
 * @returns {{index: number, key: string, confirmed: boolean}} the new index (-1 with no rows), the key it keeps ("" when lost) and whether the cursor's row is the chosen one
 */
function followCursor(rows, key, index) {
  var list = Array.isArray(rows) ? rows : []
  var chosen = typeof key === "string" && key !== "" ? key : null
  var next = reselectIndex(list, chosen, index)
  var row = next >= 0 ? list[next] : null
  var confirmed = chosen !== null && !!row && row.key === chosen
  return { index: next, key: confirmed ? chosen : "", confirmed: confirmed }
}

/**
 * followCursor for a cursor that may be showing its outline: when the row
 * whose key the cursor held is gone, the outline hides too (`keyboard`
 * false), so it never marks a row Enter would refuse. The next key only
 * reveals the cursor again, where it now sits, and a later Enter acts.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the new rows
 * @param {string|null|undefined} key - the key the cursor was deliberately put on, or ""
 * @param {number} index - the cursor's index before the change
 * @param {boolean} keyboard - whether the keyboard shows the outline
 * @returns {{index: number, key: string, confirmed: boolean, keyboard: boolean}} followCursor's answer and whether the outline still shows
 */
function followShown(rows, key, index, keyboard) {
  var next = followCursor(rows, key, index)
  var lost = typeof key === "string" && key !== "" && !next.confirmed
  return {
    index: next.index,
    key: next.key,
    confirmed: next.confirmed,
    keyboard: !!keyboard && !lost
  }
}

/**
 * Whether the cursor's row is still the one the user chose: `key` isn't
 * empty (a hidden SSID or no choice never is) and the row at `index` has it.
 * Keyboard actions refuse otherwise.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the section's rows
 * @param {string|null|undefined} key - the key the cursor was put on
 * @param {number} index - the cursor's index
 * @returns {boolean} true when the keyboard may act on that row
 */
function cursorConfirmed(rows, key, index) {
  if (!Array.isArray(rows) || typeof key !== "string" || key === "") return false
  var row = rows[index]
  return !!row && row.key === key
}

/**
 * What Enter or `x` does: nothing before any cursor exists, only reveal a
 * cursor the keyboard isn't showing (one the pointer placed), else act.
 * @param {boolean} cursorActive - whether a cursor has been placed
 * @param {boolean} keyboardCursor - whether its outline is showing
 * @returns {string} `ignore`, `reveal` or `act`
 */
function pressIntent(cursorActive, keyboardCursor) {
  if (!cursorActive) return "ignore"
  return keyboardCursor ? "act" : "reveal"
}

/**
 * Hands back the array last stored under `name` when `next` has the same
 * content, so a view's Repeater keeps its delegates (and nothing slides
 * under a still pointer) on a refresh that changed nothing. Stores `next`
 * otherwise. `cache` is mutated in place.
 * @param {Record<string, any>|null|undefined} cache - the arrays kept so far, by name
 * @param {string} name - which row array this is
 * @param {Array<any>} next - the freshly built rows
 * @returns {Array<any>} the kept array or `next`
 */
function keepRows(cache, name, next) {
  if (!cache || typeof cache !== "object") return next
  var prev = cache[name]
  if (prev !== undefined && JSON.stringify(prev) === JSON.stringify(next)) return prev
  cache[name] = next
  return next
}

/**
 * Whether row `index` still carries `key`, so a pointer action reported for
 * one row never lands on another.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the section's rows
 * @param {number} index - the row the action names
 * @param {string|undefined} key - the key the view saw at that row
 * @returns {boolean} true when the row is the one the user clicked
 */
function rowKeyMatches(rows, index, key) {
  if (!Array.isArray(rows) || typeof key !== "string") return false
  var row = rows[index]
  return !!row && row.key === key
}

/**
 * Where the keyboard cursor goes after a row left the list (Bluetooth
 * Forget, Notifications Delete): the stop now at `lastIndex` (the row that
 * slid into the removed one's place), clamped to the last stop when it was
 * the bottom one. If `removedKey` still names a stop in `stops` (this read
 * hasn't caught up with the removal yet), that stop is returned as is
 * instead, since nothing has actually moved.
 * @param {Array<{key: string}|null|undefined>|undefined} stops - the stops, read after the removal
 * @param {string|null|undefined} removedKey - the key of the row that was removed
 * @param {number} lastIndex - the removed row's index before it left
 * @returns {{index: number, key: string}} the stop to keep the cursor on, or {index: -1, key: ""} with none left
 */
function afterRemoval(stops, removedKey, lastIndex) {
  var list = Array.isArray(stops) ? stops : []
  if (list.length === 0) return { index: -1, key: "" }
  if (typeof removedKey === "string" && removedKey !== "") {
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (row && row.key === removedKey) return { index: i, key: removedKey }
    }
  }
  var idx = Math.max(0, Math.min(list.length - 1, Math.floor(Number(lastIndex)) || 0))
  var stop = list[idx]
  return { index: idx, key: stop && typeof stop.key === "string" ? stop.key : "" }
}

/**
 * Position of the row whose `keyOf(row)` is `key`. The keyed-cursor helpers
 * below (keyStep, keyedMove, keyedPress, keyedOutline) follow a cursor by
 * the row key a host's `keyOf` gives (Health's problemKey, Workspaces'
 * workspaceKey), never by position.
 * @param {*} rows - the dropdown rows (anything but an array counts as none)
 * @param {string} key - the row key, or ""
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {number} its index, or -1 (always for an empty key)
 */
function keyIndex(rows, key, keyOf) {
  if (!key) return -1
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++) if (keyOf(list[i]) === key) return i
  return -1
}

/**
 * Key of the row `delta` steps from the row with this key, wrapping; the
 * first (delta > 0) or last row when the key is empty or gone.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the current cursor key, or ""
 * @param {number} delta - rows to move (sign matters)
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {string} the new cursor key, or "" when there are no rows
 */
function keyStep(rows, key, delta, keyOf) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0) return ""
  var i = keyIndex(list, key, keyOf)
  if (i < 0) return keyOf(list[delta < 0 ? list.length - 1 : 0])
  return keyOf(list[(i + delta + list.length) % list.length])
}

/**
 * The cursor after an up or down key. Dropdowns are reveal-first: the first
 * key after opening or after pointer use (keyboard false) only reveals the
 * cursor, on the row the pointer left it on, else the first (dy > 0) or
 * last row. Later keys move it, wrapping.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {number} dy - rows to move (sign matters); 0 does nothing
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {{key: string, keyboard: boolean}} the new cursor key and mode
 */
function keyedMove(rows, key, keyboard, dy, keyOf) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0 || !dy) return { key: key, keyboard: keyboard }
  if (!keyboard)
    return {
      key: keyIndex(list, key, keyOf) >= 0 ? key : keyStep(list, "", dy, keyOf),
      keyboard: true
    }
  return { key: keyStep(list, key, dy, keyOf), keyboard: true }
}

/**
 * What Enter or Space does on a keyed list. Like an arrow, it first only
 * reveals a cursor the keyboard is not showing: on its row when that is
 * still shown, else on the first row. Only on a shown cursor's row does it
 * hand that row back to act on. With no rows it does nothing.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {{key: string, keyboard: boolean, row: ?object}} the cursor key, the new mode and the row to act on, or null
 */
function keyedPress(rows, key, keyboard, keyOf) {
  var list = Array.isArray(rows) ? rows : []
  var i = keyIndex(list, key, keyOf)
  if (pressIntent(i >= 0, keyboard) === "act") return { key: key, keyboard: true, row: list[i] }
  if (list.length === 0) return { key: key, keyboard: keyboard, row: null }
  return { key: i >= 0 ? key : keyOf(list[0]), keyboard: true, row: null }
}

/**
 * The row the mint outline is drawn on: the cursor's, only while the
 * keyboard drives it.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {number} the row index, or -1 for no outline
 */
function keyedOutline(rows, key, keyboard, keyOf) {
  return keyboard ? keyIndex(rows, key, keyOf) : -1
}

if (typeof module !== "undefined")
  module.exports = {
    reselectIndex: reselectIndex,
    followCursor: followCursor,
    followShown: followShown,
    cursorConfirmed: cursorConfirmed,
    pressIntent: pressIntent,
    keepRows: keepRows,
    rowKeyMatches: rowKeyMatches,
    afterRemoval: afterRemoval,
    keyIndex: keyIndex,
    keyStep: keyStep,
    keyedMove: keyedMove,
    keyedPress: keyedPress,
    keyedOutline: keyedOutline
  }
/* @aranea-facade-end */

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
 * @param {string} previous - the mount's previous level ("ok", "normal" or "critical")
 * @param {number} percent - current use percentage
 * @returns {string} "critical", "normal" (alert) or "ok"
 */
function diskLevel(previous, percent) {
  var p = Number(percent)
  if (p >= DISK_CRITICAL) return "critical"
  if (p >= DISK_ALERT) return "normal"
  if (previous !== "ok" && p >= DISK_CLEAR) return "normal"
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
 * Position of the row with this key (problemKey), by CursorLogic.keyIndex.
 * @param {?Array<{key?: string, summary?: string}>} rows - dropdown rows
 * @param {string} key - the row key
 * @returns {number} its index, or -1 (always for an empty key)
 */
function indexOfKey(rows, key) {
  return keyIndex(rows, key, problemKey)
}

/**
 * Key of the row delta steps from the row with this key, wrapping
 * (CursorLogic.keyStep).
 * @param {?Array<{key?: string, summary?: string}>} rows - dropdown rows
 * @param {string} key - the current cursor key, or ""
 * @param {number} delta - rows to move (sign matters)
 * @returns {string} the new cursor key, or "" when there are no rows
 */
function moveCursorKey(rows, key, delta) {
  return keyStep(rows, key, delta, problemKey)
}

/**
 * The cursor after an up or down key; the first key after opening or after
 * pointer use only reveals it (CursorLogic.keyedMove).
 * @param {?Array<{key?: string, summary?: string}>} rows - dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {number} dy - rows to move (sign matters); 0 does nothing
 * @returns {{key: string, keyboard: boolean}} the new cursor key and mode
 */
function cursorMove(rows, key, keyboard, dy) {
  return keyedMove(rows, key, keyboard, dy, problemKey)
}

/**
 * What Enter or Space does (CursorLogic.keyedPress): like an arrow, only
 * reveal a cursor the keyboard is not showing (on the first row when it
 * has none), else open the cursor's row.
 * @param {?Array<{key?: string, summary?: string}>} rows - dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @returns {{key: string, keyboard: boolean, row: ?object}} the cursor key, the new mode and the row to open, or null
 */
function cursorPress(rows, key, keyboard) {
  return keyedPress(rows, key, keyboard, problemKey)
}

/**
 * The row the mint outline is drawn on: the cursor's, only while the
 * keyboard drives it (CursorLogic.keyedOutline).
 * @param {?Array<{key?: string, summary?: string}>} rows - dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @returns {number} the row index, or -1 for no outline
 */
function outlineIndex(rows, key, keyboard) {
  return keyedOutline(rows, key, keyboard, problemKey)
}

/**
 * The key-hint line: Enter opens the outlined problem.
 * @returns {string} the hint
 */
function keyHint() {
  return "↑↓ move · enter open"
}

if (typeof module !== "undefined") {
  module.exports = {
    keyHint: keyHint,
    isFailedExit: isFailedExit,
    indexOfKey: indexOfKey,
    moveCursorKey: moveCursorKey,
    cursorMove: cursorMove,
    cursorPress: cursorPress,
    outlineIndex: outlineIndex,
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
    problemKey: problemKey,
    problemKeys: problemKeys,
    keyedProblem: keyedProblem,
    barFraction: barFraction,
    cpuSamples: cpuSamples,
    itemFor: itemFor,
    statusFor: statusFor,
    annotateProblems: annotateProblems
  }
}
