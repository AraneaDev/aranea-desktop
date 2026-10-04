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
  assert.deepEqual(r, {
    state: { busy: true, startedAt: 1000, clickedAt: 1000, revision: 3 },
    send: true
  })
})

test("refreshClick: null state counts as idle", () => {
  var r = logic.refreshClick(null, 500)
  assert.deepEqual(r, {
    state: { busy: true, startedAt: 500, clickedAt: 500, revision: null },
    send: true
  })
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

// --- recordsLandedSince ---------------------------------------------------------------

test("recordsLandedSince: false while any shown record predates the refresh", () => {
  assert.equal(logic.recordsLandedSince([2000, 900], 1000), false)
})

test("recordsLandedSince: true once every record is at or after the refresh", () => {
  assert.equal(logic.recordsLandedSince([1000, 2500], 1000), true)
})

test("recordsLandedSince: records without a usable write time are skipped", () => {
  assert.equal(logic.recordsLandedSince([0, -5, NaN, "x", 1500], 1000), true)
  assert.equal(logic.recordsLandedSince([], 1000), true)
  assert.equal(logic.recordsLandedSince(null, 1000), true)
})

test("recordsLandedSince: a missing start counts as 0, so everything landed", () => {
  assert.equal(logic.recordsLandedSince([5], undefined), true)
})

test("recordsLandedSince gates refreshLanded: a fast record alone keeps it busy", () => {
  let s = logic.refreshLanded(logic.refreshIdle(), 4)
  s = logic.refreshClick(s, 1000).state
  // The fast collector wrote; the slow one still holds its old time.
  const early = logic.recordsLandedSince([1200, 500], s.startedAt)
  assert.equal(early, false)
  // Both written: offering the revision now lands it.
  assert.equal(logic.recordsLandedSince([1200, 1800], s.startedAt), true)
  s = logic.refreshLanded(s, 6)
  assert.equal(s.busy, false)
})

// --- refreshRebase ----------------------------------------------------------------------

test("refreshRebase: busy moves the landing time to now and keeps the click time", () => {
  const busy = logic.refreshClick(logic.refreshLanded(logic.refreshIdle(), 3), 1000).state
  assert.deepEqual(logic.refreshRebase(busy, 6000), {
    busy: true,
    startedAt: 6000,
    clickedAt: 1000,
    revision: 3
  })
})

test("refreshRebase: a state without clickedAt takes startedAt as the click", () => {
  const busy = { busy: true, startedAt: 1000, revision: 3 }
  assert.deepEqual(logic.refreshRebase(busy, 6000), {
    busy: true,
    startedAt: 6000,
    clickedAt: 1000,
    revision: 3
  })
  assert.equal(logic.refreshRebase(busy, undefined).startedAt, 0)
})

test("refreshRebase: idle (or null) is unchanged", () => {
  const idle = { busy: false, startedAt: 0, revision: 2 }
  assert.deepEqual(logic.refreshRebase(idle, 6000), idle)
  assert.deepEqual(logic.refreshRebase(null, 6000), logic.refreshIdle())
})

test("refreshRebase: the earlier run's records no longer land it, and the cap still counts from the click", () => {
  let s = logic.refreshClick(logic.refreshLanded(logic.refreshIdle(), 3), 1000).state
  s = logic.refreshRebase(s, 8000)
  // Written by the earlier run (before the queued one started): not landed.
  assert.equal(logic.recordsLandedSince([7000, 7500], s.startedAt), false)
  assert.equal(logic.recordsLandedSince([8200, 9000], s.startedAt), true)
  // 30 s from the click, not from the rebase.
  assert.equal(logic.refreshTimeout(s, 30999, 30000).busy, true)
  assert.equal(logic.refreshTimeout(s, 31000, 30000).busy, false)
})

// --- showcase ---------------------------------------------------------------------------

/**
 * One valid stand-in agent; tests break one field at a time.
 * @param {object} [extra] - fields to override
 * @returns {object} the stand-in agent
 */
function standIn(extra) {
  return Object.assign(
    {
      id: "claude",
      name: "Claude Code",
      plan: "Pro",
      updatedMinutesAgo: 3,
      todayPrompts: 46,
      todaySessions: 5,
      limits: [{ label: "Session (5-hour)", percent: 0.42, resetsInMinutes: 134 }],
      days: [10, 20, 30],
      models: [{ id: "claude-sonnet-5", input: 1, output: 2, cacheRead: 3, cacheWrite: 4 }]
    },
    extra || {}
  )
}
const showcaseNow = new Date(2026, 9, 4, 12, 0, 0).getTime()

test("parseShowcase: builds the provider records the panel draws, relative to now", () => {
  const json = JSON.stringify({
    agents: [
      standIn(),
      standIn({
        id: "fireworks",
        name: "Fireworks",
        limits: [],
        balance: { remaining: 18.4, funded: 50, spent: 31.6, currency: "USD" }
      })
    ]
  })
  const out = logic.parseShowcase(json, showcaseNow)
  assert.equal(out.length, 2)
  const c = out[0]
  assert.equal(c.providerId, "claude")
  assert.equal(c.providerName, "Claude Code")
  assert.equal(c.tierLabel, "Pro")
  assert.equal(c.usageStatusText, "")
  assert.equal(c.balance, null)
  assert.deepEqual(c.limits, [
    {
      label: "Session (5-hour)",
      percent: 0.42,
      resetsAt: new Date(showcaseNow + 134 * 60000).toISOString()
    }
  ])
  // The last day is today, the ones before it count back.
  assert.deepEqual(c.recentDays, [
    { date: "2026-10-02", messageCount: 10 },
    { date: "2026-10-03", messageCount: 20 },
    { date: "2026-10-04", messageCount: 30 }
  ])
  assert.deepEqual(c.modelUsage, {
    "claude-sonnet-5": {
      inputTokens: 1,
      outputTokens: 2,
      cacheReadInputTokens: 3,
      cacheCreationInputTokens: 4
    }
  })
  assert.equal(c.showcaseUpdatedMs, showcaseNow - 3 * 60000)
  assert.equal(c.syncEnabled, false)
  assert.deepEqual(out[1].balance, {
    remaining: 18.4,
    funded: 50,
    spent: 31.6,
    currency: "USD",
    estimated: false
  })
})

test("parseShowcase: a missing now counts as 0", () => {
  const out = logic.parseShowcase(JSON.stringify({ agents: [standIn({ days: [] })] }), undefined)
  assert.equal(out[0].showcaseUpdatedMs, -180000)
})

test("parseShowcase: refuses anything but a well-formed stand-in list", () => {
  const bad = [
    undefined,
    "not json",
    "[]",
    "null",
    "{}",
    JSON.stringify({ agents: [] }),
    JSON.stringify({ agents: "x" }),
    JSON.stringify({
      agents: [standIn(), standIn(), standIn(), standIn(), standIn(), standIn(), standIn()]
    }),
    JSON.stringify({ agents: [standIn(), standIn()] }),
    JSON.stringify({ agents: [null] }),
    JSON.stringify({ agents: [standIn({ id: "Claude Code" })] }),
    JSON.stringify({ agents: [standIn({ id: 5 })] }),
    JSON.stringify({ agents: [standIn({ name: "" })] }),
    JSON.stringify({ agents: [standIn({ plan: 1 })] }),
    JSON.stringify({ agents: [standIn({ updatedMinutesAgo: -1 })] }),
    JSON.stringify({ agents: [standIn({ todayPrompts: "4" })] }),
    JSON.stringify({ agents: [standIn({ todaySessions: null })] }),
    JSON.stringify({ agents: [standIn({ limits: {} })] }),
    JSON.stringify({ agents: [standIn({ days: {} })] }),
    JSON.stringify({ agents: [standIn({ models: {} })] }),
    JSON.stringify({ agents: [standIn({ days: new Array(15).fill(1) })] }),
    JSON.stringify({ agents: [standIn({ days: [1, -2] })] }),
    JSON.stringify({
      agents: [standIn({ limits: [{ label: "S", percent: 1.2, resetsInMinutes: 1 }] })]
    }),
    JSON.stringify({
      agents: [standIn({ limits: [{ label: "", percent: 0.2, resetsInMinutes: 1 }] })]
    }),
    JSON.stringify({ agents: [standIn({ limits: [{ label: "S", percent: 0.2 }] })] }),
    JSON.stringify({ agents: [standIn({ limits: [[1]] })] }),
    JSON.stringify({
      agents: [standIn({ models: [{ id: "m", input: 1, output: 1, cacheRead: 1 }] })]
    }),
    JSON.stringify({
      agents: [standIn({ models: [{ id: "", input: 1, output: 1, cacheRead: 1, cacheWrite: 1 }] })]
    }),
    JSON.stringify({ agents: [standIn({ balance: null })] }),
    JSON.stringify({
      agents: [standIn({ balance: { remaining: 1, funded: 2, spent: 1, currency: "usd" } })]
    }),
    JSON.stringify({
      agents: [standIn({ balance: { remaining: -1, funded: 2, spent: 1, currency: "USD" } })]
    })
  ]
  bad.forEach(function (json) {
    assert.equal(logic.parseShowcase(json, showcaseNow), null, String(json))
  })
})

test("showcaseCall: closed refuses, invalid refuses, valid is ok", () => {
  const json = JSON.stringify({ agents: [standIn()] })
  assert.deepEqual(logic.showcaseCall(false, json, showcaseNow), {
    answer: "closed",
    showcase: null
  })
  assert.deepEqual(logic.showcaseCall(true, "{}", showcaseNow), {
    answer: "invalid",
    showcase: null
  })
  const ok = logic.showcaseCall(true, json, showcaseNow)
  assert.equal(ok.answer, "ok")
  assert.equal(ok.showcase[0].providerId, "claude")
})

// --- over-cap fractions, refreshCancel, selection ---------------------------------------

test("ringFraction: a fraction just over its cap (1, 1.5] is full, not a 0..100 percent", () => {
  assert.equal(logic.ringFraction([{ percent: 1.05 }]), 1)
  assert.equal(logic.ringFraction([{ percent: 1.5 }]), 1)
  assert.equal(logic.ringFraction([{ percent: 1.6 }]), 0.016)
})

test("refreshCancel: a pending refresh goes idle and keeps its baseline", () => {
  const busy = logic.refreshClick(logic.refreshLanded(logic.refreshIdle(), 7), 1000).state
  assert.deepEqual(logic.refreshCancel(busy), { busy: false, startedAt: 0, revision: 7 })
  assert.deepEqual(logic.refreshCancel(null), logic.refreshIdle())
  assert.deepEqual(logic.refreshCancel({ busy: true, startedAt: 5 }), logic.refreshIdle())
})

test("selection: a showcase and a close leave the real choice untouched", () => {
  let sel = { real: "codex", showcase: "" }
  assert.equal(logic.selectedId(sel, false), "codex")
  // The showcase picks its first stand-in, then h/l move within it.
  sel = logic.selectId(sel, true, "claude")
  assert.equal(logic.selectedId(sel, true), "claude")
  sel = logic.selectId(sel, true, "fireworks")
  assert.equal(logic.selectedId(sel, true), "fireworks")
  assert.equal(sel.real, "codex")
  // The dropdown closes: the stand-in choice goes, the real one is back.
  sel = logic.showcaseSelectionCleared(sel)
  assert.deepEqual(sel, { real: "codex", showcase: "" })
  assert.equal(logic.selectedId(sel, false), "codex")
  // Outside a showcase only the real choice moves.
  assert.deepEqual(logic.selectId(sel, false, "claude"), { real: "claude", showcase: "" })
})

test("selection: missing selections and ids read as empty", () => {
  assert.equal(logic.selectedId(null, false), "")
  assert.equal(logic.selectedId({}, true), "")
  assert.deepEqual(logic.selectId(null, true, null), { real: "", showcase: "" })
  assert.deepEqual(logic.selectId(undefined, false, undefined), { real: "", showcase: "" })
  assert.deepEqual(logic.showcaseSelectionCleared(null), { real: "", showcase: "" })
})

test("cursorView keeps the outline on Refresh, Enter's target", () => {
  assert.deepEqual(logic.cursorView(true), { active: true, section: "refresh", index: 0 })
  assert.deepEqual(logic.cursorView(false), { active: false, section: "refresh", index: 0 })
})

test("keyHint names the agent switch only with several agents, and Enter's refresh", () => {
  assert.equal(logic.keyHint(3), "h/l agent · enter refresh · ↑↓ scroll")
  assert.equal(logic.keyHint(1), "enter refresh · ↑↓ scroll")
  assert.equal(logic.keyHint(undefined), "enter refresh · ↑↓ scroll")
})
