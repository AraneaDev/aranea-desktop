/**
 * Tells whether a Pipewire node is a real playback stream (an application's
 * output), as opposed to a capture stream or a speaker-tuning's own output.
 * @param {*} node - the Pipewire node, or falsy
 * @returns {boolean} true when the node is a playback stream
 */
function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return (
    mediaClass.indexOf("Stream/Output/Audio") !== -1 ||
    mediaClass.indexOf("AudioOutStream") !== -1 ||
    mediaClass.indexOf("Output") !== -1
  )
}

/**
 * Tells whether a Pipewire node is a real (non-quickshell) audio source.
 * @param {*} node - the Pipewire node, or falsy
 * @returns {boolean} true when the node is an audio source
 */
function isAudioSource(node) {
  if (!node) return false
  if (node.audio) return true

  var mediaClass = String(node.type || "")
  return (
    mediaClass.indexOf("Audio/Source") !== -1 ||
    mediaClass.indexOf("AudioSource") !== -1 ||
    mediaClass.indexOf("Source") !== -1
  )
}

/**
 * Copies a live list-like value (a Pipewire model or plain array) into a
 * plain array snapshot.
 * @param {*} list - the list-like value, or falsy
 * @returns {Array<*>} a plain array copy, or [] when list has no slice()
 */
function listSnapshot(list) {
  return list && list.slice ? list.slice() : []
}

/**
 * The playful mood name for a given output volume and mute state.
 * @param {number} volume - the output volume, 0..1
 * @param {boolean} muted - whether the output is muted
 * @returns {string} the mood name, "Muted" when muted
 */
function outputVolumeName(volume, muted) {
  if (muted) return "Muted"
  var p = Math.round(volume * 100)
  if (p === 0) return "Silenced"
  if (p >= 100) return "Concert hall"
  if (p >= 85) return "Party mode"
  if (p >= 70) return "Cranked up"
  if (p >= 50) return "Steady groove"
  if (p >= 30) return "Easy listening"
  if (p >= 15) return "Murmur"
  return "Whisper"
}

/**
 * Parses omarchy-audio-sink-availability's "name\tavailable" lines.
 * @param {*} raw - the command's stdout
 * @returns {{[key: string]: boolean}} sink name to availability (0 means unavailable)
 */
function parseSinkAvailability(raw) {
  /** @type {{[key: string]: boolean}} */
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    if (parts.length >= 2) next[parts[0]] = parts[1] !== "0"
  }
  return next
}

/**
 * Strips noisy vendor/profile prefixes and suffixes from a device label.
 * @param {*} text - the raw device label
 * @returns {string} the cleaned-up label
 */
function friendlyDeviceLabel(text) {
  var label = String(text || "").trim()
  label = label.replace(/^sof-soundwire\s+/i, "")
  label = label.replace(/^built-?in audio\s+/i, "")
  label = label.replace(/\s+Output$/i, "")
  label = label.replace(/\s+Input$/i, "")
  label = label.replace(/\bMicrophones\b/g, "Microphone")
  return label
}

/**
 * The node's PipeWire properties bag, safe to read even before it is bound.
 * @param {*} node - the Pipewire node, or falsy
 * @returns {{[key: string]: string}} node.properties when the node is ready, else {}
 */
function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

/**
 * The display label for a sink or source node: its nickname when useful,
 * else its description or name, with device-label cleanup applied.
 * @param {*} node - the Pipewire node, or falsy
 * @returns {string} the label, or "Unknown" when node is falsy
 */
function nodeLabel(node) {
  if (!node) return "Unknown"
  var p = nodeProps(node)
  var nickname = friendlyDeviceLabel(
    node.nickname || node.nick || p["node.nick"] || p["device.profile.description"] || ""
  )
  if (nickname) return nickname
  return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "Unknown")
}

/**
 * Tells whether a device node looks like headphones, a headset or earbuds,
 * from its name, description and device properties.
 * @param {*} node - the Pipewire node, or falsy
 * @returns {boolean} true when the node looks like a headphone-class device
 */
function isHeadphones(node) {
  if (!node) return false
  var p = nodeProps(node)
  var blob = String(
    [
      node.name,
      node.description,
      node.nickname,
      p["device.icon-name"] || "",
      p["device.product.name"] || "",
      p["node.description"] || "",
      p["node.nick"] || ""
    ].join(" ")
  ).toLowerCase()
  return (
    blob.indexOf("headphone") !== -1 ||
    blob.indexOf("headset") !== -1 ||
    blob.indexOf("earbud") !== -1 ||
    blob.indexOf("earphone") !== -1 ||
    blob.indexOf("airpod") !== -1
  )
}

