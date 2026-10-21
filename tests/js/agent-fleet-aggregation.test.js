const assert = require("node:assert/strict")
const fs = require("node:fs")
const { test } = require("node:test")
const file = "plugins/araneadev.agents/AgentFleetAggregation.js"
const fleet = fs.existsSync(file) ? require("../../" + file) : {}
const dates = [
  "2026-10-15",
  "2026-10-16",
  "2026-10-17",
  "2026-10-18",
  "2026-10-19",
  "2026-10-20",
  "2026-10-21"
]

/** Runs the real reducer with explicit calendar and clock inputs. */
function aggregate(snapshots) {
  assert.equal(typeof fleet.aggregateSnapshots, "function", "pure fleet aggregation is available")
  return fleet.aggregateSnapshots(snapshots, dates, "2026-10-21T12:00:00.000Z", 1792584000000)
}

test("device counters add while replicated account counters use maxima for every metric", () => {
  const snapshots = [
    {
      deviceId: "b",
      providers: {
        claude: {
          todayPrompts: "3.6",
          todaySessions: 2,
          todayTotalTokens: 12,
          totalPrompts: 10,
          totalSessions: 4,
          todayTokensByModel: { opus: 7 },
          modelUsage: { opus: { inputTokens: 10, outputTokens: 4, customTokens: 8 } }
        },
        fireworks: {
          scope: "account",
          todayPrompts: 2,
          todaySessions: 5,
          todayTotalTokens: 100,
          totalPrompts: 20,
          totalSessions: 9,
          todayTokensByModel: { deepseek: 80 },
          modelUsage: { deepseek: { inputTokens: 80, outputTokens: 20 } }
        }
      }
    },
    {
      deviceId: "a",
      providers: {
        claude: {
          todayPrompts: 2,
          todaySessions: 3,
          todayTotalTokens: 8,
          totalPrompts: 5,
          totalSessions: 2,
          todayTokensByModel: { opus: 3 },
          modelUsage: {
            opus: {
              inputTokens: 3,
              outputTokens: 2,
              cacheReadInputTokens: 7,
              cacheCreationInputTokens: 1,
              customTokens: 2
            }
          }
        },
        fireworks: {
          scope: "account",
          todayPrompts: 3,
          todaySessions: 4,
          todayTotalTokens: 90,
          totalPrompts: 15,
          totalSessions: 11,
          todayTokensByModel: { deepseek: 70 },
          modelUsage: { deepseek: { inputTokens: 70, outputTokens: 30 } }
        }
      }
    }
  ]
  const original = JSON.stringify(snapshots)
  const out = aggregate(snapshots).providers
  assert.deepEqual(
    [
      out.claude.todayPrompts,
      out.claude.todaySessions,
      out.claude.todayTotalTokens,
      out.claude.totalPrompts,
      out.claude.totalSessions
    ],
    [6, 5, 20, 15, 6]
  )
  assert.deepEqual(out.claude.todayTokensByModel, { opus: 10 })
  assert.deepEqual(out.claude.modelUsage.opus, {
    inputTokens: 13,
    outputTokens: 6,
    cacheReadInputTokens: 7,
    cacheCreationInputTokens: 1,
    customTokens: 10
  })
  assert.deepEqual(
    [
      out.fireworks.todayPrompts,
      out.fireworks.todaySessions,
      out.fireworks.todayTotalTokens,
      out.fireworks.totalPrompts,
      out.fireworks.totalSessions
    ],
    [3, 5, 100, 20, 11]
  )
  assert.deepEqual(out.fireworks.todayTokensByModel, { deepseek: 80 })
  assert.deepEqual(out.fireworks.modelUsage.deepseek, {
    inputTokens: 80,
    outputTokens: 30,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0
  })
  assert.equal(JSON.stringify(snapshots), original, "source snapshots remain reusable")
})

test("active dates union across overlapping devices while widest legacy count remains a floor", () => {
  const out = aggregate([
    {
      deviceId: "a",
      providers: {
        union: { activeDates: ["2026-01-01", "2026-01-02", "2026-01-02"], activeDays: 2 },
        legacy: { activeDays: 8 }
      }
    },
    {
      deviceId: "b",
      providers: {
        union: { activeDates: ["2026-01-02", "2026-01-03"], activeDays: 2 },
        legacy: { activeDates: ["2026-01-01"], activeDays: 3 }
      }
    }
  ]).providers
  assert.equal(out.union.activeDays, 3)
  assert.equal(out.legacy.activeDays, 8)
})

