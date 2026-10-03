// Pure rules for the Aranea audio dropdown (Panel.qml): the live signal
// level behind the filament glow, which media player Now playing follows
// when Omarchy's media service is missing, the Now playing state, the
// device rows' trailing detail, the pending default-device switch and the
// keyed node lookups behind every row action, and the README capture's
// display-only stand-ins (the `showcase` IPC method). No QML, no I/O;
// tests/js/audio-logic.test.js runs this under Node.

/**
 * Now playing state for one player (nowPlayingState).
 * @typedef {object} NowPlaying
 * @property {boolean} visible - a player exists
 * @property {string} player - the player's name
 * @property {string} title - track title, else the player's name
 * @property {string} artist - track artist or ""
 * @property {string} album - track album or ""
 * @property {number} progress - position / length, 0..1, or -1 without a length
 * @property {boolean} playing - the player is playing
 * @property {boolean} canPrevious - previous track is possible
 * @property {boolean} canNext - next track is possible
 */

var attackMs = 30
var decayMs = 300

/**
 * Limits a number to 0..1.
 * @param {number} value - number to limit
 * @returns {number} value clamped to 0..1
 */
function unit(value) {
  return Math.max(0, Math.min(1, value))
}

/**
 * Smooths a peak reading into the glow level: fast attack, slow decay.
 * @param {number} previous - the last level, 0..1
 * @param {number} peak - the new peak reading (NaN counts as silence)
 * @param {number} dtMs - milliseconds since the last reading
 * @returns {number} the new level, 0..1 (tiny levels snap to 0)
 */
function signalLevel(previous, peak, dtMs) {
  var from = isFinite(previous) ? unit(previous) : 0
  if (!(dtMs > 0)) return from
  var target = isFinite(peak) ? unit(peak) : 0
  var tau = target > from ? attackMs : decayMs
  var ratio = dtMs / tau
  var next = ratio >= 10 ? target : from + (target - from) * (1 - Math.exp(-ratio))
  return next < 0.001 ? 0 : unit(next)
}

/**
 * Chooses the player Now playing follows: a playing one, else the last one.
 * @param {Array<{dbusName: string, isPlaying: boolean}>} players - MprisPlayer-like objects
 * @param {string} lastKey - dbusName of the player shown last
 * @returns {{dbusName: string, isPlaying: boolean}|null} the player, or null
 */
function pickPlayer(players, lastKey) {
  var list = players || []
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].isPlaying === true) return list[i]
  for (var j = 0; j < list.length; j++) if (list[j] && list[j].dbusName === lastKey) return list[j]
  return null
}

/**
 * The Now playing strip's content for a player.
 * @param {{identity: string, trackTitle: string, trackArtist: string, trackAlbum: string, position: number, length: number, lengthSupported: boolean, isPlaying: boolean, canGoPrevious: boolean, canGoNext: boolean}|null} player - an MprisPlayer-like object
 * @returns {NowPlaying} what the strip shows
 */
function nowPlayingState(player) {
  if (!player)
    return {
      visible: false,
      player: "",
      title: "",
      artist: "",
      album: "",
      progress: -1,
      playing: false,
      canPrevious: false,
      canNext: false
    }
  var name = String(player.identity || "")
  var length = Number(player.length) || 0
  var hasLength = player.lengthSupported === true && length > 0
  return {
    visible: true,
    player: name,
    title: String(player.trackTitle || "") || name,
    artist: String(player.trackArtist || ""),
    album: String(player.trackAlbum || ""),
    progress: hasLength ? unit((Number(player.position) || 0) / length) : -1,
    playing: player.isPlaying === true,
    canPrevious: player.canGoPrevious === true,
    canNext: player.canGoNext === true
  }
}

/**
 * A device row's short trailing detail: how the device is connected, else
 * what it is. Reads the properties Model.nodeProps returns; headphone
 * detection stays in Model.isHeadphones, whose answer comes in HEADPHONES.
 * @param {{[key: string]: *}|null|undefined} props - the node's Pipewire properties
 * @param {boolean} isSink - an output (else an input) device
 * @param {boolean} headphones - Model.isHeadphones said so
 * @returns {string} e.g. "HDMI", "bluetooth", "speakers" or "mic"
 */
function deviceDetail(props, isSink, headphones) {
  if (headphones) return "headphones"
  var p = props || {}
  var keys = [
    "node.name",
    "node.description",
    "device.api",
    "device.bus",
    "device.icon-name",
    "device.product.name"
  ]
  var blob = keys
    .map(function (key) {
      return String(p[key] || "")
    })
    .join(" ")
    .toLowerCase()
  if (blob.indexOf("hdmi") !== -1) return "HDMI"
  if (blob.indexOf("displayport") !== -1) return "DisplayPort"
  if (blob.indexOf("bluez") !== -1 || blob.indexOf("bluetooth") !== -1) return "bluetooth"
  if (blob.indexOf("usb") !== -1) return "USB"
  return isSink ? "speakers" : "mic"
}

