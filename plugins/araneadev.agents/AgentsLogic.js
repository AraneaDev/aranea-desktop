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
 * `used`, or carrying a non-finite value, are ignored. A value in (1, 1.5]
 * is a fraction slightly over its cap (stock's percent is a 0..1 fraction
 * that a collector may report past 1) and counts as full; only a value
 * above 1.5 is read as a 0..100 percentage and rescaled. The panel clamps
 * its fractions to 0..1 before calling, so neither case reaches the ring
 * from stock data.
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
    var fraction = value > 1.5 ? value / 100 : value
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
 * `startedAt` the time records must be newer than to land it (the click, or
 * the start of a forced run that was queued behind another; 0 when idle),
 * `clickedAt` the click's timestamp (busy only; the 30s timeout counts from
 * it, so a rebase never extends the cap), and `revision` the last provider revision this state has accounted for (the
 * busy click's baseline to compare a landing against; kept current while
 * idle so the next click always has a fresh baseline).
 * @typedef {{busy: boolean, startedAt: number, clickedAt?: number, revision: ?number}} RefreshPending
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
  var now = Number(nowMs) || 0
  return { state: { busy: true, startedAt: now, clickedAt: now, revision: revision }, send: true }
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
 * A forced run that was queued behind another run has just started: records
 * written by the earlier run must not land it, so busy, the landing time
 * (`startedAt`) moves to now while `clickedAt` (the timeout's start) stays.
 * Idle, nothing changes.
 * @param {?RefreshPending} state - the pending state (null counts as idle)
 * @param {number} nowMs - the queued run's start
 * @returns {RefreshPending} the next state
 */
function refreshRebase(state, nowMs) {
  var s = state || refreshIdle()
  if (!s.busy) return s
  var clickedAt = s.clickedAt !== undefined ? s.clickedAt : s.startedAt
  return { busy: true, startedAt: Number(nowMs) || 0, clickedAt: clickedAt, revision: s.revision }
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
  var from = s.clickedAt !== undefined ? s.clickedAt : s.startedAt
  var elapsed = (Number(nowMs) || 0) - (Number(from) || 0)
  if (elapsed >= Number(timeoutMs)) return { busy: false, startedAt: 0, revision: s.revision }
  return s
}

/**
 * Abandons a pending refresh (the showcase taking over the dropdown): idle,
 * keeping the baseline revision so the next real refresh still has one.
 * @param {?RefreshPending} state - the pending state (null counts as idle)
 * @returns {RefreshPending} an idle state with the same revision
 */
function refreshCancel(state) {
  var s = state || refreshIdle()
  return { busy: false, startedAt: 0, revision: s.revision === undefined ? null : s.revision }
}

/**
 * The agent selection: the user's real choice, and the stand-in choice made
 * while a showcase is shown, kept apart so a capture never moves the real
 * one.
 * @typedef {{real: string, showcase: string}} AgentSelection
 */

/**
 * The provider id the dropdown shows as selected.
 * @param {AgentSelection} selection - both choices
 * @param {boolean} showcasing - a showcase is shown
 * @returns {string} the showcase choice while showcasing, else the real one
 */
function selectedId(selection, showcasing) {
  var sel = selection || { real: "", showcase: "" }
  return String((showcasing ? sel.showcase : sel.real) || "")
}

/**
 * Selects provider ID: while showcasing only the stand-in choice moves,
 * otherwise only the real one.
 * @param {AgentSelection} selection - both choices
 * @param {boolean} showcasing - a showcase is shown
 * @param {string} id - the provider id chosen
 * @returns {AgentSelection} the next selection
 */
function selectId(selection, showcasing, id) {
  var sel = selection || { real: "", showcase: "" }
  var real = String(sel.real || "")
  var showcase = String(sel.showcase || "")
  if (showcasing) return { real: real, showcase: String(id || "") }
  return { real: String(id || ""), showcase: showcase }
}

/**
 * Drops the stand-in choice (the showcase cleared on open or close); the
 * real choice is untouched.
 * @param {AgentSelection} selection - both choices
 * @returns {AgentSelection} the selection without a stand-in choice
 */
function showcaseSelectionCleared(selection) {
  var sel = selection || { real: "", showcase: "" }
  return { real: String(sel.real || ""), showcase: "" }
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

/**
 * A stand-in agent for README screenshots, as the `showcase` IPC method
 * takes it (see parseShowcase).
 * @typedef {{id: string, name: string, plan: string, updatedMinutesAgo: number,
 *   limits: Array<{label: string, percent: number, resetsInMinutes: number}>,
 *   days: Array<number>, models: Array<{id: string, input: number, output: number,
 *   cacheRead: number, cacheWrite: number}>, todayPrompts: number, todaySessions: number,
 *   balance?: {remaining: number, funded: number, spent: number, currency: string}}} ShowcaseAgent
 */

/**
 * Whether V is a finite number of at least 0.
 * @param {*} v - the value to test
 * @returns {boolean} true for a usable count or amount
 */
function isCount(v) {
  return typeof v === "number" && isFinite(v) && v >= 0
}

/**
 * Whether V is a non-empty string.
 * @param {*} v - the value to test
 * @returns {boolean} true for a usable label
 */
function isLabel(v) {
  return typeof v === "string" && v !== ""
}

/**
 * Whether V is a plain (non-array) object.
 * @param {*} v - the value to test
 * @returns {boolean} true for an object
 */
function isObject(v) {
  return !!v && typeof v === "object" && !Array.isArray(v)
}

/**
 * The local calendar date of MS as "YYYY-MM-DD" (stock's day key format).
 * @param {number} ms - a timestamp
 * @returns {string} the local date
 */
function localDate(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

/**
 * Whether A is a valid stand-in agent (ShowcaseAgent): a lower-case id
 * (it names the mark asset), name, plan, the minutes since its update,
 * limit windows with a 0..1 percent and the minutes to their reset, up to
 * 14 day counts (oldest first, the last one today), models with their
 * token split, today's prompt and session counts, and an optional prepaid
 * balance.
 * @param {*} a - one entry of the showcase's "agents"
 * @returns {boolean} true when every field is usable
 */
function validShowcaseAgent(a) {
  if (!isObject(a)) return false
  if (typeof a.id !== "string" || !/^[a-z0-9-]+$/.test(a.id)) return false
  if (!isLabel(a.name) || typeof a.plan !== "string" || !isCount(a.updatedMinutesAgo)) return false
  if (!isCount(a.todayPrompts) || !isCount(a.todaySessions)) return false
  if (!Array.isArray(a.limits) || !Array.isArray(a.days) || !Array.isArray(a.models)) return false
  if (a.days.length > 14 || !a.days.every(isCount)) return false
  var limitsOk = a.limits.every(function (/** @type {any} */ l) {
    return (
      isObject(l) &&
      isLabel(l.label) &&
      isCount(l.percent) &&
      l.percent <= 1 &&
      isCount(l.resetsInMinutes)
    )
  })
  var modelsOk = a.models.every(function (/** @type {any} */ m) {
    return (
      isObject(m) &&
      isLabel(m.id) &&
      isCount(m.input) &&
      isCount(m.output) &&
      isCount(m.cacheRead) &&
      isCount(m.cacheWrite)
    )
  })
  if (!limitsOk || !modelsOk) return false
  if (a.balance === undefined) return true
  var b = a.balance
  return (
    isObject(b) &&
    isCount(b.remaining) &&
    isCount(b.funded) &&
    isCount(b.spent) &&
    typeof b.currency === "string" &&
    /^[A-Z]{3}$/.test(b.currency)
  )
}

/**
 * The display record Main's displayProvider would build for stand-in agent
 * A, with its reset times, days and update time placed relative to NOWMS.
 * @param {ShowcaseAgent} a - a valid stand-in agent
 * @param {number} nowMs - the current timestamp
 * @returns {object} the provider record the panel draws
 */
function showcaseProvider(a, nowMs) {
  /** @type {{[key: string]: object}} */
  var modelUsage = {}
  a.models.forEach(function (m) {
    modelUsage[m.id] = {
      inputTokens: m.input,
      outputTokens: m.output,
      cacheReadInputTokens: m.cacheRead,
      cacheCreationInputTokens: m.cacheWrite
    }
  })
  var dayMs = 24 * 3600 * 1000
  return {
    providerId: a.id,
    providerName: a.name,
    ready: true,
    usageStatusText: "",
    authHelpText: "",
    limits: a.limits.map(function (l) {
      return {
        label: l.label,
        percent: l.percent,
        resetsAt: new Date(nowMs + l.resetsInMinutes * 60000).toISOString()
      }
    }),
    tierLabel: a.plan,
    balance: a.balance
      ? {
          remaining: a.balance.remaining,
          funded: a.balance.funded,
          spent: a.balance.spent,
          currency: a.balance.currency,
          estimated: false
        }
      : null,
    todayPrompts: a.todayPrompts,
    todaySessions: a.todaySessions,
    recentDays: a.days.map(function (count, i) {
      return { date: localDate(nowMs - (a.days.length - 1 - i) * dayMs), messageCount: count }
    }),
    modelUsage: modelUsage,
    hasPromptStats: true,
    syncEnabled: false,
    syncDeviceCount: 0,
    showcaseUpdatedMs: nowMs - a.updatedMinutesAgo * 60000
  }
}

/**
 * Reads the stand-ins handed to the `showcase` IPC method: a JSON object
 * whose "agents" is a non-empty array (at most 6) of valid stand-in agents
 * with distinct ids (validShowcaseAgent). Anything else is refused, so a
 * capture never falls back to the real usage.
 * @param {string|undefined} json - the call's JSON
 * @param {number} nowMs - the current timestamp
 * @returns {Array<object>|null} the stand-in provider records, or null when invalid
 */
function parseShowcase(json, nowMs) {
  var parsed
  try {
    parsed = JSON.parse(String(json))
  } catch (e) {
    return null
  }
  if (!isObject(parsed) || !Array.isArray(parsed.agents)) return null
  var agents = parsed.agents
  if (agents.length === 0 || agents.length > 6 || !agents.every(validShowcaseAgent)) return null
  var ids = agents.map(function (/** @type {any} */ a) {
    return a.id
  })
  if (
    ids.some(function (/** @type {string} */ id, /** @type {number} */ i) {
      return ids.indexOf(id) !== i
    })
  )
    return null
  var now = Number(nowMs) || 0
  return agents.map(function (/** @type {ShowcaseAgent} */ a) {
    return showcaseProvider(a, now)
  })
}

/**
 * The answer to a `showcase` IPC call. Stand-ins are taken only while the
 * dropdown is open (it clears them on open and on close).
 * @param {boolean} opened - the dropdown is open
 * @param {string|undefined} json - the call's JSON
 * @param {number} nowMs - the current timestamp
 * @returns {{answer: string, showcase: Array<object>|null}} "ok" with the
 *   stand-in providers, or "closed" / "invalid" with null
 */
function showcaseCall(opened, json, nowMs) {
  if (!opened) return { answer: "closed", showcase: null }
  var showcase = parseShowcase(json, nowMs)
  return showcase === null
    ? { answer: "invalid", showcase: null }
    : { answer: "ok", showcase: showcase }
}

/**
 * The view's keyboard cursor. Enter refreshes, so the outline always sits
 * on the Refresh pill, whatever agent h/l picks.
 * @param {boolean} shown - whether the keyboard shows the cursor
 * @returns {{active: boolean, section: string, index: number}} the cursor
 */
function cursorView(shown) {
  return { active: !!shown, section: "refresh", index: 0 }
}

/**
 * The key hint under the dropdown: the agent switch when there is more
 * than one agent, then Enter's refresh and the scroll keys.
 * @param {number} providerCount - how many agents show
 * @returns {string} the hint
 */
function keyHint(providerCount) {
  var parts = []
  if ((Number(providerCount) || 0) > 1) parts.push("h/l agent")
  parts.push("enter refresh", String.fromCodePoint(0x2191, 0x2193) + " scroll")
  return parts.join(" " + String.fromCodePoint(0xb7) + " ")
}

if (typeof module !== "undefined")
  module.exports = {
    cursorView: cursorView,
    keyHint: keyHint,
    ringFraction: ringFraction,
    ringTone: ringTone,
    providerKey: providerKey,
    dayKey: dayKey,
    modelKey: modelKey,
    refreshIdle: refreshIdle,
    refreshClick: refreshClick,
    refreshLanded: refreshLanded,
    recordsLandedSince: recordsLandedSince,
    refreshRebase: refreshRebase,
    refreshTimeout: refreshTimeout,
    refreshCancel: refreshCancel,
    selectedId: selectedId,
    selectId: selectId,
    showcaseSelectionCleared: showcaseSelectionCleared,
    updatedCaption: updatedCaption,
    parseShowcase: parseShowcase,
    showcaseCall: showcaseCall
  }
