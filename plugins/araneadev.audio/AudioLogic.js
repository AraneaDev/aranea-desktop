// Pure rules for the Aranea audio dropdown (Panel.qml): the live signal
// level behind the filament glow, which media player Now playing follows
// when Omarchy's media service is missing, the Now playing state and the
// device rows' trailing detail. No QML, no I/O;
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

if (typeof module !== "undefined")
  module.exports = { signalLevel, pickPlayer, nowPlayingState, deviceDetail }
