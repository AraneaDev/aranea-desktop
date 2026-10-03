// Pure rules for the Aranea Agents dropdown (Panel.qml): the bar ring's
// fraction and tone, the keys that keep provider chips, day rows and model
// rows stable across a refresh, the Refresh pill's pending state, and the
// header's "plan · updated HH:MM" caption. No QML, no I/O, no
// `Date.now()` (every "now" is passed in explicitly); tests/js/agents-logic.test.js
// runs this under Node.
//
// Field names follow stock's omarchy.agents Panel.qml and Main.qml: a
// provider's `limits` are `{label, percent, resetsAt, title}` with `percent`
// already a 0..1 fraction (`alarming: headline.percent >= 0.9`, displayed as
// `Math.round(percent * 100) + "%"`), a provider is keyed by `providerId`, a
// day row (from `recentDays`) by `date`, and a model row (from `modelRows`)
// by `name`.

/**
 * A stock limit window, or anything close enough: the field that carries how
 * much of the window is used may be named `percent` (stock's name) or `used`
 * (an alternate a caller might pass), and may already be a 0..1 fraction or
 * a 0..100 percentage.
 * @typedef {{percent?: number, used?: number}} LimitLike
 */

/**
 * The bar ring's fill: the highest fraction used across a provider's limit
 * windows (session, weekly, ...), so the ring tracks whichever window is
 * closest to stopping the next prompt. Entries missing both `percent` and
 * `used`, or carrying a non-finite value, are ignored; a 0..100 value is
 * rescaled to 0..1 to tolerate either shape.
 * @param {Array<LimitLike>} limits - a provider's limit windows
 * @returns {number} the max fraction used (0..1), or -1 with no usable limits
 */
function ringFraction(limits) {
  var list = Array.isArray(limits) ? limits : []
  var best = -1
  for (var i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    var raw = entry.percent !== undefined ? entry.percent : entry.used
    var value = Number(raw)
    if (!isFinite(value) || value < 0) continue
    var fraction = value > 1 ? value / 100 : value
    if (fraction > best) best = fraction
  }
  return best < 0 ? -1 : Math.min(1, best)
}

/**
 * The bar ring's colour, banded the way Health tones its warning levels:
 * the accent below 80%, amber from 80%, urgent from 95%. No ring at all
 * (`ringFraction`'s -1) draws nothing.
 * @param {number} f - the ring's fraction (`ringFraction`'s return)
 * @returns {string} "none", "accent", "attention" or "urgent"
 */
function ringTone(f) {
  var value = Number(f)
  if (!isFinite(value) || value < 0) return "none"
  if (value < 0.8) return "accent"
  if (value < 0.95) return "attention"
  return "urgent"
}

/**
 * A provider's stable key, for the subscription switch's FilamentPills:
 * stock's `providerId`, which survives a refresh even when the provider
 * list is rebuilt.
 * @param {*} p - a provider (stock's displayProvider shape)
 * @returns {string} the provider's id, or "" when it has none
 */
function providerKey(p) {
  return p && p.providerId !== undefined && p.providerId !== null ? String(p.providerId) : ""
}

/**
 * A tokens-by-day row's stable key: stock's `date` (an ISO calendar date,
 * e.g. "2026-10-04"), from `recentDays`.
 * @param {*} d - a day row
 * @returns {string} the day's date, or "" when it has none
 */
function dayKey(d) {
  return d && d.date !== undefined && d.date !== null ? String(d.date) : ""
}

/**
 * A tokens-by-model row's stable key: stock's `name` (the friendly model
 * name `modelRows` already resolved), since the row carries no id.
 * @param {*} m - a model row
 * @returns {string} the model's name, or "" when it has none
 */
function modelKey(m) {
  return m && m.name !== undefined && m.name !== null ? String(m.name) : ""
}

/**
 * The Refresh pill's pending state: `busy` while a refresh is in flight,
 * `startedAt` the click's timestamp (0 when idle, for the 30s timeout), and
 * `revision` the last provider revision this state has accounted for (the
 * busy click's baseline to compare a landing against; kept current while
 * idle so the next click always has a fresh baseline).
 * @typedef {{busy: boolean, startedAt: number, revision: ?number}} RefreshPending
 */

/**
 * The idle Refresh state: nothing in flight, no baseline revision yet.
 * @returns {RefreshPending} a fresh idle state
 */
function refreshIdle() {
  return { busy: false, startedAt: 0, revision: null }
}

