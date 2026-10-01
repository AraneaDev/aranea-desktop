// Shared click-settling rule for the Filament dropdowns: a pointer click on
// a control that was just created, or that a layout shift just moved under
// a still pointer, is refused until the pointer really moves onto it or
// 300 ms pass. Kept apart from CursorLogic.js so the Network logic facade
// doesn't carry it. No QML, no I/O; tests/js/click-settle.test.js runs this
// under Node.

/**
 * Whether a pointer click may land on a control. It is refused within
 * `settleMs` of the control being created (or a prompt opening) and within
 * `settleMs` of its dropdown's layout last shifting (a section growing, a
 * prompt opening, a scroll), because either can put the control under a
 * pointer aimed at another one. A real pointer move onto the control
 * (`movedAt`, from a PointerMoveGate) after the event lifts that guard; a
 * move in the same millisecond does not. Missing input is refused.
 * @param {{now: number, createdAt?: number, movedAt?: number, layoutChangedAt?: number, settleMs?: number}|null|undefined} times - Date.now() values in ms; 0 or missing means never
 * @returns {boolean} true when the click may act
 */
function clickSettled(times) {
  if (!times || typeof times !== "object") return false
  var now = Number(times.now)
  if (!isFinite(now)) return false
  var settle =
    times.settleMs !== null && isFinite(Number(times.settleMs)) ? Number(times.settleMs) : 300
  var moved = Number(times.movedAt) || 0
  return (
    settledSince(times.createdAt, now, moved, settle) &&
    settledSince(times.layoutChangedAt, now, moved, settle)
  )
}

/**
 * Whether a click at `now` is past an event at `at`: the event never
 * happened (0 or missing), happened `settle` ms ago or more, or the pointer
 * really moved onto the control after it.
 * @param {number|null|undefined} at - when the event happened (Date.now()), 0 for never
 * @param {number} now - when the click happened
 * @param {number} moved - when the pointer last really moved onto the control, 0 for never
 * @param {number} settle - how long the event holds clicks off, in ms
 * @returns {boolean} true when the event no longer holds the click off
 */
function settledSince(at, now, moved, settle) {
  var when = Number(at) || 0
  return when <= 0 || now - when >= settle || moved > when
}

if (typeof module !== "undefined")
  module.exports = {
    clickSettled: clickSettled,
    settledSince: settledSince
  }
