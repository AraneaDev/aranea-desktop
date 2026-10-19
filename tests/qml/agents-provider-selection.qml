// Provider choice survives shell reconstruction; showcases never overwrite it.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents

ShellRoot {
  id: host
  // Instance reconstructed from the saved inline settings during this test.
  property var panel: null
  QtObject {
    id: activity
    property var snapshot: ({
        tasks: []
      })
    property bool pending: false
    property var error: null
    property var currentOperation: null
    property string operationId: ''
    property string ownerId: ''
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
  QmlTest {
    id: t
  }
  Component {
    id: panelFactory
    Agents.Panel {
      activityClient: activity
      projectClient: projects
      usageClient: ({
          enabledProviders: [
            {
              providerId: "claude",
              limits: []
            },
            {
              providerId: "codex",
              limits: []
            }
          ],
          agents: [],
          dataRevision: 0,
          pendingUpdateKind: '',
          syncStatusText: ''
        })
    }
  }
  Component.onCompleted: t.step(100, function () {
    host.panel = panelFactory.createObject(host, {
      settings: {
        refreshIntervalSec: 60
      }
    })
    host.panel.nowMs = Date.UTC(2026, 9, 19, 12)
    var expired = host.panel.limitWindow('5h', 0.95, '2026-10-19T12:00:00Z', '')
    t.equal(expired.percent, 0, 'a reset usage window no longer reports stale consumption')
    t.equal(expired.resetAt, '', 'a reset usage window clears its stale countdown')
    var current = host.panel.limitWindow('5h', 0.6, '2026-10-19T13:00:00Z', '')
    t.equal(current.percent, 0.6, 'a future usage window retains consumption')
    t.equal(host.panel.limitWindow('5h', 0.4, '', '').percent, 0.4, 'a missing reset retains consumption')
    host.panel.selectProvider(1)
    t.equal(host.panel.settings.selectedProviderId, 'codex', 'real provider choice is saved in inline settings')
    t.equal(host.panel.settings.refreshIntervalSec, 60, 'saving a provider retains other settings')
    var saved = host.panel.settings
    host.panel.destroy()
    t.step(100, function () {
      host.panel = panelFactory.createObject(host, {
        settings: saved
      })
      t.equal(host.panel.provider.providerId, 'codex', 'a reconstructed shell restores Codex instead of the first provider')
      host.panel.agentsShowcase = [
        {
          providerId: 'claude'
        },
        {
          providerId: 'codex'
        }
      ]
      host.panel.selectProvider(0)
      t.equal(host.panel.settings.selectedProviderId, 'codex', 'showcase selection never saves over the real choice')
      host.panel.agentsShowcase = null
      t.equal(host.panel.provider.providerId, 'codex', 'closing showcase restores the saved provider')
      host.panel.captureActive = true
      host.panel.selectProvider(0)
      t.equal(host.panel.settings.selectedProviderId, 'codex', 'inert capture navigation never writes preferences')
      t.done()
    })
  })
}
