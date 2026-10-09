// Authoritative owner snapshots projected into typed desktop action records.

/**
 * Creates a normalized action identity without deriving instructions from labels.
 * @param {string} id - opaque action identity
 * @param {string} label - primary action label
 * @param {string} detail - current observed context
 * @param {Array<string>} aliases - stable search terms
 * @returns {object} typed search record
 */
function actionRecord(id, label, detail, aliases) {
  return {
    key: "action:" + id,
    type: "action",
    label: label,
    detail: detail,
    aliases: aliases,
    target: { actionId: id },
    available: true
  }
}

/**
 * Projects only capabilities and targets that their current owners can identify.
 * @param {*} snapshot - current notification, audio and wallpaper snapshots
 * @returns {Array<*>} selectable action records
 */
function actionRecords(snapshot) {
  var data = snapshot || {}
  var rows = []
  var dnd = data.dnd
  if (dnd && dnd.available === true && typeof dnd.enabled === "boolean") {
    rows.push(
      actionRecord(
        "dnd",
        (dnd.enabled ? "Disable" : "Enable") + " Do not disturb",
        (dnd.enabled ? "On" : "Off") + (dnd.quietHours ? " · Quiet hours active" : ""),
        ["dnd", "notifications", "do not disturb"]
      )
    )
  }
  var audio = data.audio
  /** @type {Array<*>} */
  var outputs =
    audio && audio.available === true && Array.isArray(audio.outputs) ? audio.outputs : []
  outputs.forEach(function (output) {
    if (
      !output ||
      typeof output.key !== "string" ||
      !output.key.trim() ||
      typeof output.label !== "string" ||
      !output.label.trim()
    )
      return
    rows.push(
      actionRecord(
        "audio:" + output.key,
        "Use " + output.label,
        output.current ? "Current audio output" : "Set audio output",
        ["audio", "output", output.label]
      )
    )
  })
  var wallpaper = data.wallpaper
  /** @type {Array<*>} */
  var choices =
    wallpaper && wallpaper.available === true && Array.isArray(wallpaper.choices)
      ? wallpaper.choices
      : []
  choices.forEach(function (choice) {
    if (
      !choice ||
      choice.available !== true ||
      typeof choice.id !== "string" ||
      !choice.id.trim() ||
      typeof choice.label !== "string" ||
      !choice.label.trim()
    )
      return
    rows.push(
      actionRecord(
        "wallpaper:" + choice.id,
        "Use " + choice.label + " wallpaper",
        (wallpaper.activeId === choice.id ? "Current wallpaper" : "Set wallpaper") +
          (wallpaper.scheduled ? " · Schedule active" : ""),
        ["wallpaper", choice.id, choice.label]
      )
    )
  })
  return rows
}

if (typeof module !== "undefined") module.exports = { actionRecords: actionRecords }
