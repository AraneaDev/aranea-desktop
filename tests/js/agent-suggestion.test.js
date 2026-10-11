const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const s = loadPragma("plugins/araneadev.projects/AgentSuggestion.js")
const plain = (v) => JSON.parse(JSON.stringify(v))
const now = Date.parse("2026-10-11T12:00:00Z")
const later = (m) => new Date(now + m * 60000).toISOString()
const both = [
  { id: "claude", label: "Claude Code", available: true },
  { id: "codex", label: "Codex", available: true }
]
const hhmm = (iso) => {
  const d = new Date(iso)
  return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
}
const rec = (...limits) => ({ limits, updatedAt: new Date(now).toISOString() })
const usage = (c, x) => ({
  claude: rec({ label: "W", percent: c, resetsAt: later(60) }),
  codex: rec({ label: "W", percent: x, resetsAt: later(60) })
})

test("alarming provider loses to one below 0.9 and explains its busiest window", () => {
  const r = plain(
    s.suggest(
      both,
      {
        claude: rec({ label: "Session (5-hour)", percent: 0.92, resetsAt: later(30) }),
        codex: rec({ label: "Weekly (7-day)", percent: 0.6, resetsAt: later(900) })
      },
      "claude",
      now
    )
  )
  assert.equal(r.suggestedId, "codex")
  assert.equal(
    r.options[0].reason,
    "92% of Session (5-hour) · resets " + hhmm(later(30)) + " · last used here"
  )
  assert.equal(r.options[1].reason, "60% used")
})

test("0.9 is alarming but just below remains calm", () => {
  assert.equal(s.suggest(both, usage(0.9, 0.899999), "claude", now).suggestedId, "codex")
  assert.equal(s.suggest(both, usage(0.899999, 0.89), "claude", now).suggestedId, "claude")
})

test("decisive gap wins and small gap falls back to last used then claude", () => {
  assert.equal(s.suggest(both, usage(0.5, 0.3), "claude", now).suggestedId, "codex")
  assert.equal(s.suggest(both, usage(0.4, 0.3), "claude", now).suggestedId, "claude")
  assert.equal(s.suggest(both, usage(0.4, 0.3), null, now).suggestedId, "claude")
  assert.equal(s.suggest(both, usage(0.4, 0.3), "codex", now).suggestedId, "codex")
  assert.equal(s.suggest(both, usage(0.3, 0.5), "codex", now).suggestedId, "claude")
})

test("decimal 0.15 gap is inclusive in either direction but genuinely smaller gap is not", () => {
  assert.equal(s.suggest(both, usage(0.7, 0.55), "claude", now).suggestedId, "codex")
  assert.equal(s.suggest(both, usage(0.55, 0.7), "codex", now).suggestedId, "claude")
  assert.equal(s.suggest(both, usage(0.7, 0.55000000001), "claude", now).suggestedId, "claude")
})

test("busiest window decides and 0..100 percents are rescaled", () => {
  const r = s.suggest(
    both,
    {
      claude: rec(
        { label: "A", percent: 10, resetsAt: later(60) },
        { label: "B", percent: 45, resetsAt: later(60) }
      ),
      codex: rec({ label: "W", percent: 0.05, resetsAt: later(60) })
    },
    null,
    now
  )
  assert.equal(r.options[0].fraction, 0.45)
  assert.equal(r.options[0].headline, "B")
  assert.equal(r.options[0].resetsAt, later(60))
  assert.equal(r.suggestedId, "codex")
})

test("shared normalization keeps the over-cap fraction versus percentage boundary", () => {
  for (const [percent, fraction] of [
    [0, 0],
    [1.5, 1],
    [1.6, 0.016],
    [150, 1]
  ]) {
    assert.equal(s.suggest(both, usage(percent, 0.5), null, now).options[0].fraction, fraction)
  }
})

test("stale, empty, missing and malformed usage is unknown", () => {
  for (const claude of [
    rec({ label: "W", percent: 0.1, resetsAt: later(-5) }),
    rec(),
    null,
    { limits: "nope" },
    undefined
  ]) {
    const r = plain(
      s.suggest(
        both,
        { claude, codex: rec({ label: "W", percent: 0.7, resetsAt: later(60) }) },
        null,
        now
      )
    )
    assert.deepEqual(r.options[0], {
      id: "claude",
      label: "Claude Code",
      available: true,
      fraction: -1,
      headline: null,
      resetsAt: null,
      reason: "Usage unknown"
    })
    assert.equal(r.suggestedId, "codex", "known below 0.9 beats unknown")
  }
})

