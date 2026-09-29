/*
 * Pure normalization helpers for clipboard entries. The QML facade keeps the
 * public API stable while this module owns the input-shape rules.
 */
/** @typedef {{type: string, text?: string, path?: string, mime?: string, capturedAt?: string, kind?: string, secret?: boolean, secretOverride?: boolean, pinned?: boolean, pinnedAtMs?: number, capturedAtMs?: number}} ClipboardEntry */
/**
 * Validates and reduces a raw clipboard value to its base entry shape.
 * @param {*} value - a raw string or parsed entry
 * @returns {?ClipboardEntry} the base entry, or null
 */
function normalizeBase(value) {
  if (typeof value === "string")
    return value.trim().length > 0 ? { type: "text", text: value } : null

  if (!value || typeof value !== "object") return null

  var type = String(value.type || value.kind || "")
  if (type === "text") {
    var text = String(value.text || "")
    return text.trim().length > 0 ? { type: "text", text: text } : null
  }

  if (type === "image") {
    var path = String(value.path || "")
    if (!path) return null
    /** @type {ClipboardEntry} */
    var entry = {
      type: "image",
      path: path,
      mime: String(value.mime || "image/png")
    }
    if (value.capturedAt !== undefined && value.capturedAt !== null)
      entry.capturedAt = String(value.capturedAt)
    return entry
  }

  return null
}

/**
 * Normalizes an entry while preserving supported Aranea metadata.
 * @param {*} value - a raw string or parsed entry
 * @returns {?ClipboardEntry} the normalized entry, or null
 */
function normalizeEntry(value) {
  var entry = normalizeBase(value)
  if (!entry || !value || typeof value !== "object") return entry
  if (typeof value.kind === "string") entry.kind = value.kind
  if (typeof value.secret === "boolean") entry.secret = value.secret
  if (typeof value.secretOverride === "boolean") entry.secretOverride = value.secretOverride
  if (typeof value.pinned === "boolean") entry.pinned = value.pinned
  var pinnedAt = Number(value.pinnedAtMs)
  if (value.pinnedAtMs !== undefined && value.pinnedAtMs !== null && isFinite(pinnedAt))
    entry.pinnedAtMs = pinnedAt
  var at = Number(value.capturedAtMs)
  if (value.capturedAtMs !== undefined && value.capturedAtMs !== null && isFinite(at))
    entry.capturedAtMs = at
  return entry
}

if (typeof module !== "undefined") {
  module.exports = { normalizeBase: normalizeBase, normalizeEntry: normalizeEntry }
}