test("seven-day window filters stale and future dates and zero-fills calendar order", () => {
  const out = aggregate([
    {
      deviceId: "a",
      providers: {
        device: {
          recentDays: [
            { date: "2026-10-21", messageCount: 3 },
            { date: "2026-10-15", messageCount: 2 },
            { date: "2026-10-14", messageCount: 100 },
            { date: "2026-10-22", messageCount: 100 },
            null
          ]
        },
        account: { scope: "account", recentDays: [{ date: "2026-10-15", messageCount: 4 }] }
      }
    },
    {
      deviceId: "b",
      providers: {
        device: { recentDays: [{ date: "2026-10-15", messageCount: 5 }] },
        account: { scope: "account", recentDays: [{ date: "2026-10-15", messageCount: 3 }] }
      }
    }
  ]).providers
  assert.deepEqual(out.device.recentDays, [
    { date: "2026-10-15", messageCount: 7 },
    { date: "2026-10-16", messageCount: 0 },
    { date: "2026-10-17", messageCount: 0 },
    { date: "2026-10-18", messageCount: 0 },
    { date: "2026-10-19", messageCount: 0 },
    { date: "2026-10-20", messageCount: 0 },
    { date: "2026-10-21", messageCount: 3 }
  ])
  assert.equal(out.account.recentDays[0].messageCount, 4)
})

test("legacy flags, first nonempty name, finite rounding and discovered readiness retain fallbacks", () => {
  const out = aggregate([
    {
      deviceId: "a",
      providers: {
        legacy: {
          providerName: "",
          ready: false,
          todayPrompts: "bad",
          todaySessions: Infinity,
          totalPrompts: -1.6,
          activeDates: "bad",
          recentDays: {}
        },
        explicit: { hasLocalStats: false, hasPromptStats: false }
      }
    },
    {
      deviceId: "b",
      providers: { legacy: { providerName: "First", todayPrompts: "2.5" }, empty: null }
    },
    { deviceId: "a", providers: { legacy: { providerName: "Later" } } }
  ]).providers
  assert.equal(out.legacy.providerName, "First")
  assert.equal(out.legacy.ready, true)
  assert.equal(out.legacy.hasLocalStats, true)
  assert.equal(out.legacy.hasPromptStats, true)
  assert.equal(out.legacy.todayPrompts, 3)
  assert.equal(out.legacy.todaySessions, 0)
  assert.equal(out.legacy.totalPrompts, -2)
  assert.equal(out.legacy.activeDays, 0)
  assert.equal(out.explicit.hasLocalStats, false)
  assert.equal(out.explicit.hasPromptStats, false)
  assert.equal(out.empty.hasPromptStats, true)
})

test("fleet counts unique supplied identities, sorts devices and preserves provider encounter order", () => {
  const out = aggregate([
    { deviceId: "z", providers: { codex: {}, claude: {} } },
    { deviceId: "a", providers: { claude: {}, fireworks: {} } },
    { deviceId: "a" },
    { deviceId: "empty", providers: {} }
  ])
  assert.equal(out.schemaVersion, 1)
  assert.equal(out.updatedAt, "2026-10-21T12:00:00.000Z")
  assert.equal(out.updatedAtMs, 1792584000000)
  assert.equal(out.deviceCount, 3)
  assert.deepEqual(out.devices, ["a", "empty", "z"])
  assert.deepEqual(Object.keys(out.providers), ["codex", "claude", "fireworks"])
  assert.equal(out.providers.claude.deviceCount, 2)
  assert.deepEqual(out.providers.claude.devices, ["a", "z"])
  assert.deepEqual(out.providers.codex.devices, ["z"])
  assert.deepEqual(aggregate([]), {
    schemaVersion: 1,
    updatedAt: "2026-10-21T12:00:00.000Z",
    updatedAtMs: 1792584000000,
    deviceCount: 0,
    devices: [],
    providers: {}
  })
})

test("mixed legacy device and account snapshots retain incoming-scope merge order", () => {
  const device = { deviceId: "a", providers: { mixed: { todayPrompts: 5 } } }
  const account = { deviceId: "b", providers: { mixed: { scope: "account", todayPrompts: 3 } } }
  assert.equal(aggregate([device, account]).providers.mixed.todayPrompts, 5)
  assert.equal(aggregate([account, device]).providers.mixed.todayPrompts, 8)
})
