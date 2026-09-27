// Text rules for the Aranea polkit prompt. The first three functions are
// Omarchy's PolkitModel.js (shell/plugins/polkit), unchanged; the rest build
// the request summary, context line and details from what polkit gives the
// agent (message, action id, identities) plus `pkaction --verbose` output.
// No QML, no I/O; tests/polkit.test.sh runs this under Node.

function promptLooksFingerprint(text) {
  var s = String(text || "").toLowerCase()
  return s.indexOf("finger") !== -1 || s.indexOf("fprint") !== -1 || s.indexOf("swipe") !== -1
}

function fingerprintConfiguredFromPamConfig(raw) {
  // Fingerprint is available whenever pam_fprintd appears anywhere in the auth
  // stack — it need not be the first module. A clamshell gate (pam_exec) may
  // legitimately precede it to skip fingerprint while the lid is closed.
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (!line || line.charAt(0) === "#") continue
    if (!line.match(/^auth\s+/)) continue
    if (line.indexOf("pam_fprintd.so") !== -1) return true
  }
  return false
}

function authorizationLabel(message) {
  var text = String(message || "")
  var match = text.match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i)
  return match ? "Authorize running '" + match[1] + "'" : text
}

// pkexec's messages: "Authentication is needed to run `/usr/bin/true' as the
// super user" and "... as user Tim Schipper (tim)".
var PKEXEC_MESSAGE =
  /^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as (?:(the super user)|user (.+))$/i

function parsePkexec(message) {
  var match = String(message || "")
    .trim()
    .match(PKEXEC_MESSAGE)
  if (!match) return null
  return { command: match[1], target: match[2] ? "root" : match[3].trim() }
}

function summaryParts(message) {
  // One logical line: StyledText would otherwise decide how breaks render.
  var text = String(message || "")
    .replace(/\s*[\r\n]+\s*/g, " ")
    .trim()
  var parsed = parsePkexec(text)
  if (parsed) return { prefix: "Run '", command: parsed.command, suffix: "' as " + parsed.target }
  return { prefix: text || "Authentication is needed", command: "", suffix: "" }
}

function requestSummary(message) {
  var parts = summaryParts(message)
  return parts.prefix + parts.command + parts.suffix
}

function commandFromMessage(message) {
  var parsed = parsePkexec(message)
  return parsed ? parsed.command : ""
}

function shortenMiddle(text, max) {
  var s = String(text || "")
  var limit = Math.max(5, max || 64)
  if (s.length <= limit) return s
  var keep = limit - 1
  var head = Math.ceil(keep / 2)
  return s.slice(0, head) + "…" + s.slice(s.length - (keep - head))
}

function escapeHtml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

// StyledText for the request line: the command in the accent colour, every
// piece of polkit-supplied text escaped so it is shown, never interpreted.
function requestMarkup(message, accent) {
  var parts = summaryParts(message)
  var out = escapeHtml(parts.prefix)
  if (parts.command)
    out +=
      '<font color="' +
      escapeHtml(accent) +
      '">' +
      escapeHtml(shortenMiddle(parts.command, 64)) +
      "</font>"
  return out + escapeHtml(parts.suffix)
}

function validActionId(id) {
  var s = id === undefined || id === null ? "" : String(id)
  return s.length >= 1 && s.length <= 255 && /^[A-Za-z0-9._-]+$/.test(s)
}

function parseActionInfo(text) {
  var info = { description: "", vendor: "" }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*(description|vendor):\s*(.*)$/)
    if (match && !info[match[1]]) info[match[1]] = match[2].trim()
  }
  return info
}

// Polkit's Identity type is not declared to qmllint, so the QML passes
// identities here as plain values and reads nothing from them itself.
function identityLabel(identity) {
  if (!identity) return ""
  var name = String(identity.displayName || "").trim()
  if (name) return name
  return String(identity.string || "").trim()
}

function indexOfIdentity(identities, selected) {
  if (!identities || !selected) return -1
  for (var i = 0; i < identities.length; i++) {
    if (identities[i] === selected) return i
  }
  return -1
}

function identityPosition(identities, selected) {
  var count = identities ? identities.length : 0
  if (count < 2) return ""
  var index = indexOfIdentity(identities, selected)
  return index < 0 ? "" : " (" + (index + 1) + " of " + count + ")"
}

function nextIdentityIndex(count, current) {
  if (count < 1) return -1
  return current < 0 ? 0 : (current + 1) % count
}

function contextLine(description, identity, position) {
  var parts = []
  if (description) parts.push(description)
  if (identity) parts.push("as " + identity + (position || ""))
  return parts.join(" · ")
}

function detailRows(actionId, vendor, command, message) {
  var rows = [
    { key: "ACTION", value: String(actionId || "") },
    { key: "VENDOR", value: String(vendor || "") },
    { key: "COMMAND", value: String(command || "") },
    { key: "MESSAGE", value: String(message || "") }
  ]
  return rows.filter(function (row) {
    return row.value.length > 0
  })
}

function promptPlaceholder(prompt) {
  var s = String(prompt || "")
    .trim()
    .replace(/:\s*$/, "")
    .trim()
  if (!s || /^password$/i.test(s)) return "Enter password"
  return s
}

if (typeof module !== "undefined") {
  module.exports = {
    promptLooksFingerprint: promptLooksFingerprint,
    fingerprintConfiguredFromPamConfig: fingerprintConfiguredFromPamConfig,
    authorizationLabel: authorizationLabel,
    summaryParts: summaryParts,
    requestSummary: requestSummary,
    commandFromMessage: commandFromMessage,
    shortenMiddle: shortenMiddle,
    escapeHtml: escapeHtml,
    requestMarkup: requestMarkup,
    validActionId: validActionId,
    parseActionInfo: parseActionInfo,
    identityLabel: identityLabel,
    indexOfIdentity: indexOfIdentity,
    identityPosition: identityPosition,
    nextIdentityIndex: nextIdentityIndex,
    contextLine: contextLine,
    detailRows: detailRows,
    promptPlaceholder: promptPlaceholder
  }
}
