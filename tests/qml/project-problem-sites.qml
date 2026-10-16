// Actions, Git, task checkouts, registry and setup show the plain problem view.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects/ProjectProblems.js" as Problems

ShellRoot {
  id: host
  // Fetch and pull requests recorded from the Git section.
  property var gitSignals: []
  // Refresh requests recorded from the overview and page.
  property var refreshes: []
  // Scans recorded from the page.
  property var scans: []
  // Transport calls of the actions client.
  property var calls: []
  // Project id of the fixtures.
  readonly property string pid: 'p-00000000-0000-4000-8000-000000000001'
  // Checkout id of the fixtures.
  readonly property string cid: 'c-00000000-0000-4000-8000-000000000001'
  QmlTest {
    id: t
  }
  Projects.ProjectGitSection {
    id: section
    width: 500
    git: ({
        branch: 'main',
        upstream: 'origin/main',
        ahead: 0,
        behind: 1,
        counts: {}
      })
    onFetchRequested: host.gitSignals.push('fetch')
    onPullRequested: host.gitSignals.push('pull')
    onRefreshRequested: host.gitSignals.push('refresh')
  }
  Projects.ProjectTaskForm {
    id: form
    width: 500
    project: ({
        id: 'p-f',
        name: 'Repo',
        lastCheckoutId: 'c-p',
        checkouts: [
          {
            id: 'c-p',
            path: '/home/u/Work/myapp',
            branch: 'main',
            primary: true
          }
        ]
      })
  }
  Projects.ProjectTaskRemove {
    id: removal
    width: 500
    checkout: ({
        id: 'c-l',
        path: '/home/u/Work/myapp-worktrees/feat',
        branch: 'feat',
        primary: false
      })
  }
  Projects.ProjectActionsClient {
    id: client
    projectId: host.pid
    checkoutId: host.cid
    autoCheckDelays: []
    runner: function (argv, input, done) {
      host.calls.push(argv[argv.length - 1])
    }
  }
  Projects.ProjectActions {
    id: actions
    width: 500
    sharedClient: client
    project: ({
        id: host.pid,
        lastCheckoutId: host.cid,
        checkouts: [
          {
            id: host.cid,
            path: '/repo',
            branch: 'main'
          }
        ]
      })
  }
  Projects.ProjectRunDetails {
    id: runDetails
    width: 500
    client: client
    checkout: ({
        id: host.cid,
        path: '/repo'
      })
    run: ({
        id: 'r-00000000-0000-4000-8000-000000000001',
        projectId: host.pid,
        checkoutId: host.cid,
        actionId: 'a-00000000-0000-4000-8000-000000000001',
        definitionRevision: 1,
        definitionSnapshot: {
          name: 'Build',
          kind: 'command',
          argv: ['make']
        },
        cwd: '/repo',
        processState: 'failed',
        createdAt: 1,
        error: {
          code: 'LAUNCH_FAILED',
          message: 'make was not found',
          recovery: 'Install it.'
        }
      })
  }
  Projects.ProjectOverview {
    id: overview
    width: 500
    model: ({
        git: null,
        services: [],
        checks: [],
        workspaces: [],
        agents: [],
        tasks: [],
        activity: {}
      })
    onActionRefreshRequested: host.refreshes.push('actions')
  }
  Projects.ProjectDiscoveryController {
    id: discovery
    runner: function (argv, line, done) {
      host.scans.push(argv)
      return function () {}
    }
  }
  Projects.ProjectsPage {
    id: page
    width: 500
    discoveryClient: discovery
    registryState: ({
        roots: [
          {
            id: 'r-one',
            path: '/tmp/fixture'
          }
        ],
        ignored: [],
        projects: []
      })
    onRefreshRequested: host.refreshes.push('registry')
    onDiscoverRequested: function (id) {
      host.scans.push(['again', id])
    }
  }
  // Title, body and action ids of one problem view.
  function shown(view) {
    if (!view || !t.findChild(view, 'projectProblemTitle')) {
      t.check(false, 'problem view missing: ' + view)
      return {
        title: '',
        body: '',
        actions: []
      }
    }
    var ids = view.problem.actions.map(function (a) {
      return a.id
    })
    return {
      title: t.findChild(view, 'projectProblemTitle').text,
      body: t.findChild(view, 'projectProblemBody').text,
      actions: ids
    }
  }
  // Catch banned internal words in what a problem view shows.
  function clean(view, name) {
    var s = shown(view)
    t.check(!Problems.bannedIn(s.title) && !Problems.bannedIn(s.body), name + ' has no banned word')
  }
  Component.onCompleted: t.step(100, function () {
    gitChecks()
    formAndRemoveChecks()
    actionChecks()
    runChecks()
    registryChecks()
    discoveryChecks()
    t.done()
  })
  // Catch raw Git text, wrong retry mapping and missing last-read note.
  function gitChecks() {
    var view = t.findChild(section, 'projectGitError')
    section.commandOperation = 'fetch'
    section.commandError = {
      code: 'NOT_FAST_FORWARD',
      message: 'Branches have diverged; merge or rebase in a terminal.'
    }
    var s = shown(view)
    t.equal(s.title, "Git couldn't do that", 'diverged title')
    t.equal(s.body, 'Branches have diverged; merge or rebase in a terminal.', 'diverged body is kept')
    t.equal(s.actions, [], 'diverged offers nothing')
    clean(view, 'git')
    section.commandError = {
      code: 'GIT_TIMEOUT',
      message: 'Git took too long.',
      recovery: 'Try again.'
    }
    t.equal(shown(view).actions, ['retry'], 'timeout offers Retry')
    t.equal(view.problem.details.recovery, 'Try again.', 'recovery stays under details')
    t.findChild(view, 'projectProblemAction:retry').clicked()
    t.equal(host.gitSignals, ['fetch'], 'Retry repeats the fetch')
    section.commandOperation = 'pull'
    t.findChild(view, 'projectProblemAction:retry').clicked()
    t.equal(host.gitSignals, ['fetch', 'pull'], 'Retry repeats the pull')
    section.commandError = null
    section.error = {
      code: 'GIT_TIMEOUT',
      message: 'Git took too long.'
    }
    t.equal(shown(view).actions, ['retry'], 'a failed read offers Retry')
    t.findChild(view, 'projectProblemAction:retry').clicked()
    t.equal(host.gitSignals[2], 'refresh', 'Retry repeats the read')
    var stale = t.findChild(section, 'projectGitStale')
    t.check(stale.visible, 'last read is noted when data is shown')
    t.check(!Problems.bannedIn(stale.text), 'stale note has no banned word')
    section.error = null
  }
  // Catch lost branch text and wrong kinds for task errors.
  function formAndRemoveChecks() {
    var field = t.findChild(form, 'projectTaskBranch')
    field.text = 'feat/login'
    form.error = {
      code: 'BRANCH_EXISTS',
      message: 'A branch named feat/login already exists.',
      recovery: 'Choose another branch name.'
    }
    var view = t.findChild(form, 'projectTaskError')
    var s = shown(view)
    t.equal(s.title, "Git couldn't do that", 'branch exists title')
    t.equal(s.body, 'A branch named feat/login already exists.', 'branch exists keeps the message')
    t.equal(field.text, 'feat/login', 'typed branch is kept')
    clean(view, 'task form')
    removal.error = {
      code: 'CHECKOUT_DIRTY',
      message: 'This checkout has uncommitted changes.',
      recovery: 'Commit or stash them.'
    }
    var remove = t.findChild(removal, 'projectTaskRemoveError')
    s = shown(remove)
    t.equal(s.title, "Can't do that here", 'dirty title')
    t.equal(s.body, 'This checkout has uncommitted changes.', 'dirty keeps the message')
    t.equal(remove.problem.details.recovery, 'Commit or stash them.', 'dirty recovery under details')
    clean(remove, 'task remove')
  }
  // Catch a second run being started, or no check offered, for an uncertain submission.
  function actionChecks() {
    client.submissionUncertain = true
    var view = t.findChild(actions, 'actionSubmissionProblem')
    t.check(view.visible, 'uncertain submission shows the problem')
    var s = shown(view)
    t.equal(s.title, "Couldn't confirm it started", 'uncertain title')
    t.equal(s.actions, ['checkAgain'], 'uncertain offers Check again')
    clean(view, 'actions submission')
    host.calls = []
    t.findChild(view, 'projectProblemAction:checkAgain').clicked()
    t.equal(host.calls[0], 'snapshot', 'Check again reads the snapshot')
    t.check(host.calls.every(function (c) {
      return ['snapshot', 'availability', 'detect'].indexOf(c) >= 0
    }), 'Check again never starts a run')
    client.submissionUncertain = false
    client.error = {
      code: 'REGISTRY_CONFLICT',
      message: 'Changed.',
      recovery: 'Refresh.'
    }
    var error = t.findChild(actions, 'actionClientProblem')
    s = shown(error)
    t.equal(s.title, 'Changed elsewhere', 'client error title')
    t.equal(s.actions, ['refresh'], 'client error offers Refresh')
    clean(error, 'actions error')
    client.error = null
    overview.actionProblem = {
      code: 'SUBMISSION_UNCONFIRMED'
    }
    var panel = t.findChild(overview, 'overviewActionProblem')
    t.equal(shown(panel).title, "Couldn't confirm it started", 'overview uncertain title')
    t.equal(shown(panel).actions, ['checkAgain'], 'overview offers Check again')
    t.findChild(panel, 'projectProblemAction:checkAgain').clicked()
    t.equal(host.refreshes, ['actions'], 'overview Check again refreshes')
    clean(panel, 'overview actions')
  }
  // Catch a Retry that is offered when restart is not allowed, or that starts anything else.
  function runChecks() {
    var view = t.findChild(runDetails, 'actionRunProblem')
    t.equal(shown(view).title, "Couldn't start", 'launch failure title')
    t.equal(shown(view).actions, [], 'no Retry while restart is not allowed')
    client.snapshot = {
      revision: 1,
      definitions: [
        {
          id: 'a-00000000-0000-4000-8000-000000000001',
          projectId: host.pid,
          name: 'Build',
          kind: 'command',
          argv: ['make'],
          revision: 1
        }
      ],
      runs: [],
      requests: []
    }
    t.equal(shown(view).actions, ['retry'], 'Retry is offered when restart is allowed')
    clean(view, 'run details')
  }
  // Catch registry conflicts without the Changed elsewhere view.
  function registryChecks() {
    page.errorObject = {
      code: 'REGISTRY_CONFLICT',
      message: 'The registry changed.',
      recovery: 'Refresh.'
    }
    page.error = 'The registry changed. Refresh.'
    var view = t.findChild(page, 'projectsPageProblem')
    t.equal(shown(view).title, 'Changed elsewhere', 'registry conflict title')
    t.equal(shown(view).actions, ['refresh'], 'registry conflict offers Refresh')
    t.findChild(view, 'projectProblemAction:refresh').clicked()
    t.equal(host.refreshes[host.refreshes.length - 1], 'registry', 'Refresh re-reads')
    clean(view, 'registry')
    page.errorObject = null
    page.error = 'Something plain.'
    page.errorObject = {
      message: 'Something plain.'
    }
    t.equal(shown(view).title, 'Something went wrong', 'a text-only error is unknown')
  }
  // Catch a discovery failure that shows raw text or maps Retry to the wrong scan.
  function discoveryChecks() {
    t.check(discovery.start('r-one'), 'scan starts')
    discovery.failure = {
      code: 'READ_FAILED',
      message: 'Discovery failed. Check the folder and retry.'
    }
    discovery.pending = false
    var view = t.findChild(page, 'projectsDiscoveryProblem')
    t.equal(shown(view).title, "Couldn't start", 'discovery failure kind')
    t.equal(shown(view).actions, ['retry'], 'discovery offers Retry')
    t.findChild(view, 'projectProblemAction:retry').clicked()
    t.equal(host.scans[host.scans.length - 1], ['again', 'r-one'], 'Retry scans the same folder again')
    clean(view, 'discovery')
  }
}
