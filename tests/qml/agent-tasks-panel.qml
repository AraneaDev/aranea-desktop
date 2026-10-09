// Actual panel integration uses injected clients and never creates Usage collectors.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: host
  // Typed calls expose the sole client boundary without commands.
  property var calls: []
  // The first operation read can fail after both acceptance IDs are known.
  property bool failAcceptedRead: true
  // Fixture-controlled transport results never invoke a process.
  property string acceptanceOwner: 'accepted-owner'
  // A different owner cannot establish recovery of the original acceptance.
  property string observationOwner: 'different-owner'
  // Exact accepted ID is retained before currentOperation has been populated.
  property string acceptanceId: 'accepted-before-first-read'
  Activity.ActivityClient {
    id: acceptedClient
    captureActive: true
    runner: function (argv, done) {
      if (argv[2] === 'request')
        done(0, JSON.stringify({
          ok: true,
          operationId: host.acceptanceId,
          ownerId: host.acceptanceOwner
        }), '')
      else if (argv[2] === 'operation') {
        if (host.failAcceptedRead)
          done(1, '', 'First accepted operation read failed')
        else
          done(0, JSON.stringify({
            id: host.acceptanceId,
            ownerId: host.observationOwner,
            taskId: 'before-first-read',
            action: 'reopen',
            state: 'completed',
            outcome: 'observed'
          }), '')
      } else if (argv[2] === 'snapshot')
        done(0, JSON.stringify({
          tasks: []
        }), '')
      else
        done(1, '', 'Unexpected test transport method')
    }
  }
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
    property bool acceptReopen: false
    signal operationChanged(var operation)
    function refresh() {
      calls.push(['refresh'])
    }
    function request(payload) {
      calls.push(['request', payload])
      if (acceptReopen && payload.action === 'reopen') {
        operationId = 'accepted-lost'
        currentOperation = {
          id: operationId,
          ownerId: 'old-owner',
          taskId: payload.taskId,
          action: 'reopen',
          state: 'observing',
          outcome: null
        }
      }
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
          nativeSessionEligible: true,
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
    var frame = t.findChild(panel, 'agentKeyboardFrame')
    frame.textKey('r')
    frame.textKey('R')
    t.equal(calls.length, 0, 'both Tasks r/R keyboard routes refuse injected refresh during capture')
    panel.handleTaskAction('focus', 'stable')
    panel.handleTaskAction('setup', '')
    t.equal(calls.length, 0, 'capture blocks mutation and setup actions')
    tabs.choose('usage')
    t.equal(tabs.destination, 'usage', 'tab choice is remembered with attention')
    tabs.choose('tasks')
    tasks.selectedId = 'stable'
    panel.captureActive = false
    frame.textKey('r')
    frame.textKey('R')
    t.equal(calls, [['refresh'], ['refresh']], 'both live Tasks r/R routes use the injected activity refresh boundary')
    calls = []
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
    activity.snapshot = {
      tasks: [Object.assign({}, activity.snapshot.tasks[0], {
          displayState: 'connection-lost',
          freshness: 'connection-lost',
          resumeCommand: 'fixed display command'
        })],
      operations: []
    }
    activity.currentOperation = null
    activity.operationId = ''
    activity.acceptReopen = true
    panel.handleTaskAction('reopen', 'stable')
    t.equal(calls.pop(), ['request',
      {
        action: 'reopen',
        taskId: 'stable'
      }
    ], 'one reopen is explicitly accepted before owner loss')
    activity.error = {
      code: 'OPERATION_LOST',
      message: 'Owner restarted',
      recovery: 'Reconnect and check existing terminal'
    }
    t.check(tasks.selectedOperation && tasks.selectedOperation.ownerUnconfirmed, 'accepted owner loss marks exact operation unconfirmed')
    panel.handleTaskAction('open-checkout', 'stable')
    panel.handleTaskAction('dismiss', 'stable')
    t.equal(calls.length, 0, 'lost accepted operation blocks same-task overwrite')
    activity.snapshot = Object.assign({}, activity.snapshot, {
      revision: 99,
      ownerId: 'new-owner'
    })
    activity.error = null
    activity.currentOperation = {
      id: 'another-new-action',
      ownerId: 'new-owner',
      taskId: 'other-task',
      action: 'focus',
      state: 'completed',
      outcome: 'observed'
    }
    activity.operationId = 'another-new-action'
    t.equal(tasks.selectedOperation && tasks.selectedOperation.id, 'accepted-lost', 'successful new snapshot and other mutation retain original lost operation')
    t.check(tasks.selectedOperation && tasks.selectedOperation.ownerLossError && tasks.selectedOperation.ownerLossError.code === 'OPERATION_LOST', 'loss diagnostic survives global error clearing')
    panel.handleTaskAction('reopen', 'stable')
    panel.handleTaskAction('open-checkout', 'stable')
    t.equal(calls.length, 0, 'cleared transport error never restores same-task launch/checkout')
    panel.handleTaskAction('reconnect', 'stable')
    t.equal(calls.pop(), ['reconnect', 'accepted-lost'], 'lost owner recovery reconnects exact accepted ID')
    t.check(t.findChild(tasks, 'operationStatus').text.indexOf('unconfirmed') >= 0, 'loss remains visible in actual details after global error clearing')
    t.check(t.findChild(tasks, 'operationError').text.indexOf('Owner restarted') >= 0, 'exact retained loss diagnostic remains visible')
    activity.operationChanged({
      id: 'accepted-lost',
      ownerId: 'new-owner',
      taskId: 'stable'
    })
    t.check(tasks.selectedOperation.ownerUnconfirmed, 'different owner observation cannot clear retained loss')
    var recovered = {
      id: 'accepted-lost',
      ownerId: 'old-owner',
      taskId: 'stable',
      action: 'reopen',
      state: 'completed',
      outcome: 'observed'
    }
    activity.currentOperation = recovered
    activity.operationId = recovered.id
    activity.operationChanged(recovered)
    t.check(!tasks.selectedOperation.ownerUnconfirmed, 'explicit successful exact owner observation clears retained loss')
    activity.currentOperation = null
    activity.snapshot = {
      tasks: [Object.assign({}, activity.snapshot.tasks[0], {
          taskId: 'fresh-review',
          reportedState: 'ready-for-review',
          displayState: 'ready-for-review',
          freshness: 'connected'
        })],
      operations: []
    }
    panel.handleTaskAction('dismiss', 'fresh-review')
    t.equal(calls.length, 0, 'fresh live review never submits dismissal')
    activity.snapshot = {
      tasks: [Object.assign({}, activity.snapshot.tasks[0], {
          freshness: 'connection-lost'
        })],
      operations: []
    }
    panel.handleTaskAction('dismiss', 'fresh-review')
    t.equal(calls.pop(), ['dismiss', 'fresh-review'], 'owner-stale review submits narrow exact-ID dismissal')
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
      syncStatusText: '',
      refreshLimits: function () {
        calls.push(['limits-refresh'])
      }
    }
    tabs.choose('usage')
    t.check(t.findChild(panel, 'agentsHeader').visible, 'Usage tab renders the actual existing dropdown')
    t.equal(panel.ringFraction, 0.2, 'task attention preserves the existing Usage ring')
    tabs.choose('tasks')
    t.equal(panel.selectedProviderId, 'claude', 'task selection leaves Usage provider identity unchanged')
    panel.captureActive = false
    acceptedClient.captureActive = false
    acceptedClient.snapshot = {
      tasks: [
        {
          taskId: 'before-first-read',
          provider: 'claude',
          source: 'native',
          nativeSessionEligible: true,
          reportedState: 'working',
          displayState: 'connection-lost',
          freshness: 'connection-lost',
          resumeCommand: 'fixed display text',
          association: {
            status: 'registered',
            projectId: 'p',
            checkoutId: 'c',
            cwd: '/repo'
          }
        }
      ]
    }
    panel.activityClient = acceptedClient
    tasks.selectedId = 'before-first-read'
    panel.handleTaskAction('reopen', 'before-first-read')
    t.equal(acceptedClient.currentOperation, null, 'failed first read leaves accepted client operation unobserved')
    t.equal(acceptedClient.operationId, 'accepted-before-first-read', 'real client retains accepted operation ID before observation')
    t.equal(acceptedClient.ownerId, 'accepted-owner', 'real client retains accepted owner ID before observation')
    t.equal(tasks.selectedOperation && tasks.selectedOperation.ownerId, 'accepted-owner', 'sticky first-read failure preserves known accepted owner identity')
    t.check(tasks.selectedOperation && tasks.selectedOperation.ownerUnconfirmed, 'failed first observation is protected')
    failAcceptedRead = false
    acceptedClient.reconnect()
    t.check(tasks.selectedOperation.ownerUnconfirmed, 'different owner response cannot clear first-read uncertainty')
    observationOwner = 'accepted-owner'
    acceptedClient.reconnect()
    t.check(!tasks.selectedOperation.ownerUnconfirmed, 'successful same-owner first observation clears sticky protection')
    t.equal(tasks.selectedOperation.id, 'accepted-before-first-read', 'successful recovery preserves the accepted ID')
    acceptanceId = 'acceptance-without-owner'
    acceptanceOwner = ''
    failAcceptedRead = true
    panel.handleTaskAction('reopen', 'before-first-read')
    t.equal(tasks.selectedOperation.ownerId, '', 'missing accepted owner identity remains explicitly absent')
    failAcceptedRead = false
    acceptedClient.reconnect()
    t.check(tasks.selectedOperation.ownerUnconfirmed, 'later owner identity is never guessed into the absent acceptance')
    panel.activityClient = activity
    t.check(typeof panel.showTask === 'function', 'notification detail endpoint exists')
    if (typeof panel.showTask === 'function') {
      var beforeSelection = tasks.selectedId
      var requested = panel.showTask('notify-task')
      t.check(requested.ok && requested.status === 'pending', 'deep link awaits a fresh snapshot')
      t.equal(tasks.selectedId, beforeSelection, 'cached task cannot satisfy notification deep link')
      activity.snapshot = {
        tasks: [
          {
            taskId: 'notify-task',
            provider: 'claude',
            reportedState: 'failed',
            association: {}
          }
        ]
      }
      t.equal(tasks.selectedId, 'notify-task', 'fresh exact task opens its real details')
      panel.showTask('removed-task')
      activity.snapshot = {
        tasks: [
          {
            taskId: 'different-task',
            provider: 'claude',
            reportedState: 'failed',
            association: {}
          }
        ]
      }
      t.check(tasks.selectedId !== 'different-task', 'removed target never selects its replacement')
      t.equal(panel.taskInspection.status, 'unavailable', 'removed deep link reports unavailable')
      panel.captureActive = true
      var beforeCalls = calls.length
      t.check(!panel.showTask('different-task').ok, 'capture refuses deep link')
      t.equal(calls.length, beforeCalls, 'capture deep link does not refresh')
    }
    acceptedClient.captureActive = true
    panel.captureActive = true
    t.done()
  })
}