test("reset equal to now makes the busiest window unknown even with a fresh lesser window", () => {
  const r = s.suggest(
    both,
    {
      claude: rec(
        { label: "Fresh", percent: 0.2, resetsAt: later(60) },
        { label: "Expired", percent: 0.8, resetsAt: later(0) }
      )
    },
    null,
    now
  )
  assert.equal(r.options[0].fraction, -1)
  assert.equal(r.options[0].headline, null)
})

test("invalid or missing reset stays known but does not invent a reset clock", () => {
  for (const resetsAt of [undefined, null, "invalid"]) {
    const r = s.suggest(both, { claude: rec({ label: "W", percent: 0.8, resetsAt }) }, null, now)
    assert.equal(r.options[0].fraction, 0.8)
    assert.equal(r.options[0].reason, "80% of W")
  }
  const r = s.suggest(both, { claude: rec({ percent: 0.8 }) }, "claude", now)
  assert.equal(r.options[0].reason, "80% used · last used here")
})

test("malformed percent and used values never become known zero usage", () => {
  for (const raw of [null, false, true, "", "0", "0.3", [], {}, NaN, Infinity, -Infinity, -0.1]) {
    for (const limit of [{ percent: raw }, { used: raw }, { percent: raw, used: 0.2 }]) {
      const r = s.suggest(both, { claude: rec(limit) }, null, now)
      assert.equal(r.options[0].fraction, -1, JSON.stringify(limit))
    }
  }
})

test("used is a numeric fallback only when percent is absent", () => {
  for (const [limit, fraction] of [
    [{ used: 30 }, 0.3],
    [{ percent: undefined, used: 0.4 }, 0.4],
    [{ percent: 0.2, used: 0.9 }, 0.2],
    [{ percent: 0, used: 0.9 }, 0]
  ]) {
    const r = s.suggest(both, { claude: rec(limit) }, null, now)
    assert.equal(r.options[0].fraction, fraction)
  }
})

test("mixed malformed limits cannot mask a valid busiest window", () => {
  const r = s.suggest(
    both,
    {
      claude: rec(
        null,
        false,
        "bad",
        {},
        { label: "Invalid", percent: "99" },
        { label: "Invalid fallback", percent: null, used: 0.99 },
        { label: "Valid", used: 40, resetsAt: later(60) },
        { label: "Lesser", percent: 0.2 }
      )
    },
    null,
    now
  )
  assert.equal(r.options[0].fraction, 0.4)
  assert.equal(r.options[0].headline, "Valid")
  assert.equal(r.options[0].reason, "40% used")
})

test("both unknown falls back to last used then claude", () => {
  assert.equal(s.suggest(both, {}, "codex", now).suggestedId, "codex")
  assert.equal(s.suggest(both, {}, null, now).suggestedId, "claude")
  assert.equal(s.suggest(both, null, null, now).suggestedId, "claude")
  assert.equal(s.suggest(both, {}, "other", now).suggestedId, "claude")
  assert.equal(
    s.suggest(both, {}, "codex", now).options[1].reason,
    "Usage unknown · last used here"
  )
})

test("known alarming usage does not automatically beat unknown", () => {
  assert.equal(
    s.suggest(both, { claude: usage(0.9, 0.1).claude }, "codex", now).suggestedId,
    "codex"
  )
  assert.equal(s.suggest(both, { codex: usage(0.1, 0.95).codex }, null, now).suggestedId, "claude")
  assert.equal(s.suggest(both, usage(0.9, 1.1), "codex", now).suggestedId, "codex")
})

test("only installed available providers are suggested and options keep canonical order", () => {
  const onlyCodex = [{ id: "codex", label: "My Codex", available: true }]
  const r = plain(
    s.suggest(
      onlyCodex,
      { claude: rec({ label: "W", percent: 0.01, resetsAt: later(60) }) },
      "claude",
      now
    )
  )
  assert.equal(r.suggestedId, "codex")
  assert.deepEqual(
    r.options.map((o) => o.id),
    ["claude", "codex"]
  )
  assert.equal(r.options[0].available, false)
  assert.equal(r.options[0].label, "Claude Code")
  assert.equal(r.options[1].label, "My Codex")
  assert.equal(
    s.suggest([...onlyCodex, { id: "claude", available: false }], usage(0.1, 0.8), "claude", now)
      .suggestedId,
    "codex"
  )
  assert.equal(s.suggest([], {}, "claude", now).suggestedId, null)
  assert.equal(s.suggest(undefined, {}, null, now).suggestedId, null)
  assert.equal(s.suggest([{ id: "other", available: true }], {}, null, now).suggestedId, null)
  assert.equal(s.suggest([...both].reverse(), {}, null, now).suggestedId, "claude")
})
