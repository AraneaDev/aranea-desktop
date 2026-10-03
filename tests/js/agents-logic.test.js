// Logic contract for AgentsLogic.js: the bar ring's fraction and tone, the
// provider/day/model keys, the Refresh pill's pending state and the
// header's "plan · updated HH:MM" caption. Run with `node --test tests/js/`
// (tools/check runs it with coverage).
process.env.TZ = "Europe/Amsterdam"

const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.agents/AgentsLogic.js"))

// --- ringFraction --------------------------------------------------------------------

test("ringFraction: -1 with no limits at all", () => {
  assert.equal(logic.ringFraction([]), -1)
  assert.equal(logic.ringFraction(null), -1)
  assert.equal(logic.ringFraction(undefined), -1)
})

test("ringFraction: the highest percent among the windows, as a 0..1 fraction", () => {
  assert.equal(logic.ringFraction([{ percent: 0.42 }]), 0.42)
  assert.equal(logic.ringFraction([{ percent: 0.1 }, { percent: 0.73 }, { percent: 0.3 }]), 0.73)
})

test("ringFraction: a 0..100 percent is rescaled to 0..1", () => {
  assert.equal(logic.ringFraction([{ percent: 42 }]), 0.42)
  assert.equal(logic.ringFraction([{ percent: 8 }, { percent: 95 }]), 0.95)
})

test("ringFraction: a bare fraction of exactly 1 is not rescaled (it is already full)", () => {
  assert.equal(logic.ringFraction([{ percent: 1 }]), 1)
})

test("ringFraction: an alternate `used` field is read when `percent` is absent", () => {
  assert.equal(logic.ringFraction([{ used: 0.6 }]), 0.6)
  assert.equal(logic.ringFraction([{ used: 60 }]), 0.6)
})

test("ringFraction: `percent` wins over `used` when both are present", () => {
  assert.equal(logic.ringFraction([{ percent: 0.2, used: 0.9 }]), 0.2)
})

test("ringFraction: broken entries (negative, non-numeric, missing field) are ignored, not thrown", () => {
  assert.equal(logic.ringFraction([{ percent: -1 }]), -1)
  assert.equal(logic.ringFraction([{ percent: "nope" }]), -1)
  assert.equal(logic.ringFraction([{}]), -1)
  assert.equal(logic.ringFraction([null, undefined, { percent: 0.5 }]), 0.5)
  assert.equal(logic.ringFraction("not an array"), -1)
})

test("ringFraction: never exceeds 1 even when a window is reported over its cap", () => {
  assert.equal(logic.ringFraction([{ percent: 150 }]), 1)
})

// --- ringTone --------------------------------------------------------------------------

test("ringTone: none with no limits (-1) or any other negative", () => {
  assert.equal(logic.ringTone(-1), "none")
  assert.equal(logic.ringTone(-0.5), "none")
  assert.equal(logic.ringTone(NaN), "none")
})

test("ringTone: accent below 0.8", () => {
  assert.equal(logic.ringTone(0), "accent")
  assert.equal(logic.ringTone(0.5), "accent")
  assert.equal(logic.ringTone(0.79), "accent")
})

test("ringTone: attention from 0.8, up to (not including) 0.95", () => {
  assert.equal(logic.ringTone(0.8), "attention")
  assert.equal(logic.ringTone(0.9), "attention")
  assert.equal(logic.ringTone(0.9499), "attention")
})

test("ringTone: urgent from 0.95", () => {
  assert.equal(logic.ringTone(0.95), "urgent")
  assert.equal(logic.ringTone(1), "urgent")
  assert.equal(logic.ringTone(1.5), "urgent")
})

// --- providerKey / dayKey / modelKey ----------------------------------------------------

test("providerKey: the provider's providerId", () => {
  assert.equal(logic.providerKey({ providerId: "claude" }), "claude")
  assert.equal(logic.providerKey({ providerId: "codex" }), "codex")
})

test("providerKey: '' for broken input", () => {
  assert.equal(logic.providerKey(null), "")
  assert.equal(logic.providerKey(undefined), "")
  assert.equal(logic.providerKey({}), "")
})

test("dayKey: the row's date", () => {
  assert.equal(logic.dayKey({ date: "2026-10-04" }), "2026-10-04")
})

test("dayKey: '' for broken input", () => {
  assert.equal(logic.dayKey(null), "")
  assert.equal(logic.dayKey({}), "")
})

test("modelKey: the row's name", () => {
  assert.equal(logic.modelKey({ name: "Claude Opus" }), "Claude Opus")
})

test("modelKey: '' for broken input", () => {
  assert.equal(logic.modelKey(null), "")
  assert.equal(logic.modelKey({}), "")
})

// --- refresh pending -------------------------------------------------------------------

test("refreshIdle: nothing in flight, no baseline revision", () => {
  assert.deepEqual(logic.refreshIdle(), { busy: false, startedAt: 0, revision: null })
})

test("refreshClick: idle starts a refresh and freezes the baseline revision", () => {
  var idle = { busy: false, startedAt: 0, revision: 3 }
  var r = logic.refreshClick(idle, 1000)
  assert.deepEqual(r, { state: { busy: true, startedAt: 1000, revision: 3 }, send: true })
})

test("refreshClick: null state counts as idle", () => {
  var r = logic.refreshClick(null, 500)
  assert.deepEqual(r, { state: { busy: true, startedAt: 500, revision: null }, send: true })
})