/**
 * The Nerd Font glyph for an audio sink (output) device.
 * @param {*} node - the Pipewire sink node, or falsy
 * @returns {string} the glyph
 */
function sinkGlyph(node) {
  if (!node) return "󰓃"
  if (isHeadphones(node)) return "󰋋"
  var p = nodeProps(node)
  var blob = String(
    [
      node.name,
      node.description,
      node.nickname,
      p["device.icon-name"] || "",
      p["device.product.name"] || ""
    ].join(" ")
  ).toLowerCase()
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
  return "󰓃"
}

/**
 * The Nerd Font glyph for an audio source (microphone) device.
 * @param {*} node - the Pipewire source node, or falsy
 * @returns {string} the glyph
 */
function sourceGlyph(node) {
  if (!node) return "󰍬"
  var p = nodeProps(node)
  var blob = String(
    [node.name, node.description, node.nickname, p["device.icon-name"] || ""].join(" ")
  ).toLowerCase()
  if (blob.indexOf("headset") !== -1) return "󰋋"
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1) return "󰄀"
  return "󰍬"
}

/**
 * Maps a few known raw stream labels to their friendly display name.
 * @param {string} label - the raw stream label
 * @returns {string} the friendly label, or the trimmed input when it is not a known one
 */
function friendlyStreamLabel(label) {
  label = String(label || "").trim()
  if (!label) return ""

  /** @type {{[key: string]: string}} */
  var known = {
    spotify: "Spotify"
  }
  var normalized = label.toLowerCase()
  return known[normalized] || label
}

/**
 * Normalizes a stream label for case-insensitive comparison.
 * @param {string} label - the stream label
 * @returns {string} the trimmed, lower-cased label
 */
function streamLabelKey(label) {
  return String(label || "")
    .trim()
    .toLowerCase()
}

/**
 * Tells whether a stream label is PipeWire's generic placeholder ("audio-src").
 * @param {string} label - the stream label
 * @returns {boolean} true when the label is the generic placeholder
 */
function streamLabelIsGeneric(label) {
  return streamLabelKey(label) === "audio-src"
}

/**
 * The raw (not yet friendliness-mapped) label for a playback stream node.
 * @param {*} node - the Pipewire stream node
 * @returns {string} the application name, description or node name, or "" when node is falsy
 */
function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"] || node.description || p["media.name"] || p["node.name"] || node.name
}

/**
 * The display label for an MPRIS player: its identity, or desktop entry.
 * @param {*} player - the MPRIS player, or falsy
 * @returns {string} the friendly label, or "" when player is falsy
 */
function mprisPlayerLabel(player) {
  if (!player) return ""
  return friendlyStreamLabel(player.identity || player.desktopEntry || "")
}

/**
 * Tells whether an MPRIS player is playerctld's own proxy player rather than
 * a real app.
 * @param {*} player - the MPRIS player
 * @returns {boolean} true when the player is the playerctld proxy
 */
