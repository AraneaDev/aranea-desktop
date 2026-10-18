// Real presentation composition with inert fixtures and held external transports.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held action transport requests never execute native commands.
  property var calls: []
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: root
    windowEnabled: false
    captureActive: true
  }
  Projects.ProjectsSurface {
    id: surface
    root: root
    width: 1080
    height: 720
  }
  Component.onCompleted: t.step(80, function () {
    root.view = surface
    root.projectController.state = {
      projects: [
        {
          id: 'p',
          name: 'Repo',
          lastCheckoutId: 'c',
          checkouts: [
            {
              id: 'c',
              path: '/repo',
              branch: 'main'
            }
          ]
        }
      ],
      roots: [],
      ignored: []
    }
    root.projectId = 'p'
    var overview = t.findChild(surface, 'projectOverview')
    t.check(!!overview, 'selected project renders Git-led Overview')
    if (!overview) {
      t.done()
      return
    }
    var cache = {}
    cache[JSON.stringify(['p', 'c'])] = {
      data: {
        projectId: 'p',
        checkoutId: 'c',
        branch: 'fresh-branch',
        observedAt: Date.now(),
        counts: {},
        files: []
      },
      error: null
    }
    root.gitClient.cache = cache
    t.check(t.findChild(surface, 'headerChooseCheckout').text.indexOf('fresh-branch') >= 0, 'selected header agrees with fresh exact-checkout Git branch')
    var actions = t.findChild(surface, 'projectActions')
    t.check(actions.client === root.actionClient, 'summary and full view share persistent action client')
    root.actionClient.runner = function (argv, input, done) {
      // Detection is observation on opening Actions; this suite counts explicit action calls only.
      if (argv[argv.length - 1] === 'detect')
        return
      host.calls.push({
        method: argv[argv.length - 1],
        payload: JSON.parse(input || '{}'),
        done: done
      })
    }
    root.actionClient.snapshot = {
      revision: 1,
      definitions: [
        {
          id: 'a',
          projectId: 'p',
          revision: 3,
          name: 'Tests',
          kind: 'command',
          argv: ['true'],
          cwdRelative: '.'
        }
      ],
      runs: [],
      requests: []
    }
    t.equal(overview.model.checks.length, 1, 'saved command discoverable without run')
    overview.actionRequested('start', overview.model.checks[0].target)
    t.equal(calls.length, 0, 'inert overview refuses explicit action dispatch')
    root.captureActive = false
    root.actionClient.availability = {
      execution: true
    }
    surface.refreshOverview()
    t.check(calls.every(function (c) {
      return ['snapshot', 'availability'].indexOf(c.method) >= 0
    }), 'refresh observes only and never executes commands')
    var services = []
    for (var i = 0; i < 4; i++)
      services.push({
        title: 'Old service',
        status: 'Stopped',
        detail: '',
        active: false,
        attention: false,
        target: {},
        controls: []
      })
    overview.model = {
      git: null,
      services: services,
      checks: [
        {
          title: 'Failed check',
          status: 'Failed',
          detail: '',
          active: false,
          attention: true,
          target: {},
          controls: []
        }
      ],
      agents: [],
      workspaces: []
    }
    t.equal(t.findChild(overview, 'overviewCommands').rows[0].title, 'Failed check', 'attention check precedes completed service history')
    overview.model = Qt.binding(function () {
      return surface.overviewModel
    })
    var commands = t.findChild(overview, 'overviewCommands')
    var summaryRequests = []
    commands.requested.connect(function (method, target) {
      summaryRequests.push(target)
    })
    var controls = [
      {
        method: 'start',
        label: 'Run'
      }
    ]
    overview.model = {
      git: null,
      services: [],
      checks: [
        {
          title: 'Check',
          status: 'Saved',
          detail: '',
          target: {
            actionId: 'pointer-test',
            revision: 1
          },
          controls: controls
        }
      ],
      agents: [],
      workspaces: []
    }
    var pressed = t.findChildren(commands, 'pill').filter(function (button) {
      return button.text === 'Run'
    })[0]
    pressed.pressed()
    overview.model = {
      git: null,
      services: [],
      checks: [
        {
          title: 'Check',
          status: 'Saved',
          detail: '',
          target: {
            actionId: 'pointer-test',
            revision: 2
          },
          controls: controls
        }
      ],
      agents: [],
      workspaces: []
    }
    t.findChildren(commands, 'pill').filter(function (button) {
      return button.text === 'Run'
    })[0].clicked()
    t.equal(summaryRequests.length, 0, 'refreshed compact row cannot inherit a press for an older revision')
    overview.model = Qt.binding(function () {
      return surface.overviewModel
    })
    var definition = root.actionClient.snapshot.definitions[0]
    var service = Object.assign({}, definition, {
      kind: 'service',
      previewUrl: 'http://127.0.0.1:8080'
    })
    var run = {
      id: 'run-one',
      projectId: 'p',
      checkoutId: 'c',
      actionId: 'a',
      createdAt: 1,
      processState: 'running',
      invocationId: 'inv',
      definitionSnapshot: service
    }
    root.actionClient.snapshot = {
      revision: 1,
      definitions: [service],
      runs: [run],
      requests: []
    }
    calls = []
    overview.actionRequested('open-preview', overview.model.services[0].target)
    t.equal(calls[0].method, 'open-preview', 'preview routes through existing client')
    t.equal(calls[0].payload.runId, 'run-one', 'preview keeps exact retained run')
    calls[0].done(0, JSON.stringify({
      ok: true,
      error: null,
      run: run
    }), '')
    overview.actionRequested('stop', overview.model.services[0].target)
    t.equal(calls[1].method, 'stop', 'Stop routes through existing client')
    t.equal(calls[1].payload.runId, 'run-one', 'Stop keeps exact retained run')
    calls[1].done(0, JSON.stringify({
      ok: true,
      error: null,
      run: run
    }), '')
    overview.actionRequested('logs', overview.model.services[0].target)
    t.equal(surface.section, 'actions', 'View output opens full Actions details')
    t.equal(calls[2].method, 'logs', 'output uses existing bounded journal reader')
    t.equal(calls[2].payload.runId, 'run-one', 'output keeps exact retained run')
    calls[2].done(0, JSON.stringify({
      ok: true,
      error: null,
      run: run,
      output: 'actual fixture output'
    }), '')
    t.equal(actions.client.output, 'actual fixture output', 'full Actions shares returned output')
    surface.chooseSection('overview')
    var activityCalls = []
    root.activityClient.runner = function (argv, done) {
      activityCalls.push(argv)
    }
    root.activityClient.snapshot = {
      tasks: [
        {
          taskId: 'task-one',
          description: 'Fix layout',
          reportedState: 'needs-input',
          freshness: 'connected',
          nativeSessionEligible: true,
          association: {
            status: 'registered',
            projectId: 'p',
            checkoutId: 'c',
            cwd: '/repo'
          }
        }
      ],
      operations: []
    }
    overview.agentRequested('focus', 'wrong-task')
    t.equal(activityCalls.length, 0, 'unknown agent target cannot dispatch')
    overview.agentRequested('focus', 'task-one')
    t.equal(JSON.parse(activityCalls[0][3]), {
      action: 'focus',
      taskId: 'task-one'
    }, 'Answer focuses exact session without submitting provider text')
    root.activityClient.pending = false
    root.actionClient.snapshot = {
      revision: 1,
      definitions: [definition],
      runs: [],
      requests: []
    }
    calls = []
    var target = overview.model.checks[0].target
    surface.overviewAction('start', Object.assign({}, target, {
      checkoutId: 'other'
    }))
    surface.overviewAction('start', Object.assign({}, target, {
      revision: 2
    }))
    t.equal(calls.length, 0, 'stale checkout and displayed revision refuse action')
    // The card's own Run button, as Enter activates it, not the signal.
    function buttonText(item, text) {
      if (item.text === text && typeof item.activate === 'function')
        return item
      var kids = t.childrenOf(item)
      for (var k = 0; k < kids.length; k++) {
        var found = kids[k] ? buttonText(kids[k], text) : null
        if (found)
          return found
      }
      return null
    }
    var runButton = buttonText(t.findChild(overview, 'overviewCommands'), 'Run')
    t.check(!!runButton && runButton.enabled, 'the checks card offers an enabled Run button')
    runButton.activate()
    t.equal(calls.length, 1, 'explicit Run routes once through actual shared client UUID boundary')
    calls[0].done(0, '00000000-0000-4000-8000-000000000001', '')
    t.equal(calls[1].method, 'start', 'explicit Run uses existing backend')
    t.equal(calls[1].payload.checkoutId, 'c', 'Run keeps exact checkout')
    t.equal(calls[1].payload.expectedDefinitionRevision, 3, 'Run keeps displayed revision')
    root.actionClient.disconnect()
    root.actionClient.runId = 'accepted-run'
    root.actionClient.submissionTarget = {
      projectId: 'p',
      checkoutId: 'c',
      actionId: 'a'
    }
    var tasks = [
      {
        taskId: 't-freshness',
        provider: 'codex',
        description: 'Layout',
        reportedState: 'working',
        freshness: 'connected',
        association: {
          status: 'registered',
          projectId: 'p',
          checkoutId: 'c',
          cwd: '/repo'
        }
      }
    ]
    var readSucceeded = true
    root.activityClient.runner = function (argv, done) {
      done(readSucceeded ? 0 : 1, readSucceeded ? JSON.stringify({
        tasks: tasks,
        operations: []
      }) : '', readSucceeded ? '' : 'Owner disappeared')
    }
    root.activityClient.refresh()
    t.check(overview.activitySummary.some(function (row) {
      return row.label === '1 agent working (reported)'
    }), 'successful owner read presents reported live work')
    readSucceeded = false
    root.activityClient.refresh()
    t.check(overview.activitySummary.some(function (row) {
      return row.label === 'Agent status not available'
    }), 'failed owner read replaces retained live work with connection uncertainty')
    t.check(!overview.activitySummary.some(function (row) {
      return row.label === '1 agent working (reported)'
    }), 'retained snapshot cannot keep a live summary after owner loss')
    root.gitClient.captureActive = true
    root.actionClient.captureActive = true
    root.activityClient.captureActive = true
    var nativeCalls = []
    root.projectClient.runner = function (argv, done) {
      nativeCalls.push({
        method: argv[2],
        payload: argv[3] ? JSON.parse(argv[3]) : null
      })
    }
    root.projectClient.identityRunner = function (done) {
      done('00000000-0000-4000-8000-000000000019')
    }
    root.projectClient.snapshot = {
      availability: {
        compositor: true
      },
      environments: [
        {
          id: 'e-old',
          projectId: 'p',
          checkoutId: 'old',
          workspaceId: 8,
          profileSnapshot: {
            name: 'Old tools',
            roles: ['editor', 'agent']
          },
          checkoutSnapshot: {
            branch: 'earlier',
            path: '/old'
          },
          resolvedTools: {
            editorId: 'code',
            agentId: 'codex'
          },
          observedRoles: ['editor']
        }
      ],
      operations: []
    }
    root.projectClient.available = true
    var page = t.findChild(surface, 'projectsPage')
    var registry = JSON.parse(JSON.stringify(root.projectController.state))
    registry.projects[0].checkouts.push({
      id: 'c-other',
      path: '/other'
    })
    root.projectController.state = registry
    var environmentOperation = {
      id: 'env-op',
      environmentId: 'e-other',
      sessionId: 's',
      projectId: 'p',
      checkoutId: 'c-other',
      generation: 9,
      state: 'completed',
      outcome: 'partial'
    }
    root.projectClient.snapshot = Object.assign({}, root.projectClient.snapshot, {
      sessionId: 's',
      operations: [environmentOperation]
    })
    page.reconcileOperation(environmentOperation)
    t.equal(page.details.operation, null, 'environment operation never enters legacy Details recovery')
    t.equal(page.recoveryCheckoutId, 'c', 'environment report never retargets legacy recovery checkout')
    var legacyOperation = {
      id: 'legacy-op',
      sessionId: 's',
      projectId: 'p',
      checkoutId: 'c',
      generation: 1,
      state: 'completed',
      outcome: 'partial'
    }
    root.projectClient.snapshot = Object.assign({}, root.projectClient.snapshot, {
      operations: [legacyOperation, environmentOperation]
    })
    page.reconcileOperation(environmentOperation)
    t.equal(page.details.operation.id, 'legacy-op', 'ordinary legacy recovery remains available beside newer environment work')
    var environmentRow = overview.model.workspaces[0]
    t.equal(environmentRow.target, {
      projectId: 'p',
      environmentId: 'e-old'
    }, 'Overview keeps old environment independently of selected checkout')
    t.findChild(overview, 'overviewWorkspaces').detailsRequested(environmentRow.target)
    t.equal(overview.inspectedEnvironmentId, 'e-old', 'Details inspects exact retained environment')
    t.check(overview.inspectedEnvironment.fullDetail.indexOf('Codex') >= 0, 'Details names original saved tool even without current provider probe')
    overview.workspaceRequested('newWindow:agent', environmentRow.target)
    t.equal(nativeCalls[0], {
      method: 'recoverEnvironment',
      payload: {
        projectId: 'p',
        environmentId: 'e-old',
        newWindowRole: 'agent',
        activationId: 'a-00000000-0000-4000-8000-000000000019'
      }
    }, 'role recovery uses exact old environment with no selected checkout or profile override')
    root.projectClient.captureActive = true
    root.projectId = 'other'
    t.equal(root.actionClient.runId, 'accepted-run', 'selection preserves accepted run receipt')
    t.equal(root.actionClient.submissionTarget.checkoutId, 'c', 'selection preserves immutable submission target')
    t.check(!!JSON.parse(root.captureSnapshot()).actions, 'persistent capture owns shared action observations and receipts')
    root.captureActive = true
    root.projectClient.acceptanceUnknown = true
    root.projectClient.activationId = 'a-00000000-0000-4000-8000-000000000021'
    var saved = root.captureSnapshot()
    var beforeCapture = calls.length
    t.equal(root.captureBegin(JSON.stringify({
      snapshot: saved,
      projectId: '',
      fixture: {
        projectsState: {
          projects: [],
          roots: [],
          ignored: []
        },
        projectActions: {
          runId: 'fixture-run'
        }
      }
    })), 'ok', 'capture admits passive shared action observations')
    t.equal(root.actionClient.runId, 'fixture-run', 'inert fixture can substitute shared observation')
    t.check(!root.projectClient.acceptanceUnknown, 'inert fixture never inherits live launch uncertainty')
    t.equal(root.captureRestore(saved), 'ok', 'shared action capture restores successfully')
    t.equal(root.actionClient.runId, 'accepted-run', 'capture restores accepted receipt identity')
    t.check(root.projectClient.acceptanceUnknown, 'capture restores held launch uncertainty')
    t.equal(root.projectClient.activationId, 'a-00000000-0000-4000-8000-000000000021', 'capture retains original immutable recovery identity')
    t.equal(root.actionClient.submissionTarget.checkoutId, 'c', 'capture restores exact submitted checkout')
    t.equal(calls.length, beforeCapture, 'capture restoration never starts an action')
    t.done()
  })
}
