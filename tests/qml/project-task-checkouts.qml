// Fetch, pull and task checkout controls: components in isolation, then through the surface.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Fixture state for the isolated components.
  property var fetches: 0
  // Signals recorded from the header.
  property var headerSignals: []
  // Create requests recorded from the form.
  property var created: []
  // Confirm requests recorded from the removal card.
  property var confirmed: []
  // Git commands the surface sent, in order: {argv, done}.
  property var gitCalls: []
  // Git observation reads the surface made.
  property var readCalls: []
  // Registry refreshes answered by the held controller runner.
  property int registryReads: 0
  // Profile starts the surface emitted.
  property var starts: []
  QmlTest {
    id: t
  }
  Projects.ProjectGitSection {
    id: section
    width: 600
    git: host.gitState(2)
    onFetchRequested: host.fetches++
  }
  Projects.ProjectHeader {
    id: header
    width: 600
    project: host.project('p-h', 'c-p')
    onTaskCreateRequested: function (id) {
      host.headerSignals.push(['create', id])
    }
    onTaskRemoveRequested: function (id, checkout) {
      host.headerSignals.push(['remove', id, checkout])
    }
  }
  Projects.ProjectTaskForm {
    id: form
    width: 600
    project: host.project('p-f', 'c-p')
    onCreateRequested: function (branch) {
      host.created.push(branch)
    }
  }
  Projects.ProjectTaskRemove {
    id: removal
    width: 600
    checkout: {
      'id': 'c-l',
      'path': '/home/u/Work/myapp-worktrees/feat',
      'branch': 'feat',
      'primary': false
    }
    onConfirmRequested: function (unpushed) {
      host.confirmed.push(unpushed)
    }
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
  // One Git observation with the given commits behind.
  function gitState(behind, upstream) {
    return {
      branch: 'main',
      detached: false,
      upstream: upstream === undefined ? 'origin/main' : upstream,
      ahead: 0,
      behind: behind,
      counts: {},
      files: [],
      observedAt: Date.now()
    }
  }
  // Registered project with a primary and a linked checkout.
  function project(id, selected) {
    return {
      id: id,
      name: id,
      tools: {},
      profiles: [
        {
          id: 'pr',
          name: 'Code',
          roles: ['editor'],
          tools: {
            editorId: 'code'
          },
          revision: 1
        }
      ],
      lastProfileId: 'pr',
      lastCheckoutId: selected,
      checkouts: [
        {
          id: 'c-p',
          path: '/home/u/Work/myapp',
          branch: 'main',
          primary: true
        },
        {
          id: 'c-l',
          path: '/home/u/Work/myapp-worktrees/feat',
          branch: 'feat',
          primary: false
        }
      ]
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
  // Commands of one operation, in order.
  function only(operation) {
    return host.gitCalls.filter(function (c) {
      return c.argv[1] === operation
    })
  }
  // Answer one held Git command.
  function answer(index, response) {
    host.gitCalls[index].done(response.ok ? 0 : 1, JSON.stringify(response), '')
  }
  // Observation reply for a selected pair.
  function observation(argv) {
    return JSON.stringify({
      ok: true,
      error: null,
      data: {
        projectId: argv[2],
        checkoutId: argv[4],
        path: '/fixture',
        observedAt: Date.now(),
        branch: 'main',
        detached: false,
        upstream: 'origin/main',
        ahead: 0,
        behind: 1,
        counts: {},
        files: [],
        truncated: false
      }
    })
  }
  Component.onCompleted: t.step(80, function () {
    sectionChecks()
    headerChecks()
    formChecks()
    removeChecks()
    surfaceChecks()
  })
  function sectionChecks() {
    var fetch = t.findChild(section, 'projectGitFetch')
    var pull = t.findChild(section, 'projectGitPull')
    t.check(fetch.enabled && pull.enabled, 'Fetch and Pull are enabled when behind')
    t.equal(pull.text, 'Pull', 'Pull reads Pull when behind')
    fetch.clicked()
    t.equal(host.fetches, 1, 'Fetch emits fetchRequested once')
    section.git = host.gitState(0)
    t.equal(pull.text, 'Up to date', 'Pull reads Up to date')
    t.check(!pull.enabled, 'Pull is disabled when up to date')
    section.git = host.gitState(2, null)
    t.check(!pull.enabled && fetch.enabled, 'Pull is disabled without an upstream')
    section.git = host.gitState(2)
    section.commandPending = 'fetch'
    t.equal(fetch.text, 'Fetching…', 'Fetch reads Fetching while pending')
    t.check(!fetch.enabled && !pull.enabled, 'both are disabled while fetching')
    section.commandPending = 'pull'
    t.equal(pull.text, 'Pulling…', 'Pull reads Pulling while pending')
    section.commandPending = ''
    section.commandError = {
      message: 'No network.',
      recovery: 'Check the connection.'
    }
    t.equal(t.findChild(section, 'projectGitError').text, 'No network. Check the connection.', 'command error shows message and recovery')
    section.commandError = null
    section.displayOnly = true
    t.check(!fetch.enabled && !pull.enabled, 'display only disables both')
    section.displayOnly = false
  }
  function headerChecks() {
    var create = t.findChild(header, 'headerNewTask')
    var remove = t.findChild(header, 'headerRemoveTask')
    t.check(create.visible && create.enabled, 'New task checkout is available on the primary')
    t.check(!remove.visible, 'Remove is hidden on the primary')
    create.clicked()
    header.project = host.project('p-h', 'c-l')
    t.check(remove.visible, 'Remove is visible on a linked checkout')
    remove.clicked()
    t.equal(host.headerSignals, [['create', 'p-h'], ['remove', 'p-h', 'c-l']], 'header signals carry exact IDs')
  }
  function formChecks() {
    var field = t.findChild(form, 'projectTaskBranch')
    var preview = t.findChild(form, 'projectTaskPreview')
    var create = t.findChild(form, 'projectTaskCreate')
    field.text = 'feat/login'
    t.equal(preview.text, 'From the default branch · /home/u/Work/myapp-worktrees/feat-login', 'preview shows the folder')
    t.check(create.enabled, 'Create is enabled for a valid name')
    create.clicked()
    t.equal(host.created, ['feat/login'], 'Create emits the branch')
    field.accepted()
    t.equal(host.created, ['feat/login', 'feat/login'], 'Enter creates')
    field.text = 'a b'
    t.equal(preview.text, 'Branch names cannot contain spaces.', 'a space is explained')
    t.check(!create.enabled, 'Create is disabled for a bad name')
    field.accepted()
    t.equal(host.created.length, 2, 'Enter does nothing for a bad name')
    field.text = 'feat/login'
    form.error = {
      message: 'A branch named x already exists.',
      recovery: 'Choose another branch name.'
    }
    t.equal(field.text, 'feat/login', 'an error keeps the typed text')
    t.check(t.findChild(form, 'projectTaskError').text.indexOf('A branch named x already exists.') === 0, 'error is shown')
    form.pending = true
    t.equal(create.text, 'Creating task checkout…', 'Create reads pending')
    t.check(!create.enabled, 'Create is disabled while pending')
    form.pending = false
  }
  function removeChecks() {
    var confirm = t.findChild(removal, 'projectTaskRemoveConfirm')
    t.equal(t.findChild(removal, 'projectTaskRemoveQuestion').text, 'Remove the folder /home/u/Work/myapp-worktrees/feat? The branch feat is kept.', 'question names folder and branch')
    t.check(t.findChild(removal, 'projectTaskRemoveChecking').visible, 'Checking is shown while facts are null')
    t.check(!confirm.enabled, 'Confirm is disabled while checking')
    removal.facts = {
      dirty: false,
      untracked: false,
      busy: false,
      unpushed: 0,
      ignored: 0,
      missing: false
    }
    t.equal(confirm.text, 'Remove', 'clean facts read Remove')
    t.check(confirm.enabled, 'clean facts enable Confirm')
    confirm.clicked()
    removal.facts = {
      dirty: false,
      untracked: false,
      busy: false,
      unpushed: 3,
      ignored: 0,
      missing: false
    }
    t.equal(confirm.text, 'Remove anyway', 'unpushed commits read Remove anyway')
    t.equal(t.findChild(removal, 'projectTaskRemoveLines').count, 1, 'unpushed adds one line')
    t.equal(t.findChild(removal, 'projectTaskRemoveLines').itemAt(0).text, "3 commits aren't on any remote.", 'unpushed line text')
    confirm.clicked()
    t.equal(host.confirmed, [false, true], 'confirm carries the unpushed choice')
    removal.facts = {
      dirty: false,
      untracked: true,
      busy: false,
      unpushed: 0,
      ignored: 0,
      missing: false
    }
    t.check(!confirm.enabled, 'untracked files disable Confirm')
  }
  function surfaceChecks() {
    entry.projectController.runner = function (argv, input, done) {
      if (argv[1] === 'snapshot') {
        host.registryReads++
        Qt.callLater(function () {
          done(0, JSON.stringify({
            ok: true,
            state: entry.projectController.state
          }), '')
        })
        return
      }
      Qt.callLater(function () {
        done(0, JSON.stringify({
          ok: true,
          state: entry.projectController.state
        }), '')
      })
    }
    entry.gitClient.runner = function (argv, done) {
      host.readCalls.push(argv)
      Qt.callLater(function () {
        done(0, host.observation(argv), '')
      })
    }
    entry.gitCommands.runner = function (argv, done) {
      host.gitCalls.push({
        argv: argv,
        done: done
      })
    }
    entry.projectClient.runner = function () {}
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
    entry.captureActive = false
    var all = [host.project('p-a', 'c-p'), host.project('p-b', 'c-p')]
    host.show(all, 'p-a', 1)
    var fetch = t.findChild(surface, 'projectGitFetch')
    t.waitFor(function () {
      return host.readCalls.length > 0 && fetch.enabled
    }, 3000, 'Git section is ready', function () {
      fetch.clicked()
      t.equal(host.gitCalls.length, 1, 'Fetch sends one command')
      t.equal(host.gitCalls[0].argv.slice(1), ['fetch', '--project', 'p-a', '--checkout', 'c-p', '--json'], 'Fetch targets the selected pair')
      t.equal(fetch.text, 'Fetching…', 'Fetch shows pending')
      var before = host.readCalls.length
      host.answer(0, {
        ok: true,
        data: {},
        error: null
      })
      t.waitFor(function () {
        return host.readCalls.length === before + 1
      }, 3000, 'one Git refresh follows', function () {
        t.equal(host.readCalls[before].slice(1), ['--project', 'p-a', '--checkout', 'c-p', '--json'], 'the refresh reads the selected pair')
        staleFetch()
      })
    })
  }
  function staleFetch() {
    var fetch = t.findChild(surface, 'projectGitFetch')
    t.waitFor(function () {
      return fetch.enabled
    }, 3000, 'Fetch is idle', function () {
      host.gitCalls = []
      fetch.clicked()
      t.equal(host.gitCalls.length, 1, 'second Fetch starts')
      entry.projectId = 'p-b'
      t.step(150, function () {
        t.check(!t.findChild(surface, 'projectGitFetch').enabled, "Fetch on another project is disabled while a fetch is pending")
        var before = host.readCalls.length
        host.answer(0, {
          ok: false,
          data: null,
          error: {
            code: 'GIT_ERROR',
            message: 'The remote refused.',
            recovery: 'Try again.'
          }
        })
        t.step(150, function () {
          var errorLabel = t.findChild(surface, 'projectGitError')
          t.equal(host.readCalls.length, before, 'a result for an unselected pair triggers no Git refresh')
          t.check(!errorLabel.visible || errorLabel.text.indexOf('The remote refused.') < 0, "another project's section shows no command error")
          entry.projectId = 'p-a'
          t.waitFor(function () {
            var label = t.findChild(surface, 'projectGitError')
            return label.visible && label.text === 'The remote refused. Try again.'
          }, 3000, 'the error waits for its project', keepError)
        })
      })
    })
  }
  // Another pair's success never clears a stored error that belongs to a different pair.
  function keepError() {
    host.gitCalls = []
    entry.projectId = 'p-b'
    var fetch = t.findChild(surface, 'projectGitFetch')
    t.waitFor(function () {
      return fetch.enabled
    }, 3000, 'Fetch is idle on the other project', function () {
      fetch.clicked()
      t.equal(host.gitCalls.length, 1, 'Fetch on the other project starts')
      host.answer(0, {
        ok: true,
        data: {},
        error: null
      })
      t.step(150, function () {
        entry.projectId = 'p-a'
        t.waitFor(function () {
          var label = t.findChild(surface, 'projectGitError')
          return label.visible && label.text === 'The remote refused. Try again.'
        }, 3000, 'the first pair keeps its error', scopedCreate)
      })
    })
  }
  // A create started on one project never affects the form of another.
  function scopedCreate() {
    var header = t.findChild(surface, 'projectHeader')
    host.gitCalls = []
    t.findChild(header, 'headerNewTask').clicked()
    t.findChild(surface, 'projectTaskBranch').text = 'feat/x'
    t.findChild(surface, 'projectTaskCreate').clicked()
    t.equal(host.gitCalls.length, 1, 'Create on the first project starts')
    entry.projectId = 'p-b'
    t.step(100, function () {
      t.findChild(header, 'headerNewTask').clicked()
      var field = t.findChild(surface, 'projectTaskBranch')
      t.check(field.visible, "the other project's form opens")
      t.equal(field.text, '', 'the branch field starts empty for another project')
      t.equal(t.findChild(surface, 'projectTaskCreate').text, 'Create', "another project's form is not pending")
      host.answer(0, {
        ok: true,
        data: {
          checkoutId: 'c-x'
        },
        error: null
      })
      t.step(150, function () {
        t.check(t.findChild(surface, 'projectTaskBranch').visible, "a result for another project does not close this form")
        t.findChild(surface, 'projectTaskCancel').clicked()
        entry.projectId = 'p-a'
        t.step(100, createFlow)
      })
    })
  }
  function createFlow() {
    var header = t.findChild(surface, 'projectHeader')
    header.startProfile.connect(function (id, revision) {
      host.starts.push([id, revision])
    })
    host.gitCalls = []
    t.findChild(header, 'headerNewTask').clicked()
    var field = t.findChild(surface, 'projectTaskBranch')
    t.check(field.visible, 'the task form opens')
    t.check(field.activeFocus, 'the branch field has focus')
    field.text = 'feat/login'
    t.findChild(surface, 'projectTaskCreate').clicked()
    t.equal(host.gitCalls.length, 1, 'Create sends one command')
    t.equal(host.gitCalls[0].argv.slice(1), ['task-create', '--project', 'p-a', '--checkout', 'c-p', '--branch', 'feat/login', '--json'], 'Create names the branch')
    var reads = host.registryReads
    host.answer(0, {
      ok: true,
      data: {
        checkoutId: 'c-new'
      },
      error: null
    })
    t.waitFor(function () {
      return !field.visible && host.registryReads > reads
    }, 3000, 'the form closes and the registry refreshes', function () {
      t.equal(host.starts.length, 0, 'creating never launches')
      removeFlow()
    })
  }
  function removeFlow() {
    var header = t.findChild(surface, 'projectHeader')
    host.show([host.project('p-a', 'c-l'), host.project('p-b', 'c-p')], 'p-a', 2)
    host.gitCalls = []
    var remove = t.findChild(header, 'headerRemoveTask')
    t.waitFor(function () {
      return remove.visible
    }, 3000, 'Remove is offered on the linked checkout', function () {
      remove.clicked()
      t.equal(host.gitCalls.length, 1, 'Remove sends the check')
      t.equal(host.gitCalls[0].argv.slice(1), ['task-remove', '--project', 'p-a', '--checkout', 'c-l', '--check', '--json'], 'the check is a dry run')
      host.answer(0, {
        ok: true,
        data: {
          dirty: false,
          untracked: false,
          busy: false,
          unpushed: 0,
          ignored: 0,
          missing: false
        },
        error: null
      })
      var confirm = t.findChild(surface, 'projectTaskRemoveConfirm')
      t.check(t.findChild(surface, 'projectTaskRemove').activeFocus, 'the removal card has focus so Esc cancels')
      t.waitFor(function () {
        return confirm.enabled
      }, 3000, 'Confirm is enabled after the check', function () {
        confirm.clicked()
        t.equal(host.gitCalls.length, 2, 'Confirm sends the removal')
        t.equal(host.gitCalls[1].argv.slice(1), ['task-remove', '--project', 'p-a', '--checkout', 'c-l', '--json'], 'removal has no unpushed flag')
        host.answer(1, {
          ok: true,
          data: {},
          error: null
        })
        t.waitFor(function () {
          return surface.removeTarget === null
        }, 3000, 'the card closes', unpushedFlow)
      })
    })
  }
  // Unpushed commits need the explicit flag.
  function unpushedFlow() {
    var header = t.findChild(surface, 'projectHeader')
    host.show([host.project('p-a', 'c-l'), host.project('p-b', 'c-p')], 'p-a', 4)
    host.gitCalls = []
    var remove = t.findChild(header, 'headerRemoveTask')
    t.waitFor(function () {
      return remove.visible
    }, 3000, 'Remove is offered again', function () {
      remove.clicked()
      host.answer(0, {
        ok: true,
        data: {
          dirty: false,
          untracked: false,
          busy: false,
          unpushed: 2,
          ignored: 0,
          missing: false
        },
        error: null
      })
      var confirm = t.findChild(surface, 'projectTaskRemoveConfirm')
      t.waitFor(function () {
        return confirm.enabled && confirm.text === 'Remove anyway'
      }, 3000, 'Confirm reads Remove anyway', function () {
        confirm.clicked()
        t.equal(host.gitCalls[1].argv.slice(1), ['task-remove', '--project', 'p-a', '--checkout', 'c-l', '--confirm-unpushed', '--json'], 'unpushed removal passes the flag')
        host.answer(1, {
          ok: true,
          data: {},
          error: null
        })
        t.waitFor(function () {
          return surface.removeTarget === null
        }, 3000, 'the card closes again', inertChecks)
      })
    })
  }
  function inertChecks() {
    host.show([host.project('p-a', 'c-l'), host.project('p-b', 'c-p')], 'p-a', 3)
    host.gitCalls = []
    entry.captureActive = true
    t.step(60, function () {
      var names = ['projectGitFetch', 'projectGitPull', 'headerNewTask', 'headerRemoveTask']
      names.forEach(function (name) {
        var button = t.findChild(surface, name)
        if (button)
          button.clicked()
      })
      surface.requestTaskRemove('p-a', 'c-l')
      surface.runGit('fetch')
      t.equal(host.gitCalls.length, 0, 'capture sends no Git command')
      t.done()
    })
  }
}
