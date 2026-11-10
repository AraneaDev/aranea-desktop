// Actual target collector output must survive Aranea discovery and panel views.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.agents" as Agents

ShellRoot {
  QmlTest {
    id: t
  }
  FileView {
    id: captured
    path: Quickshell.env("ARANEA_TEST_SANDBOX") + "/provider-fixtures.json"
    blockLoading: true
  }
  Agents.Main {
    id: usage
  }
  Agents.Agent {
    id: record
  }
  QtObject {
    id: activity
    property var snapshot: ({
        tasks: []
      })
    property bool pending: false
    property var error: null
    property var currentOperation: null
    property string operationId: ""
    property string ownerId: ""
    function refresh() {
    }
  }
  QtObject {
    id: projects
    property var snapshot: ({
        projects: []
      })
    function refresh() {
    }
  }
  Agents.Panel {
    id: panel
    usageClient: usage
    activityClient: activity
    projectClient: projects
  }
  // Feed the real JSON parser and normalization, including settings discovery.
  function apply(value) {
    record.parse(JSON.stringify(value))
    usage.agents = [record]
    usage.recordsChanged()
    panel.selectProvider(0)
  }
  Component.onCompleted: t.step(250, function () {
    var fixtures = JSON.parse(captured.text())
    apply(fixtures.subscription)
    t.equal(panel.agentsView.limits.length, 1, "subscription exposes its actual limit window")
    t.equal(panel.agentsView.limits[0].fraction, 0.4, "subscription consumption survives normalization")
    apply(fixtures.stale)
    t.equal(panel.agentsView.limits.length, 1, "failed refresh keeps the last good limit")
    t.equal(panel.agentsView.hero.problem, "failed to fetch codex rate limits", "retained limits explain stale data even with empty status")
    apply(fixtures.accounts)
    t.equal(panel.agentsView.limits.length, 1, "account copies never become duplicate current-account windows")
    t.equal(panel.provider.totalSessions, 1, "account copies never multiply local sessions")
    t.check(panel.agentsView.hero.problem.indexOf("Work: failed to fetch codex rate limits") >= 0, "inactive stale account explains its own failed refresh")
    var partial = JSON.parse(JSON.stringify(fixtures.accounts))
    partial.limitsStale = false
    partial.authHelpText = ""
    partial.accounts[0].stale = false
    partial.accounts[0].authHelpText = ""
    apply(partial)
    t.equal(panel.agentsView.hero.problem, "Work: failed to fetch codex rate limits", "inactive account staleness remains visible when current account is fresh")
    apply(fixtures.prepaid)
    t.equal(panel.agentsView.limits.length, 0, "prepaid account never invents subscription windows")
    t.equal(panel.balance.remaining, 7.5, "real prepaid ledger retains remaining credit")
    t.equal(panel.agentsView.balance.fraction, 0.75, "prepaid meter measures remaining funded credit")
    apply(fixtures.compressed)
    t.equal(panel.provider.totalSessions, 1, "compressed Codex rollout counts one session")
    t.equal(panel.agentsView.limits.length, 0, "history without subscription has no LIMITS section")
    apply(fixtures.swapping)
    t.equal(panel.provider.totalSessions, 1, "plain plus compressed rollout still counts once")
    t.equal(panel.provider.todayTotalTokens, 9, "compression swap never doubles tokens")
    apply(fixtures.missing)
    t.equal(usage.enabledProviders.length, 0, "unused missing provider does not acquire an empty tab")
    apply({
      id: "grok",
      name: "Grok",
      ready: true,
      tierLabel: "X Premium+",
      limits: []
    })
    t.equal(usage.enabledProviders.length, 1, "ready plan remains discoverable before limits arrive")
    t.equal(panel.agentsView.limits.length, 0, "tier-only plan does not invent consumption")
    apply({
      id: "future-provider",
      name: "Future",
      ready: true,
      totalSessions: 2,
      limits: []
    })
    t.equal(usage.enabledProviders.length, 1, "unknown usage providers remain discoverable by default")
    usage.settings = {
      providers: {
        "future-provider": {
          enabled: false
        }
      }
    }
    t.equal(usage.enabledProviders.length, 0, "explicit disable also restricts newly discovered usage providers")
    usage.settings = {
      providers: {
        codex: {
          enabled: false
        }
      }
    }
    apply(fixtures.subscription)
    t.equal(usage.enabledProviders.length, 0, "disabled subscription cannot bypass local settings")
    t.done()
  })
}