function mprisPlayerIsProxy(player) {
  var dbusName = String((player && player.dbusName) || "").toLowerCase()
  var desktopEntry = String((player && player.desktopEntry) || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

/**
 * Tells whether a stream label and an MPRIS player label refer to the same app.
 * @param {string} streamLabel - the stream's (already friendly) label
 * @param {string} playerLabel - the MPRIS player's label
 * @returns {boolean} true when the labels match or one contains the other
 */
function streamRepresentsMprisPlayer(streamLabel, playerLabel) {
  var streamKey = streamLabelKey(friendlyStreamLabel(streamLabel))
  var playerKey = streamLabelKey(playerLabel)
  if (!streamKey || !playerKey) return false
  return (
    streamKey === playerKey ||
    streamKey.indexOf(playerKey) !== -1 ||
    playerKey.indexOf(streamKey) !== -1
  )
}

/**
 * Picks the single MPRIS player label matching a predicate, preferring a
 * playing, non-proxy player, then a playing proxy, then any match.
 * @param {Array<*>} players - all known MPRIS players
 * @param {(label: string) => boolean} predicate - tests a candidate player label
 * @returns {string} the chosen label, or "" when none or more than one tie
 */
function mprisLabelsFor(players, predicate) {
  var values = Array.isArray(players) ? players : []
  var playingCandidates = []
  var candidates = []
  var playingProxyCandidates = []
  var proxyCandidates = []

  for (var i = 0; i < values.length; i++) {
    var player = values[i]
    if (!player) continue
    if (!player.isPlaying && !player.canPlay) continue

    var playerLabel = mprisPlayerLabel(player)
    if (!playerLabel || !predicate(playerLabel)) continue

    if (mprisPlayerIsProxy(player)) {
      if (player.isPlaying) playingProxyCandidates.push(playerLabel)
      proxyCandidates.push(playerLabel)
    } else {
      if (player.isPlaying) playingCandidates.push(playerLabel)
      candidates.push(playerLabel)
    }
  }

  if (playingCandidates.length === 1) return playingCandidates[0]
  if (playingCandidates.length === 0 && playingProxyCandidates.length === 1)
    return playingProxyCandidates[0]
  if (candidates.length === 1) return candidates[0]
  if (candidates.length === 0 && proxyCandidates.length === 1) return proxyCandidates[0]
  return ""
}

/**
 * Finds the MPRIS player whose label matches a (non-generic) stream label.
 * @param {string} label - the stream's raw label
 * @param {Array<*>} players - all known MPRIS players
 * @returns {string} the matched player label, or "" when the label is generic or nothing matches
 */
function matchingMprisStreamLabel(label, players) {
  if (streamLabelIsGeneric(label)) return ""
  return mprisLabelsFor(players, function (playerLabel) {
    return streamRepresentsMprisPlayer(label, playerLabel)
  })
}

/**
 * Finds the one playing MPRIS player not already claimed by another,
 * non-generic stream label, for a stream whose own label is generic
 * (e.g. Spotify's "audio-src").
 * @param {string} label - the stream's raw label
 * @param {Array<*>} players - all known MPRIS players
 * @param {Array<*>} streams - the currently displayed playback streams
 * @returns {string} the matched player label, or "" when the stream label is not generic or nothing matches
 */
function unmatchedMprisStreamLabel(label, players, streams) {
  if (!streamLabelIsGeneric(label)) return ""

  return mprisLabelsFor(players, function (playerLabel) {
    var values = Array.isArray(streams) ? streams : []
    for (var i = 0; i < values.length; i++) {
      var stream = values[i]
      var streamLabel = rawStreamLabel(stream)
      if (
        !streamLabelIsGeneric(streamLabel) &&
        streamRepresentsMprisPlayer(streamLabel, playerLabel)
      )
        return false
    }
    return true
  })
}

/**
 * The display label for a playback stream: matched to its MPRIS player when
 * one applies, else the stream's own raw label.
 * @param {*} node - the Pipewire stream node
 * @param {Array<*>} players - all known MPRIS players
 * @param {Array<*>} streams - the currently displayed playback streams
 * @returns {string} the label, or "Stream" when node is falsy
 */
function streamLabel(node, players, streams) {
  if (!node) return "Stream"
  var label = rawStreamLabel(node)
  return (
    friendlyStreamLabel(
      matchingMprisStreamLabel(label, players) ||
        unmatchedMprisStreamLabel(label, players, streams) ||
        label
    ) || "Stream"
  )
}

/**
 * Tells whether a Pipewire stream node represents a given MPRIS player.
 * @param {*} node - the Pipewire stream node
 * @param {*} player - the MPRIS player (Quickshell MprisPlayer), or falsy
 * @param {Array<*>} players - all known MPRIS players
 * @param {Array<*>} streams - the currently displayed playback streams
 * @returns {boolean} true when the stream belongs to that player
 */
function streamRepresentsPlayer(node, player, players, streams) {
  if (!node || !player) return false
  var playerLabel = mprisPlayerLabel(player)
  if (!playerLabel) return false

  var label = rawStreamLabel(node)
  if (!streamLabelIsGeneric(label)) return streamRepresentsMprisPlayer(label, playerLabel)
  return streamRepresentsMprisPlayer(streamLabel(node, players, streams), playerLabel)
}

if (typeof module !== "undefined") {
  module.exports = {
    isPlaybackStream: isPlaybackStream,
    isAudioSource: isAudioSource,
    listSnapshot: listSnapshot,
    outputVolumeName: outputVolumeName,
    parseSinkAvailability: parseSinkAvailability,
    friendlyDeviceLabel: friendlyDeviceLabel,
    nodeProps: nodeProps,
    nodeLabel: nodeLabel,
    isHeadphones: isHeadphones,
    sinkGlyph: sinkGlyph,
    sourceGlyph: sourceGlyph,
    friendlyStreamLabel: friendlyStreamLabel,
    streamLabelKey: streamLabelKey,
    streamLabelIsGeneric: streamLabelIsGeneric,
    rawStreamLabel: rawStreamLabel,
    mprisPlayerLabel: mprisPlayerLabel,
    mprisPlayerIsProxy: mprisPlayerIsProxy,
    streamRepresentsMprisPlayer: streamRepresentsMprisPlayer,
    mprisLabelsFor: mprisLabelsFor,
    matchingMprisStreamLabel: matchingMprisStreamLabel,
    unmatchedMprisStreamLabel: unmatchedMprisStreamLabel,
    streamLabel: streamLabel,
    streamRepresentsPlayer: streamRepresentsPlayer
  }
}
