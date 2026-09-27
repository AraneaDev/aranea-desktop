// Text rules for the Aranea polkit prompt. The first three functions are
// Omarchy's PolkitModel.js (shell/plugins/polkit), unchanged; the rest build
// the request summary, context line and details from what polkit gives the
// agent (message, action id, identities) plus `pkaction --verbose` output.
// No QML, no I/O; tests/polkit.test.sh runs this under Node.

/**
 * A polkit identity as the QML passes it (a Quickshell Identity object).
 * @typedef {object} PolkitIdentity
 * @property {string} [displayName] - the human name, e.g. "Tim Schipper"
 * @property {string} [string] - the identity string, e.g. "unix-user:tim"
 */

/**
 * The request line split around the command.
 * @typedef {object} SummaryParts
 * @property {string} prefix - text before the command (the whole message when not pkexec)
 * @property {string} command - the pkexec command, or ""
 * @property {string} suffix - text after the command, e.g. "' as root", or ""
 */

/**
 * Tells whether a PAM prompt is asking for a fingerprint (mentions "finger", "fprint" or "swipe", any case).
 * @param {?string} text - the PAM prompt text; null or empty counts as not fingerprint
 * @returns {boolean} true when the prompt looks like a fingerprint prompt
 */
function promptLooksFingerprint(text) {
  var s = String(text || "").toLowerCase()
  return s.indexOf("finger") !== -1 || s.indexOf("fprint") !== -1 || s.indexOf("swipe") !== -1
}

/**
 * Tells whether a PAM config enables fingerprint auth: any uncommented `auth` line loads pam_fprintd.so.
 * @param {?string} raw - contents of a PAM config file such as /etc/pam.d/polkit-1
 * @returns {boolean} true when pam_fprintd.so appears in the auth stack
 */
function fingerprintConfiguredFromPamConfig(raw) {
  // Fingerprint is available whenever pam_fprintd appears anywhere in the auth
  // stack; it need not be the first module. A clamshell gate (pam_exec) may
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

/**
 * Turns pkexec's "Authentication is needed to run `cmd' as ..." into "Authorize running 'cmd'"; other text is returned as is.
 * @param {?string} message - the polkit request message
 * @returns {string} the short label, or the message unchanged
 */
function authorizationLabel(message) {
  var text = String(message || "")
  var match = text.match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i)
  return match ? "Authorize running '" + match[1] + "'" : text
}

// pkexec's messages: "Authentication is needed to run `/usr/bin/true' as the
// super user" and "... as user Tim Schipper (tim)".
var PKEXEC_MESSAGE =
  /^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as (?:(the super user)|user (.+))$/i

/**
 * Parses a pkexec message into the command and the target user ("root" for the super user).
 * @param {?string} message - the polkit request message
 * @returns {?{command: string, target: string}} the parts, or null when it is not a pkexec message
 */
function parsePkexec(message) {
  var match = String(message || "")
    .trim()
    .match(PKEXEC_MESSAGE)
  if (!match) return null
  return { command: match[1], target: match[2] ? "root" : match[3].trim() }
}

/**
 * Splits the request message, flattened to one line, into prefix, command and suffix; non-pkexec
 * messages come back whole as the prefix ("Authentication is needed" when empty).
 * @param {?string} message - the polkit request message
 * @returns {SummaryParts} the three pieces of the request line
 */
function summaryParts(message) {
  // One logical line: StyledText would otherwise decide how breaks render.
  var text = String(message || "")
    .replace(/\s*[\r\n]+\s*/g, " ")
    .trim()
  var parsed = parsePkexec(text)
  if (parsed) return { prefix: "Run '", command: parsed.command, suffix: "' as " + parsed.target }
  return { prefix: text || "Authentication is needed", command: "", suffix: "" }
}

/**
 * Builds the plain-text request line, e.g. "Run '/usr/bin/true' as root".
 * @param {?string} message - the polkit request message
 * @returns {string} the request summary
 */
function requestSummary(message) {
  var parts = summaryParts(message)
  return parts.prefix + parts.command + parts.suffix
}

/**
 * Extracts the command from a pkexec message.
 * @param {?string} message - the polkit request message
 * @returns {string} the command, or "" when it is not a pkexec message
 */
function commandFromMessage(message) {
  var parsed = parsePkexec(message)
  return parsed ? parsed.command : ""
}

/**
 * Shortens text to at most `max` characters by replacing its middle with "…".
 * @param {?string} text - the text to shorten
 * @param {?number} max - the maximum length; 0 or missing means 64, values below 5 become 5
 * @returns {string} the text, shortened when longer than the limit
 */
