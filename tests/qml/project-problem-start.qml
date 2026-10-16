// Start, Details and role recovery show the plain problem view instead of internal wording.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects/ProjectProblems.js" as Problems

ShellRoot {
  id: host
  // Held owner calls of the shared project client.
  property var calls: []
  // Open requests emitted by the standalone details view.
  property var opens: []
  // Activation id shared by the start scenarios.
  readonly property string activation: 'a-00000000-0000-4000-8000-000000000001'
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    visible: true
    width: 900
    height: 700
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Projects.ProjectDetails {
    id: details
    width: 500
    roleAutoDelay: 600000
    openAvailable: true
    project: ({
        id: 'p-one',
        name: 'Repo',
        lastCheckoutId: 'c-main',
        workspaceMode: 'dedicated',
        tools: {
          editorId: 'code',
          terminalId: 'kitty'
        },
        checkouts: [
          {
            id: 'c-main',
            path: '/repo',
            branch: 'main',
            primary: true
          }
        ]
      })
    onOpenRequested: function (payload) {
      host.opens.push(payload)
    }
  }
  // Project record with one editor profile that Start another can reuse.
  function project(id, profiles) {
    return {
      id: id,
      name: id,
      tools: {},
      profiles: profiles,
      lastProfileId: profiles.length ? profiles[0].id : null,
      lastCheckoutId: 'c-' + id,
      checkouts: [
        {
          id: 'c-' + id,
          path: '/fixture/' + id
        }
      ]
    }
  }
  // Saved editor profile.
  function profile() {
    return {
      id: 'f-a',
      name: 'VS Code',
      roles: ['editor'],
      tools: {
        editorId: 'code',
        terminalId: null,
        agentId: null
      },
      revision: 1
    }
  }
  // Publish a registry state and select one project.
  function show(projects, id, revision) {
    entry.projectController.state = {
      revision: revision,
      projects: projects,
      roots: [],
      ignored: []
    }
    entry.projectId = id
  }
  // Visible text of every label under a root.
  function texts(root) {
    var out = []
    t.childrenOf(root).forEach(function (item) {
      if (!item || item.visible === false)
        return
      if (typeof item.text === 'string' && item.text !== '')
        out.push(item.text)
      out = out.concat(texts(item))
    })
    return out
  }
  // Names of banned words found in a list of texts.
  function banned(list) {
    return list.filter(function (text) {
      return Problems.BANNED.some(function (word) {
        return new RegExp('\\b' + word + '\\b', 'i').test(text)
      })
    })
  }
  // Completed operation with one step in the given state.
  function roleOperation(role, status, reobserve) {
    return {
      id: 'op-' + role,
      projectId: 'p-one',
      checkoutId: 'c-main',
      state: 'completed',
      steps: [
        {
          role: role,
          status: status,
          reobserveAvailable: reobserve
        }
      ]
    }
  }
  Component.onCompleted: t.step(80, function () {
    entry.projectClient.runner = function (argv, done) {
      host.calls.push({
        method: argv[2],
        done: done
      })
    }
    entry.projectClient.autoCheckDelays = [50, 100, 150]
    entry.projectController.runner = function (argv, input, done) {
      if (argv[1] === 'snapshot')
        Qt.callLater(function () {
          done(0, JSON.stringify({
            ok: true,
            state: entry.projectController.state
          }), '')
        })
    }
    entry.gitClient.runner = function () {}
    entry.actionClient.runner = function () {}
    entry.projectClient.available = true
    entry.projectClient.snapshot = {
      availability: {
        compositor: true
      }
    }
    entry.projectController.tools = {
      defaults: {},
      editors: [
        {
          id: 'code',
          label: 'VS Code',
          available: true,
          supported: true
        }
      ],
      terminals: [],
      agents: []
    }
    entry.opened = true
    entry.view = surface
    host.show([host.project('p-one', [host.profile()]), host.project('p-bare', [])], 'p-one', 1)
    t.step(150, startCase)
  })
  // While checking, Start reads Starting and no problem is shown.
  function startCase() {
    var header = t.findChild(surface, 'projectHeader')
    entry.projectClient.startEnvironment({
      projectId: 'p-one',
      checkoutId: 'c-p-one',
      profileId: 'f-a',
      profileRevision: 1,
      activationId: host.activation
    })
    host.calls[0].done(1, '', 'acknowledgement lost')
    var problem = t.findChild(surface, 'projectStartProblem')
    t.check(entry.projectClient.autoChecking, 'automatic checks are running')
    t.equal(t.findChild(header, 'projectPrimaryStart').text, 'Starting…', 'Start reads Starting while checking')
    t.check(!problem.visible, 'no problem while checking')
    t.waitFor(function () {
      return !entry.projectClient.autoChecking
    }, 2000, 'checks end', function () {
      var answered = 0
      var answer = function () {
        host.calls.filter(function (c) {
          return c.method === 'environmentActivation'
        }).slice(answered).forEach(function (c) {
          c.done(0, JSON.stringify({
            ok: true,
            sessionId: 'owner-one',
            activationId: host.activation,
            found: false
          }), '')
          answered++
        })
      }
      answer()
      t.step(50, function () {
        answer()
        afterChecks()
      })
    })
  }
  // Answer the remaining lookups, then expect the unconfirmed problem.
  function afterChecks() {
    var answered = 0
    var pump = function () {
      var lookups = host.calls.filter(function (c) {
        return c.method === 'environmentActivation'
      })
      for (; answered < lookups.length; answered++)
        lookups[answered].done(0, JSON.stringify({
          ok: true,
          sessionId: 'owner-one',
          activationId: host.activation,
          found: false
        }), '')
    }
    var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 20; repeat: true; running: true }', host)
    timer.triggered.connect(pump)
    t.waitFor(function () {
      var problem = t.findChild(surface, 'projectStartProblem')
      return !entry.projectClient.autoChecking && problem.visible
    }, 4000, 'unconfirmed problem appears', function () {
      timer.stop()
      var problem = t.findChild(surface, 'projectStartProblem')
      t.equal(t.findChild(problem, 'projectProblemTitle').text, "Couldn't confirm it started", 'unconfirmed title')
      t.check(!!t.findChild(problem, 'projectProblemAction:checkAgain'), 'Check again offered')
      t.check(!!t.findChild(problem, 'projectProblemAction:startAnother'), 'Start another offered with a remembered profile')
      t.check(!t.findChild(problem, 'projectProblemAction:retry'), 'no retry for an unknown start')
      var before = host.calls.filter(function (c) {
        return c.method === 'environmentActivation'
      }).length
      t.findChild(problem, 'projectProblemAction:checkAgain').clicked()
      t.equal(host.calls.filter(function (c) {
        return c.method === 'environmentActivation'
      }).length, before + 1, 'Check again looks the start up once more')
      host.calls[host.calls.length - 1].done(0, JSON.stringify({
        ok: true,
        sessionId: 'owner-one',
        activationId: host.activation,
        found: false
      }), '')
      t.findChild(problem, 'projectProblemDetailsToggle').clicked()
      t.check(texts(problem).join('\n').indexOf(host.activation) >= 0, 'Details keep the request id')
      t.check(texts(problem).join('\n').indexOf('Earlier unresolved requests: 0') >= 0, 'Details keep the unresolved count')
      t.findChild(problem, 'projectProblemDetailsToggle').clicked()
      t.equal(banned(texts(t.findChild(surface, 'projectStartProblem').parent)), [], 'start block has no banned words')
      t.findChild(problem, 'projectProblemAction:startAnother').clicked()
      t.equal(entry.projectClient.unresolvedEnvironmentActivations.length, 1, 'the earlier start is kept as unresolved, not replayed')
      t.waitFor(function () {
        return host.calls.filter(function (c) {
          return c.method === 'startEnvironment'
        }).length === 2
      }, 2000, 'Start another sends a second start for the remembered profile', noProfileCase)
    })
  }
  // Without a remembered profile there is no Start another.
  function noProfileCase() {
    host.show([host.project('p-one', [host.profile()]), host.project('p-bare', [])], 'p-bare', 2)
    entry.projectClient.acceptanceUnknown = true
    entry.projectClient.requestError = {
      code: 'ACCEPTANCE_UNKNOWN',
      message: 'unknown'
    }
    entry.projectClient.stopAutoCheck()
    t.step(100, function () {
      var problem = t.findChild(surface, 'projectStartProblem')
      t.check(problem.visible, 'problem visible for the bare project')
      t.check(!!t.findChild(problem, 'projectProblemAction:checkAgain'), 'bare project can still check again')
      t.check(!t.findChild(problem, 'projectProblemAction:startAnother'), 'no Start another without a remembered profile')
      notRunningCase()
    })
  }
  // A request error maps to Projects isn't running.
  function notRunningCase() {
    entry.projectClient.acceptanceUnknown = false
    entry.projectClient.requestError = {
      code: 'OWNER_UNAVAILABLE',
      message: 'Project owner unavailable.'
    }
    t.step(100, function () {
      var problem = t.findChild(surface, 'projectStartProblem')
      t.equal(t.findChild(problem, 'projectProblemTitle').text, "Projects isn't running", 'not running title')
      t.check(!t.findChild(problem, 'projectProblemAction:retry'), 'no retry path exists for start errors, so none is offered')
      t.equal(banned(texts(problem.parent)), [], 'not running view has no banned words')
      entry.projectClient.requestError = null
      detailsCases()
    })
  }
  // A moved folder offers Locate folder; unconfirmed roles map to the existing recovery.
  function detailsCases() {
    details.operation = {
      id: 'op-moved',
      projectId: 'p-one',
      checkoutId: 'c-main',
      state: 'completed',
      steps: [],
      error: {
        code: 'CHECKOUT_INVALID',
        message: 'Folder missing.',
        recovery: 'Locate folder and retry.'
      }
    }
    var problem = t.findChild(details, 'projectOperationError')
    t.check(problem.visible, 'operation problem visible')
    t.equal(t.findChild(problem, 'projectProblemTitle').text, 'Folder moved or missing', 'moved title')
    var locate = t.findChild(problem, 'projectProblemAction:locate')
    t.check(!!locate, 'Locate folder offered')
    var picker = t.findChild(details, 'locateFolder:p-one:c-main')
    picker.chooserAvailable = false
    locate.clicked()
    t.check(picker.error.indexOf('Folder chooser unavailable') === 0, 'Locate folder runs the checkout folder chooser')
    details.operation = roleOperation('terminal', 'unconfirmed', true)
    var role = t.findChild(details, 'roleProblem:terminal')
    t.equal(t.findChild(role, 'projectProblemTitle').text, "Couldn't confirm it started", 'role uncertainty title')
    t.findChild(role, 'projectProblemAction:checkAgain').clicked()
    t.findChild(role, 'projectProblemAction:openAnother').clicked()
    t.equal(host.opens, [
      {
        projectId: 'p-one',
        checkoutId: 'c-main',
        reobserveRole: 'terminal'
      },
      {
        projectId: 'p-one',
        checkoutId: 'c-main',
        newWindowRole: 'terminal'
      }
    ], 'Check again and Open another window map to the existing role recovery')
    details.operation = roleOperation('editor', 'failed', false)
    t.check(!t.findChild(details, 'roleProblem:editor').visible, 'a failed role is not an unconfirmed problem')
    details.operation = roleOperation('terminal', 'unconfirmed', true)
    var all = texts(details).concat(texts(t.findChild(details, 'projectOperationError')))
    t.equal(banned(texts(role)), [], 'role recovery has no banned words')
    t.equal(banned(all), [], 'Details has no banned words')
    t.done()
  }
}