/**
 * A pending default-device switch for one channel: `target` is the device
 * key (deviceKey: its node id and name) sent as the new default and not
 * yet reported by PipeWire (null when idle), `queued` the key clicked
 * while waiting (null for none).
 * @typedef {{target: ?string, queued: ?string}} DefaultPending
 */

/** How long a default-device switch may stay pending, in ms. */
var defaultTimeoutMs = 4000

/**
 * The idle default-device state: nothing sent, nothing queued.
 * @returns {DefaultPending} a fresh idle state
 */
function defaultIdle() {
  return { target: null, queued: null }
}

/**
 * Whether a key is set (a string other than "").
 * @param {*} key - a device key, or null/undefined
 * @returns {boolean} true for a non-empty string
 */
function hasKey(key) {
  return typeof key === "string" && key !== ""
}

/**
 * A device row chosen as the new default (a click or Enter). Idle, it is
 * sent at once; when it already is the default it is sent again without
 * waiting (the helper re-applies it, as before) and nothing pulses. While
 * a switch is in flight the choice only queues: the last one wins, and a
 * choice of the in-flight device empties the queue.
 * @param {?DefaultPending} state - the pending state (null counts as idle)
 * @param {string} key - the chosen device's key
 * @param {string} actual - the key of PipeWire's default now ("" for none)
 * @returns {{state: DefaultPending, send: ?string}} the next state and the key to send now (null: send nothing)
 */
function defaultClick(state, key, actual) {
  var s = state || defaultIdle()
  if (!hasKey(key)) return { state: s, send: null }
  if (!hasKey(s.target)) {
    if (key === actual) return { state: defaultIdle(), send: key }
    return { state: { target: key, queued: null }, send: key }
  }
  return { state: { target: s.target, queued: key === s.target ? null : key }, send: null }
}

/**
 * PipeWire's default device changed (or was read back). When it reaches
 * the in-flight target, a queued key that differs is sent next; otherwise
 * the switch goes idle. Any other default keeps waiting (the timeout calls
 * defaultAfter).
 * @param {?DefaultPending} state - the pending state
 * @param {string} actual - the key of PipeWire's default now ("" for none)
 * @returns {{state: DefaultPending, send: ?string}} the next state and the key to send now (null: send nothing)
 */
function defaultEcho(state, actual) {
  var s = state || defaultIdle()
  if (!hasKey(s.target) || s.target !== actual) return { state: s, send: null }
  if (hasKey(s.queued) && s.queued !== actual)
    return { state: { target: s.queued, queued: null }, send: s.queued }
  return { state: defaultIdle(), send: null }
}

/**
 * The pending state after a lifetime EVENT: the timeout falls back to the
 * real default; closing the panel drops the queued choice, so it never
 * runs with nobody watching, but lets the one in flight finish; anything
 * else keeps it.
 * @param {string} event - "timeout", "close" or anything else
 * @param {?DefaultPending} state - the pending state
 * @returns {DefaultPending} the state to keep
 */
function defaultAfter(event, state) {
  var s = state || defaultIdle()
  if (event === "timeout") return defaultIdle()
  if (event === "close") return { target: hasKey(s.target) ? s.target : null, queued: null }
  return { target: s.target, queued: s.queued }
}

/**
 * Which device the rows show as the default: the queued key, else the
 * in-flight one, else PipeWire's; busy (its row pulses) while a switch is
 * in flight.
 * @param {?DefaultPending} state - the pending state
 * @param {string} actual - the key of PipeWire's default now ("" for none)
 * @returns {{key: string, busy: boolean}} the shown default's key and whether it pulses
 */
function defaultView(state, actual) {
  var s = state || defaultIdle()
  var busy = hasKey(s.target)
  var key = hasKey(s.queued) ? s.queued : busy ? s.target : String(actual || "")
  return { key: String(key), busy: busy }
}

/**
 * A device's key: its node id and name together, so a node id PipeWire
 * reuses for another device never reads as the old one.
 * @param {{id: *, name?: *}|null|undefined} node - a PwNode-like object
 * @returns {string} "id:name", or "" without a node
 */
function deviceKey(node) {
  if (!node) return ""
  return String(node.id) + ":" + String(node.name || "")
}

/**
 * A node's key: deviceKey when BY_NAME (devices), else its id (streams).
 * @param {{id: *, name?: *}} node - a PwNode-like object
 * @param {boolean|undefined} byName - key by id and name
 * @returns {string} the key
 */
function keyOf(node, byName) {
  return byName ? deviceKey(node) : String(node.id)
}

/**
 * The node a keyed row action means: the one at INDEX, but only while its
 * key still reads as KEY. A list that changed underneath (a re-sort, a
 * stream leaving) refuses the action rather than hit another node.
 * @param {Array<{id: *, name?: *}>|null|undefined} list - the nodes the rows were built from
 * @param {number} index - the row's index
 * @param {string} key - the row's key as the view held it
 * @param {boolean} [byName] - KEY is a deviceKey (id and name), else the id
 * @returns {{id: *}|null} the node, or null when it no longer matches
 */