function shortenMiddle(text, max) {
  var s = String(text || "")
  var limit = Math.max(5, max || 64)
  if (s.length <= limit) return s
  var keep = limit - 1
  var head = Math.ceil(keep / 2)
  return s.slice(0, head) + "…" + s.slice(s.length - (keep - head))
}

/**
 * Escapes &, <, > and " so the text is shown literally in StyledText.
 * @param {*} text - the value to escape; falsy values give ""
 * @returns {string} the escaped text
 */
function escapeHtml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

// StyledText for the request line: the command in the accent colour, every
// piece of polkit-supplied text escaped so it is shown, never interpreted.
/**
 * Builds the StyledText request line with the (middle-shortened) command wrapped in an accent-coloured font tag.
 * @param {?string} message - the polkit request message
 * @param {string} accent - the accent colour as a string, e.g. "#ff00aa"
 * @returns {string} the escaped StyledText markup
 */
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

/**
 * Tells whether a polkit action id is safe to pass to pkaction: 1 to 255 characters of letters, digits, ".", "_" or "-".
 * @param {*} id - the action id; null and undefined are invalid
 * @returns {boolean} true when the id is valid
 */
function validActionId(id) {
  var s = id === undefined || id === null ? "" : String(id)
  return s.length >= 1 && s.length <= 255 && /^[A-Za-z0-9._-]+$/.test(s)
}

/**
 * Reads the first `description:` and `vendor:` values from `pkaction --verbose` output.
 * @param {?string} text - the pkaction output
 * @returns {{[key: string]: string}} `description` and `vendor` keys, "" when missing
 */
function parseActionInfo(text) {
  /** @type {{[key: string]: string}} */
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
/**
 * Returns the display name of a polkit identity, falling back to its string form (e.g. "unix-user:tim").
 * @param {?PolkitIdentity} identity - the identity; null gives ""
 * @returns {string} the label, trimmed
 */
function identityLabel(identity) {
  if (!identity) return ""
  var name = String(identity.displayName || "").trim()
  if (name) return name
  return String(identity.string || "").trim()
}

/**
 * Finds the position of the selected identity in the list by identity (===).
 * @param {?Array<*>} identities - the flow's identities
 * @param {*} selected - the selected identity
 * @returns {number} its index, or -1 when either is missing or it is not in the list
 */
function indexOfIdentity(identities, selected) {
  if (!identities || !selected) return -1
  for (var i = 0; i < identities.length; i++) {
    if (identities[i] === selected) return i
  }
  return -1
}

/**
 * Builds the " (n of m)" suffix for the selected identity; empty with fewer than two identities or no match.
 * @param {?Array<*>} identities - the flow's identities
 * @param {*} selected - the selected identity
 * @returns {string} the suffix, or ""
 */
function identityPosition(identities, selected) {
  var count = identities ? identities.length : 0
  if (count < 2) return ""
  var index = indexOfIdentity(identities, selected)
  return index < 0 ? "" : " (" + (index + 1) + " of " + count + ")"
}

/**
 * Returns the index of the next identity, wrapping around; starts at 0 when nothing is selected.
 * @param {number} count - the number of identities
 * @param {number} current - the current index, or -1 for none
 * @returns {number} the next index, or -1 when count is below 1
 */
function nextIdentityIndex(count, current) {
  if (count < 1) return -1
  return current < 0 ? 0 : (current + 1) % count
}

/**
 * Joins the action description and "as <identity><position>" with " · ", skipping empty parts.
 * @param {?string} description - the polkit action's description
 * @param {?string} identity - the identity label
 * @param {?string} position - the " (n of m)" suffix, or ""
 * @returns {string} the context line, "" when both description and identity are empty
 */
function contextLine(description, identity, position) {
  var parts = []
  if (description) parts.push(description)
  if (identity) parts.push("as " + identity + (position || ""))
  return parts.join(" · ")
}

/**
 * Builds the details rows (ACTION, VENDOR, COMMAND, MESSAGE), leaving out empty values.
 * @param {?string} actionId - the polkit action id
 * @param {?string} vendor - the action's vendor from pkaction
 * @param {?string} command - the pkexec command
 * @param {?string} message - the polkit request message
 * @returns {Array<{key: string, value: string}>} the non-empty rows in that order
 */
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

/**
 * Turns a PAM prompt into the password field placeholder: trailing colon removed, "Enter password" for empty or "Password".
 * @param {?string} prompt - the PAM input prompt
 * @returns {string} the placeholder text
 */
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
