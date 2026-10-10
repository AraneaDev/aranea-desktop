// Type identity for desktop search rows without a supplied application icon.

/**
 * Names a desktop result type while leaving untyped menu rows unlabelled.
 * @param {string} type - normalized desktop type
 * @returns {string} short type label
 */
function typeLabel(type) {
  return (
    {
      app: "App",
      command: "Command",
      window: "Window",
      workspace: "Workspace",
      setting: "Setting",
      action: "Action",
      project: "Project"
    }[type] || ""
  )
}

/**
 * Supplies a dedicated-font glyph when a desktop result has no custom icon.
 * @param {string} type - normalized desktop type
 * @returns {string} glyph or an empty string for untyped rows
 */
function fallbackIcon(type) {
  /** @type {{[key: string]: number}} */
  var codes = {
    app: 0xf03a3,
    command: 0xf120,
    window: 0xf02d1,
    workspace: 0xf0099,
    setting: 0xf0493,
    action: 0xf0e7,
    project: 0xf024b
  }
  return codes[type] ? String.fromCodePoint(codes[type]) : ""
}

if (typeof module !== "undefined")
  module.exports = { typeLabel: typeLabel, fallbackIcon: fallbackIcon }