function nodeAt(list, index, key, byName) {
  var nodes = list || []
  if (!hasKey(key) || !(index >= 0) || index >= nodes.length) return null
  var node = nodes[index]
  return node && keyOf(node, byName) === key ? node : null
}

/**
 * The node whose key reads as KEY, wherever it sits in LIST.
 * @param {Array<{id: *, name?: *}>|null|undefined} list - nodes to search
 * @param {string} key - the key to find
 * @param {boolean} [byName] - KEY is a deviceKey (id and name), else the id
 * @returns {{id: *}|null} the node, or null when none has that key
 */
function nodeByKey(list, key, byName) {
  var nodes = list || []
  if (!hasKey(key)) return null
  for (var i = 0; i < nodes.length; i++)
    if (nodes[i] && keyOf(nodes[i], byName) === key) return nodes[i]
  return null
}

/**
 * The README capture's stand-ins (showcaseCall): labels for the output,
 * input and stream rows, and a made-up track for Now playing.
 * @typedef {object} AudioShowcase
 * @property {string[]} outputs - output row labels, in display order
 * @property {string[]} inputs - input row labels, in display order
 * @property {string[]} apps - stream (Sources) row labels, in display order
 * @property {{title: string, artist: string, album: string, player: string, progress: number}} track - the stand-in track
 */

/**
 * Whether VALUE is a non-empty array of strings.
 * @param {*} value - anything
 * @returns {boolean} true for a non-empty string array
 */
function nameList(value) {
  if (!Array.isArray(value) || value.length === 0) return false
  for (var i = 0; i < value.length; i++) if (typeof value[i] !== "string") return false
  return true
}

/**
 * Reads the stand-ins handed to the `showcase` IPC method: a JSON object
 * with non-empty string arrays "outputs", "inputs" and "apps", and a
 * "track" with a non-empty "title", string "artist" and "player", an
 * optional string "album" and a "progress" number in 0..1. Anything else
 * is refused, so a capture never falls back to the real names.
 * @param {string|undefined} json - the call's JSON
 * @returns {AudioShowcase|null} the stand-ins, or null when invalid
 */
function parseShowcase(json) {
  var parsed
  try {
    parsed = JSON.parse(String(json))
  } catch (e) {
    return null
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
  if (!nameList(parsed.outputs) || !nameList(parsed.inputs) || !nameList(parsed.apps)) return null
  var t = parsed.track
  if (!t || typeof t !== "object") return null
  if (typeof t.title !== "string" || t.title === "") return null
  if (typeof t.artist !== "string" || typeof t.player !== "string") return null
  if (t.album !== undefined && typeof t.album !== "string") return null
  if (typeof t.progress !== "number" || !(t.progress >= 0 && t.progress <= 1)) return null
  return {
    outputs: parsed.outputs.slice(),
    inputs: parsed.inputs.slice(),
    apps: parsed.apps.slice(),
    track: {
      title: t.title,
      artist: t.artist,
      album: t.album || "",
      player: t.player,
      progress: t.progress
    }
  }
}

/**
 * The answer to a `showcase` IPC call. Stand-ins are taken only while the
 * dropdown is open (it clears them on open and on close).
 * @param {boolean} opened - the dropdown is open
 * @param {string|undefined} json - the call's JSON
 * @returns {{answer: string, showcase: AudioShowcase|null}} "ok" with the
 *   stand-ins, or "closed" / "invalid" with null
 */
function showcaseCall(opened, json) {
  if (!opened) return { answer: "closed", showcase: null }
  var showcase = parseShowcase(json)
  return showcase === null
    ? { answer: "invalid", showcase: null }
    : { answer: "ok", showcase: showcase }
}

/**
 * What Now playing shows: the stand-in track while showcasing (shown even
 * without a real player, playing, with its progress), else REAL.
 * @param {AudioShowcase|null|undefined} showcase - the stand-ins, or null
 * @param {NowPlaying} real - nowPlayingState of the followed player
 * @returns {NowPlaying} the strip's content
 */
function showcaseNowPlaying(showcase, real) {
  if (!showcase) return real
  var t = showcase.track
  return {
    visible: true,
    player: t.player,
    title: t.title,
    artist: t.artist,
    album: t.album,
    progress: t.progress,
    playing: true,
    canPrevious: true,
    canNext: true
  }
}

if (typeof module !== "undefined")
  module.exports = {
    signalLevel,
    pickPlayer,
    nowPlayingState,
    deviceDetail,
    defaultTimeoutMs,
    defaultIdle,
    defaultClick,
    defaultEcho,
    defaultAfter,
    defaultView,
    deviceKey,
    nodeAt,
    nodeByKey,
    parseShowcase,
    showcaseCall,
    showcaseNowPlaying
  }
