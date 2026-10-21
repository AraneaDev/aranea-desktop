// Characterize the real sync parsing owner and its cross-device reduction.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents

ShellRoot {
  QmlTest {
    id: t
  }
  Agents.Main {
    id: usage
  }

  Component.onCompleted: {
    var dates = usage.recentDateStrings()
    var before = Date.now()
    var first = {
      deviceId: "..z laptop..",
      providers: {
        claude: {
          todayPrompts: 3,
          activeDates: ["2026-01-01", "2026-01-02"],
          recentDays: [
            {
              date: dates[0],
              messageCount: 2
            }
          ]
        },
        fireworks: {
          scope: "account",
          todayTotalTokens: 100
        }
      }
    }
    var second = {
      deviceId: "a",
      providers: {
        claude: {
          todayPrompts: 4,
          activeDays: 5,
          activeDates: ["2026-01-02", "2026-01-03"],
          recentDays: [
            {
              date: dates[0],
              messageCount: 7
            }
          ]
        },
        fireworks: {
          scope: "account",
          todayTotalTokens: 80
        }
      }
    }
    usage.parseSyncScanOutput("===/z.json===\n" + JSON.stringify(first) + "\n=== EOM ===\n===/a.json===\n" + JSON.stringify(second))
    var fleet = usage.aggregateData
    t.equal(fleet.devices, ["a", "z-laptop"], "scan sanitizes and sorts device identities")
    t.equal(fleet.providers.claude.todayPrompts, 7, "device counters add across parsed files")
    t.equal(fleet.providers.fireworks.todayTotalTokens, 100, "replicated account counters never double")
    t.equal(fleet.providers.claude.activeDays, 5, "legacy active-day count survives the date union")
    t.equal(fleet.providers.claude.recentDays[0], {
      date: dates[0],
      messageCount: 9
    }, "recent counts merge in calendar order")
    t.equal(fleet.providers.claude.hasPromptStats, true, "old snapshots retain prompt support")
    t.equal(usage.syncRevision, 1, "scan publishes one aggregate revision")
    t.check(fleet.updatedAtMs >= before && fleet.updatedAtMs <= Date.now(), "owner supplies the current timestamp")
    t.check(isFinite(Date.parse(fleet.updatedAt)), "fleet timestamp is an ISO date")
    t.done()
  }
}
