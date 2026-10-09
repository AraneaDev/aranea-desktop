// Actual panel integration uses injected clients and never creates Usage collectors.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents

ShellRoot {
  id: host
  // Typed calls expose the sole client boundary without commands.
  property var calls: []
  QmlTest {
    id: t
  }
  Item {
    id: activity
    property var snapshot: ({
        tasks: []
      })
    property bool pending: false
    property var error: null
    property var currentOperation: null
    property string operationId: ''
    function refresh() {
      calls.push(['refresh'])
    }
    function request(payload) {
      calls.push(['request', payload])
    }
    function dismiss(id) {
      calls.push(['dismiss', id])
    }
    function reconnect(id) {
      calls.push(['reconnect', id])
    }
    function reobserve() {
      calls.push(['reobserve'])
    }
  }
  Item {
    id: projects
    property var snapshot: ({
        projects: [
          {
            id: 'p',
            name: 'Project',
            checkouts: [
              {
                id: 'c',
                path: '/repo',
                branch: 'main'
              }
            ]
          }
        ]
      })
    function refresh() {
      calls.push(['project-refresh'])
    }
  }
  FloatingWindow {
    visible: true
    width: 400
    height: 700
    Agents.Panel {
      id: panel
      captureActive: true
      activityClient: activity
      projectClient: projects
      usageClient: ({
          enabledProviders: [],
          agents: [],
          dataRevision: 0,
          pendingUpdateKind: '',
          syncStatusText: '',
          refreshAll: function () {
            calls.push(['usage-refresh'])
          },
          refreshLimits: function () {
            calls.push(['limits-refresh'])
          }
        })
    }
  }
  Component.onCompleted: t.step(80, function () {
    var tabs = t.findChild(panel, 'agentNavigation')
    var tasks = t.findChild(panel, 'agentTasks')
    t.check(!t.findChild(panel, 'agentUsageLoader').active, 'capture never creates Usage collectors')
    panel.requestRefresh()
    t.equal(calls.length, 0, 'capture does not refresh any injected client')
    t.equal(tabs.destination, 'usage', 'empty panel starts with Usage')
    activity.snapshot = {
      tasks: [
        {
          taskId: 'stable',
          provider: 'claude',
          description: 'Task',
          source: 'native',
          displayState: 'needs-input',
          reportedState: 'needs-input',
          freshness: 'connected',
          association: {
            status: 'registered',
            projectId: 'p',
            checkoutId: 'c',
            cwd: '/repo'
          }
        }
      ]
    }
    t.check(panel.visible, 'task-only panel is visible')
    t.equal(tabs.destination, 'tasks', 'attention opens Tasks by default')
    panel.handleTaskAction('focus', 'stable')
    panel.handleTaskAction('setup', '')
    t.equal(calls.length, 0, 'capture blocks mutation and setup actions')
    tabs.choose('usage')
    t.equal(tabs.destination, 'usage', 'tab choice is remembered with attention')
    tabs.choose('tasks')
    tasks.selectedId = 'stable'
    panel.captureActive = false
    panel.handleTaskAction('focus', 'gone')
    t.equal(calls.length, 0, 'removed task action is refused')
    panel.handleTaskAction('focus', 'stable')
    t.equal(calls.pop(), ['request',
      {
        action: 'focus',
        taskId: 'stable'
      }
    ], 'fixed session action routes exact ID only')
    activity.operationId = 'retained'
    activity.currentOperation = {
      id: 'retained',
      taskId: 'stable',
      action: 'reopen',
      state: 'completed',
      outcome: 'partial'
    }
    panel.handleTaskAction('reconnect', 'stable')
    t.equal(calls.pop(), ['reconnect', 'retained'], 'reconnect never requests another launch')
    panel.handleTaskAction('reobserve', 'stable')
    t.equal(calls.pop(), ['reobserve'], 'reobserve uses narrow observation endpoint')
    activity.snapshot = Object.assign({}, activity.snapshot, {
      operations: [
        {
          id: 'protected-original',
          taskId: 'stable',
          action: 'reopen',
          state: 'completed',
          outcome: 'partial',
          submissionUnconfirmed: true
        }
      ]
    })
    activity.currentOperation = {
      id: 'unrelated',
      taskId: 'another',
      action: 'focus',
      state: 'completed',
      outcome: 'observed'
    }
    activity.operationId = 'unrelated'
    t.check(tasks.selectedOperation && tasks.selectedOperation.id === 'protected-original', 'another client action does not hide retained uncertainty')
    panel.handleTaskAction('reconnect', 'stable')
    t.equal(calls.pop(), ['reconnect', 'protected-original'], 'reconnect uses selected retained operation identity')
    panel.handleTaskAction('open-checkout', 'stable')
    t.equal(calls.length, 0, 'protected task cannot replace retained operation with another mutation')
    panel.captureActive = true
    panel.selectedProviderId = 'claude'
    panel.usageClient = {
      enabledProviders: [
        {
          providerId: 'claude',
          providerName: 'Claude Code',
          limits: [
            {
              label: 'Session',
              percent: 0.2
            }
          ],
          recentDays: [],
          modelUsage: {}
        }
      ],
      agents: [],
      dataRevision: 0,
      pendingUpdateKind: '',
      syncStatusText: ''
    }
    tabs.choose('usage')
    t.check(t.findChild(panel, 'agentsHeader').visible, 'Usage tab renders the actual existing dropdown')
    t.equal(panel.ringFraction, 0.2, 'task attention preserves the existing Usage ring')
    tabs.choose('tasks')
    t.equal(panel.selectedProviderId, 'claude', 'task selection leaves Usage provider identity unchanged')
    t.done()
  })
}
