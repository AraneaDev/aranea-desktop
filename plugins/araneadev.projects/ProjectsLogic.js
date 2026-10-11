/** Validate an optional opaque project details destination.
 * @param {unknown} value Requested identity.
 * @returns {string} Safe identity or the empty overview destination.
 */
function normalizeProjectId(value) {
  return typeof value === "string" && /^p-[A-Za-z0-9-]+$/.test(value) ? value : ""
}
/** Normalize a local file URL or an absolute editable folder path.
 * @param {string} value User-selected folder.
 * @returns {string} Absolute path or an empty invalid result.
 */
function normalizeFolder(value) {
  if (typeof value !== "string") return ""
  if (value.indexOf("file://") === 0) {
    if (!/^file:\/\/(localhost)?\//.test(value) || /[?#]/.test(value)) return ""
    try {
      value = decodeURIComponent(value.replace(/^file:\/\/(localhost)?/, ""))
    } catch (e) {
      return ""
    }
  }
  if (value.charAt(0) !== "/") return ""
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code <= 31 || code === 127) return ""
  }
  return value
}
/** Fit the standalone Projects window to the available logical screen.
 * @param {number} screenWidth Available width.
 * @param {number} screenHeight Available height.
 * @param {number} scale Host spacing scale.
 * @returns {object} Desired window geometry.
 */
function geometry(screenWidth, screenHeight, scale) {
  scale = scale || 1
  return {
    width: Math.max(1, Math.min(1080 * scale, screenWidth - 48 * scale)),
    height: Math.max(1, Math.min(720 * scale, screenHeight - 48 * scale))
  }
}
if (typeof module !== "undefined")
  module.exports = { normalizeProjectId, normalizeFolder, geometry }
