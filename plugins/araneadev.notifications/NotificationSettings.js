// Pure persistence helpers for the notification service settings file.

/**
 * Reads the current DND preference and detects legacy history payloads.
 * @param {*} raw - contents of notifications.json
 * @returns {{error: boolean, dnd: ?boolean, legacy: boolean, errorMessage?: string}}
 */
function parseSettings(raw) {
  var text = String(raw || "").trim()
  if (!text) return { error: false, dnd: null, legacy: false }

  try {
    var parsed = JSON.parse(text)
    return {
      error: false,
      dnd: parsed && typeof parsed.dnd === "boolean" ? parsed.dnd : null,
      legacy: !!(parsed && (parsed.pending || parsed.past || parsed.entries))
    }
  } catch (e) {
    return { error: true, errorMessage: String(e), dnd: null, legacy: false }
  }
}

if (typeof module !== "undefined") module.exports = { parseSettings: parseSettings }
