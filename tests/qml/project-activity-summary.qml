// Summary links navigate only, fit small viewports, and refuse capture activation.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Detail destinations reached by navigation-only summary links.
  property var destinations: []
  // Work effects must remain absent while summary links are activated.
  property int effects: 0
  QmlTest {
    id: t
  }
  Projects.ProjectOverview {
    id: overview
    width: 260
    model: ({
        git: null,
        services: [
          {
            observationState: 'running',
            title: 'Dev server',
            status: 'Running',
            detail: '',
            target: {},
            controls: []
          }
        ],
        checks: [],
        agents: [
          {
            reportedState: 'ready-for-review',
            connected: true,
            connectionLost: false,
            title: 'Layout work',
            status: 'Ready for review (reported)',
            detail: '',
            target: {},
            controls: []
          }
        ],
        workspaces: []
      })
    onDetailsRequested: function (section, target) {
      host.destinations.push(section)
    }
    onActionRequested: host.effects++
    onAgentRequested: host.effects++
    onWorkspaceRequested: host.effects++
  }
  Component.onCompleted: t.step(80, function () {
    var agents = t.findChild(overview, 'activitySummary:agents')
    var actions = t.findChild(overview, 'activitySummary:actions')
    t.check(!!agents && !!actions, 'actions and agents share one compact activity summary')
    t.check(agents.width <= overview.width && actions.width <= overview.width, 'summary links fit a narrow viewport')
    agents.activate()
    actions.activate()
    t.equal(host.destinations, ['agents', 'actions'], 'summary links open their existing detail destinations')
    t.equal(host.effects, 0, 'summary navigation never starts or stops work')
    overview.displayOnly = true
    agents.activate()
    actions.activate()
    t.equal(host.destinations.length, 2, 'capture disables summary navigation')
    overview.width = 180
    t.step(30, function () {
      t.check(agents.width <= overview.width, 'long summary labels remain inside a smaller viewport')
      t.done()
    })
  })
}