test("refreshClick: busy ignores the click (no second refreshNow)", () => {
  var busy = { busy: true, startedAt: 1000, revision: 3 }
  var r = logic.refreshClick(busy, 2000)
  assert.deepEqual(r, { state: busy, send: false })
})

test("refreshLanded: busy, a revision that differs from the baseline lands (goes idle)", () => {
  var busy = { busy: true, startedAt: 1000, revision: 3 }
  assert.deepEqual(logic.refreshLanded(busy, 4), { busy: false, startedAt: 0, revision: 4 })
})

test("refreshLanded: busy, the same revision as the baseline is still in flight (unchanged)", () => {
  var busy = { busy: true, startedAt: 1000, revision: 3 }
  assert.deepEqual(logic.refreshLanded(busy, 3), busy)
})

test("refreshLanded: busy with no baseline yet lands on the first revision seen", () => {
  var busy = { busy: true, startedAt: 1000, revision: null }
  assert.deepEqual(logic.refreshLanded(busy, 7), { busy: false, startedAt: 0, revision: 7 })
})

test("refreshLanded: idle keeps the baseline current for the next click", () => {
  var idle = logic.refreshIdle()
  assert.deepEqual(logic.refreshLanded(idle, 9), { busy: false, startedAt: 0, revision: 9 })
})

test("refreshLanded: null state counts as idle", () => {
  assert.deepEqual(logic.refreshLanded(null, 2), { busy: false, startedAt: 0, revision: 2 })
})

test("refreshLanded: a non-finite revision is ignored (state unchanged)", () => {
  var busy = { busy: true, startedAt: 1000, revision: 3 }
  assert.deepEqual(logic.refreshLanded(busy, NaN), busy)
  assert.deepEqual(logic.refreshLanded(busy, "nope"), busy)
})

test("refreshTimeout: busy, under the timeout stays busy", () => {
  var busy = { busy: true, startedAt: 1000, revision: 3 }
  assert.deepEqual(logic.refreshTimeout(busy, 1000 + 29999, 30000), busy)
})

test("refreshTimeout: busy, at or past the timeout stops the pill (keeps the baseline)", () => {
  var busy = { busy: true, startedAt: 1000, revision: 3 }
  assert.deepEqual(logic.refreshTimeout(busy, 1000 + 30000, 30000), {
    busy: false,
    startedAt: 0,
    revision: 3
  })
  assert.deepEqual(logic.refreshTimeout(busy, 1000 + 45000, 30000), {
    busy: false,
    startedAt: 0,
    revision: 3
  })
})

test("refreshTimeout: idle is unaffected", () => {
  var idle = logic.refreshIdle()
  assert.deepEqual(logic.refreshTimeout(idle, 999999, 30000), idle)
})

test("refreshTimeout: null state counts as idle", () => {
  assert.deepEqual(logic.refreshTimeout(null, 999999, 30000), logic.refreshIdle())
})

test("refresh pending: a full click/land cycle, then a second click", () => {
  var state = logic.refreshIdle()
  state = logic.refreshLanded(state, 1) // first scan already landed once, baseline = 1
  var clicked = logic.refreshClick(state, 10000)
  assert.equal(clicked.send, true)
  state = clicked.state
  assert.equal(state.busy, true)
  // A watcher firing on an unrelated change does not end the busy pill.
  state = logic.refreshLanded(state, 1)
  assert.equal(state.busy, true)
  // The real refresh lands with a new revision.
  state = logic.refreshLanded(state, 2)
  assert.equal(state.busy, false)
  assert.equal(state.revision, 2)
  // Busy again: a second click while this one is in flight is ignored.
  var again = logic.refreshClick(state, 20000)
  assert.equal(again.send, true)
  var ignored = logic.refreshClick(again.state, 20001)
  assert.deepEqual(ignored, { state: again.state, send: false })
})

// --- updatedCaption --------------------------------------------------------------------

test("updatedCaption: plan and time together", () => {
  var ms = new Date(2026, 9, 4, 23, 58, 0).getTime()
  assert.equal(logic.updatedCaption("Max 20x", ms), "Max 20x · updated 23:58")
})

test("updatedCaption: pads single-digit hours and minutes", () => {
  var ms = new Date(2026, 9, 4, 1, 5, 0).getTime()
  assert.equal(logic.updatedCaption("Pro", ms), "Pro · updated 01:05")
})

test("updatedCaption: no plan leaves just the updated half", () => {
  var ms = new Date(2026, 9, 4, 23, 58, 0).getTime()
  assert.equal(logic.updatedCaption("", ms), "updated 23:58")
  assert.equal(logic.updatedCaption(null, ms), "updated 23:58")
})

test("updatedCaption: no valid timestamp leaves just the plan", () => {
  assert.equal(logic.updatedCaption("Max 20x", 0), "Max 20x")
  assert.equal(logic.updatedCaption("Max 20x", -1), "Max 20x")
  assert.equal(logic.updatedCaption("Max 20x", NaN), "Max 20x")
  assert.equal(logic.updatedCaption("Max 20x", undefined), "Max 20x")
})

test("updatedCaption: both missing is ''", () => {
  assert.equal(logic.updatedCaption("", 0), "")
  assert.equal(logic.updatedCaption(null, null), "")
})