/**
 * A click on the Refresh pill (or `r`, or Enter). Idle, it starts a refresh
 * at once, freezing the current baseline revision so a later landing can
 * tell a real change from the one already on screen. Busy, the click is
 * ignored: stock's `refreshNow` is not called again until this one lands or
 * times out.
 * @param {?RefreshPending} state - the pending state (null counts as idle)
 * @param {number} nowMs - the click's timestamp
 * @returns {{state: RefreshPending, send: boolean}} the next state, and whether to call refreshNow()
 */
function refreshClick(state, nowMs) {
  var s = state || refreshIdle()
  if (s.busy) return { state: s, send: false }
  var revision = s.revision !== undefined ? s.revision : null
  return { state: { busy: true, startedAt: Number(nowMs) || 0, revision: revision }, send: true }
}

/**
 * The provider revision changed (or was read back, busy or not). Busy, a
 * revision that differs from the baseline (or no baseline yet) means the
 * refresh landed, so the pill goes idle with the new revision as its next
 * baseline; the same revision as the baseline means the refresh is still in
 * flight (a watcher firing on something else), so the state is unchanged.
 * Idle, the revision only refreshes the baseline for the next click.
 * @param {?RefreshPending} state - the pending state (null counts as idle)
 * @param {number} revision - the provider revision just observed
 * @returns {RefreshPending} the next state
 */
function refreshLanded(state, revision) {
  var s = state || refreshIdle()
  var r = Number(revision)
  if (!isFinite(r)) return s
  if (!s.busy) return { busy: false, startedAt: 0, revision: r }
  if (s.revision === null || s.revision === undefined || r !== s.revision)
    return { busy: false, startedAt: 0, revision: r }
  return s
}

/**
 * Whether every shown agent's record has been rewritten since a refresh
 * started, so the pill waits for the whole refresh instead of stopping at
 * the first record a fast collector writes. Busy, the panel only offers a
 * revision to `refreshLanded` once this holds. A record without a usable
 * write time (0, negative or not a number, e.g. a synced-only agent with no
 * local record) cannot be waited on and is skipped.
 * @param {Array<number>} updatedMs - each shown agent's record write time (ms)
 * @param {number} startedAt - the refresh's start (RefreshPending.startedAt)
 * @returns {boolean} true when no usable write time predates startedAt
 */
function recordsLandedSince(updatedMs, startedAt) {
  var list = Array.isArray(updatedMs) ? updatedMs : []
  var since = Number(startedAt) || 0
  for (var i = 0; i < list.length; i++) {
    var ms = Number(list[i])
    if (isFinite(ms) && ms > 0 && ms < since) return false
  }
  return true
}

/**
 * A refresh that never lands: once `timeoutMs` have passed since the click,
 * the pill stops pulsing and shows the last data instead of waiting
 * forever. The baseline revision is kept as it was, since nothing proved it
 * changed.
 * @param {?RefreshPending} state - the pending state (null counts as idle)
 * @param {number} nowMs - the current timestamp
 * @param {number} timeoutMs - how long to wait before giving up (30000 in the panel)
 * @returns {RefreshPending} the next state
 */
function refreshTimeout(state, nowMs, timeoutMs) {
  var s = state || refreshIdle()
  if (!s.busy) return s
  var elapsed = (Number(nowMs) || 0) - (Number(s.startedAt) || 0)
  if (elapsed >= Number(timeoutMs)) return { busy: false, startedAt: 0, revision: s.revision }
  return s
}

/**
 * Zero-pads a two-digit time component.
 * @param {number} n - hours or minutes
 * @returns {string} a two-digit, zero-padded value
 */
function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

/**
 * The header's caption: the plan (stock's `heroMeta`, e.g. "Max 20x") and
 * when the data was last updated, e.g. "Max 20x · updated 23:58". Either
 * half may be missing: no plan leaves just the "updated" half, and no valid
 * timestamp leaves just the plan.
 * @param {string} plan - the plan text (stock's heroMeta), or "" when there is none
 * @param {number} updatedMs - when the data was last updated
 * @returns {string} the assembled caption
 */
function updatedCaption(plan, updatedMs) {
  var p = String(plan || "").trim()
  var ms = Number(updatedMs)
  var updated = ""
  if (isFinite(ms) && ms > 0) {
    var d = new Date(ms)
    updated = "updated " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  }
  if (p && updated) return p + " · " + updated
  return p || updated
}

if (typeof module !== "undefined")
  module.exports = {
    ringFraction: ringFraction,
    ringTone: ringTone,
    providerKey: providerKey,
    dayKey: dayKey,
    modelKey: modelKey,
    refreshIdle: refreshIdle,
    refreshClick: refreshClick,
    refreshLanded: refreshLanded,
    recordsLandedSince: recordsLandedSince,
    refreshTimeout: refreshTimeout,
    updatedCaption: updatedCaption
  }
