// The compact quick switcher drives the real Projects start and return paths and their guards.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects/ProjectProblems.js" as Problems

ShellRoot {
  id: host
  // Held owner calls of the shared project client.
  property var calls: []
  // Counter that gives every start a distinct launch identity.
  property int uuids: 0
  // Installed tool probe: one editor.
  readonly property var tools: ({
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
    })
  // select-checkout requests the controller sent.
  property var selects: []
  // Visible text of every switcher label seen in any state.
  property var seenTexts: []
  QmlTest {
    id: t
  }
  TestCase {
    id: keys
    when: false
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
  // Project record with one editor profile, or none.
  function project(id, name, withProfile) {
    return {
      id: id,
      name: name,
      tools: {},
      profiles: withProfile ? [
        {
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
      ] : [],
      lastProfileId: withProfile ? 'f-a' : null,
      lastCheckoutId: 'c-' + id,
      checkouts: [
        {
          id: 'c-' + id,
          path: '/fixture/' + name.toLowerCase()
        }
      ]
    }
  }
  // Publish the registry state.
  function show(projects) {
    entry.projectController.state = {
      revision: 1,
      projects: projects,
      roots: [],
      ignored: []
    }
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
  // Remember what the switcher shows right now.
  function note() {
    host.seenTexts = host.seenTexts.concat(texts(t.findChild(surface, 'projectSwitcher')))
  }
  // Held calls of one owner method.
  function method(name) {
    return host.calls.filter(function (c) {
      return c.method === name
    })
  }
  // Forget every in-flight client request between cases.
  function resetClient() {
    var c = entry.projectClient
    c.stopAutoCheck()
    c.generation++
    c.pending = false
    c.operationId = ''
    c.acceptanceUnknown = false
    c.requestError = null
    c.error = ''
    c.environmentTarget = null
    c.activationId = ''
    host.calls = []
  }
  // Open the switcher from closed.
  function openSwitcher() {
    resetClient()
    entry.opened = false
    return entry.open('{"mode":"switcher"}')
  }
  // The search field.
  function search() {
    return t.findChild(surface, 'projectSwitcherSearch')
  }
  // Row project ids in display order.
  function rowIds() {
    return t.findChild(surface, 'projectSwitcher').rows.map(function (r) {
      return r.id
    })
  }
  // Project id the Enter key acts on.
  function cursor() {
    return t.findChild(surface, 'projectSwitcher').cursorId
  }
  // Pump environment lookups with no match until the checks end.
  function pumpLookups(done) {
    var answered = 0
    var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 20; repeat: true; running: true }', host)
    timer.triggered.connect(function () {
      var lookups = host.method('environmentActivation')
      for (; answered < lookups.length; answered++)
        lookups[answered].done(0, JSON.stringify({
          ok: true,
          sessionId: 'owner-one',
          activationId: entry.projectClient.activationId,
          found: false
        }), '')
    })
    t.waitFor(function () {
      return !entry.projectClient.autoChecking && !entry.projectClient.pending
    }, 4000, 'automatic checks end', function () {
      timer.stop()
      done()
    })
  }
  Component.onCompleted: t.step(80, function () {
    entry.projectClient.runner = function (argv, done) {
      host.calls.push({
        method: argv[2],
        payload: argv[3],
        done: done
      })
    }
    entry.projectClient.identityRunner = function (done) {
      host.uuids++
      done('00000000-0000-4000-8000-00000000000' + host.uuids)
    }
    entry.projectClient.autoCheckDelays = [50, 100, 150]
    entry.projectController.runner = function (argv, input, done) {
      var action = input ? JSON.parse(input).action : argv[1]
      if (action === '--json')
        Qt.callLater(function () {
          done(0, JSON.stringify(host.tools), '')
        })
      if (action === 'select-checkout') {
        var args = JSON.parse(input).args
        host.selects.push(args)
        var next = JSON.parse(JSON.stringify(entry.projectController.state))
        next.projects.forEach(function (p) {
          if (p.id === args.projectId)
            p.lastCheckoutId = args.checkoutId
        })
        next.revision++
        Qt.callLater(function () {
          done(0, JSON.stringify({
            ok: true,
            state: next
          }), '')
        })
      }
      if (action === 'snapshot' || action === 'navigation-set' || action === 'profiles-seed')
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
      },
      environments: [
        {
          id: 'e-ret',
          projectId: 'p-ret',
          workspaceId: 3,
          generation: 1,
          profileSnapshot: {
            id: 'f-a',
            name: 'VS Code',
            roles: ['editor']
          },
          checkoutSnapshot: {
            branch: 'main',
            path: '/fixture/beta'
          },
          observedRoles: ['editor']
        }
      ]
    }
    entry.projectController.tools = host.tools
    entry.view = surface
    host.show([host.project('p-start', 'Alpha', true), host.project('p-ret', 'Beta', true), host.project('p-bare', 'Gamma', false)])
    t.step(100, openCase)
  })
  // The open payload shows the switcher with ordered rows, labels and the exact hint.
  function openCase() {
    t.equal(entry.mode, '', 'mode starts empty')
    t.equal(entry.open('{"mode":"switcher"}'), 'ok', 'switcher payload opens')
    t.equal(entry.mode, 'switcher', 'mode is switcher')
    t.check(entry.opened, 'window is open')
    t.step(100, function () {
      t.check(host.search().activeFocus, 'search field has focus')
      t.equal(host.rowIds(), ['p-start', 'p-ret', 'p-bare'], 'rows follow the navigation order')
      t.equal(t.findChild(surface, 'projectSwitcherAction:p-start').text, 'Start · VS Code', 'start label')
      t.equal(t.findChild(surface, 'projectSwitcherAction:p-ret').text, 'Return · workspace 3', 'return label')
      t.equal(t.findChild(surface, 'projectSwitcherAction:p-bare').text, 'Set up first', 'setup label')
      t.equal(t.findChild(surface, 'projectSwitcherHint').text, 'Enter: go · Alt+Enter: open in Projects · Esc: close', 'hint text')
      host.note()
      moveCase()
    })
  }
  // Typing filters; Down and Ctrl+J move the outlined row.
  function moveCase() {
    t.equal(host.cursor(), 'p-start', 'first row holds the cursor')
    t.check(t.findChild(surface, 'projectSwitcherRow:p-start').hasCursor, 'cursor row is outlined')
    keys.keyClick(Qt.Key_Down)
    t.equal(host.cursor(), 'p-ret', 'Down moves the cursor')
    t.check(t.findChild(surface, 'projectSwitcherRow:p-ret').hasCursor && !t.findChild(surface, 'projectSwitcherRow:p-start').hasCursor, 'only the cursor row is outlined')
    keys.keyClick(Qt.Key_J, Qt.ControlModifier)
    t.equal(host.cursor(), 'p-bare', 'Ctrl+J moves the cursor')
    keys.keyClick(Qt.Key_K, Qt.ControlModifier)
    t.equal(host.cursor(), 'p-ret', 'Ctrl+K moves it back')
    keys.keyClick(Qt.Key_Up)
    t.equal(host.cursor(), 'p-start', 'Up moves it up')
    keys.keyClick('b')
    keys.keyClick('e')
    keys.keyClick('t')
    t.equal(host.rowIds(), ['p-ret'], 'typing filters the rows')
    t.equal(host.cursor(), 'p-ret', 'filter puts the cursor on the first match')
    keys.keyClick(Qt.Key_Escape)
    t.check(!entry.opened, 'Escape closes')
    startCase()
  }
  // Enter on a start row starts the remembered profile once and closes on acceptance.
  function startCase() {
    t.equal(host.openSwitcher(), 'ok', 'reopens')
    t.check(host.search().text === '' && host.cursor() === 'p-start', 'reopening resets the search and cursor')
    t.step(60, function () {
      keys.keyClick(Qt.Key_Return)
      var starts = host.method('startEnvironment')
      t.equal(starts.length, 1, 'one start is sent')
      var sent = JSON.parse(starts[0].payload)
      t.equal({
        projectId: sent.projectId,
        checkoutId: sent.checkoutId,
        profileId: sent.profileId,
        profileRevision: sent.profileRevision
      }, {
        projectId: 'p-start',
        checkoutId: 'c-p-start',
        profileId: 'f-a',
        profileRevision: 1
      }, 'the start target is the row target')
      t.equal(entry.projectId, 'p-start', 'the row project is selected')
      t.check(entry.opened, 'switcher stays open until the start is accepted')
      starts[0].done(0, JSON.stringify({
        ok: true,
        operationId: 'op-one',
        environmentId: 'e-one'
      }), '')
      t.check(!entry.opened, 'acceptance closes the switcher')
      t.equal(host.method('startEnvironment').length, 1, 'still one start')
      returnCase()
    })
  }
  // Enter on a return row sends one return and closes on the observed return.
  function returnCase() {
    host.openSwitcher()
    // Closing now resets the mode, so the search field takes focus a moment after reopening.
    t.step(60, returnSend)
  }
  // Send the return from the reopened switcher.
  function returnSend() {
    keys.keyClick(Qt.Key_Down)
    keys.keyClick(Qt.Key_Return)
    var returns = host.method('returnEnvironment')
    t.equal(returns.length, 1, 'one return is sent')
    t.equal(JSON.parse(returns[0].payload), {
      projectId: 'p-ret',
      environmentId: 'e-ret'
    }, 'the return target is the row target')
    t.equal(host.method('startEnvironment').length, 0, 'no start is sent')
    returns[0].done(0, JSON.stringify({
      ok: true,
      operationId: 'op-ret',
      environmentId: 'e-ret'
    }), '')
    t.check(entry.opened, 'acceptance alone does not close')
    entry.projectClient.returnObserved('e-ret')
    t.check(!entry.opened, 'the observed return closes')
    changedCase()
  }
  // A return whose windows are gone shows the problem and a Start button that waits for a click.
  function changedCase() {
    host.openSwitcher()
    t.step(60, changedSend)
  }
  // Return from the reopened switcher; the windows turn out to be gone.
  function changedSend() {
    keys.keyClick(Qt.Key_Down)
    keys.keyClick(Qt.Key_Return)
    host.method('returnEnvironment')[0].done(0, JSON.stringify({
      ok: true,
      operationId: 'op-gone',
      environmentId: 'e-ret'
    }), '')
    var read = host.method('operation')[0]
    t.check(!!read, 'the return operation is read')
    read.done(0, JSON.stringify({
      id: 'op-gone',
      state: 'completed',
      projectId: 'p-ret',
      environmentId: 'e-ret',
      error: {
        code: 'ENVIRONMENT_CHANGED',
        message: 'The saved environment changed. Refresh Projects.'
      },
      steps: []
    }), '')
    t.step(100, function () {
      var problem = t.findChild(surface, 'projectSwitcherProblem')
      t.check(problem.visible, 'the problem is shown')
      t.equal(t.findChild(problem, 'projectProblemTitle').text, 'Changed elsewhere', 'plain title')
      var start = t.findChild(surface, 'projectSwitcherStart')
      t.check(start.visible, 'Start is offered')
      t.equal(host.method('startEnvironment').length, 0, 'nothing starts before the click')
      host.note()
      start.clicked()
      var starts = host.method('startEnvironment')
      t.equal(starts.length, 1, 'the click starts once')
      t.equal(JSON.parse(starts[0].payload).projectId, 'p-ret', 'for the same project')
      t.equal(JSON.parse(starts[0].payload).profileId, 'f-a', 'with its remembered profile')
      uncertainCase()
    })
  }
  // An uncertain start reads Starting while checks run, then shows the problem.
  function uncertainCase() {
    host.openSwitcher()
    t.step(60, function () {
      keys.keyClick(Qt.Key_Return)
      host.method('startEnvironment')[0].done(1, '', 'acknowledgement lost')
      t.check(entry.projectClient.autoChecking, 'checks are running')
      t.equal(t.findChild(surface, 'projectSwitcherAction:p-start').text, 'Starting…', 'row reads Starting')
      t.check(entry.opened, 'switcher stays open')
      t.check(!t.findChild(surface, 'projectSwitcherProblem').visible, 'no problem while checking')
      host.pumpLookups(function () {
        var problem = t.findChild(surface, 'projectSwitcherProblem')
        t.check(problem.visible, 'problem appears once checks end')
        t.equal(t.findChild(problem, 'projectProblemTitle').text, "Couldn't confirm it started", 'unconfirmed title')
        t.check(entry.opened, 'switcher still open')
        host.note()
        keys.keyClick(Qt.Key_Return)
        t.equal(host.method('startEnvironment').length, 1, 'Enter does not start again while the start is unconfirmed')
        busyCase()
      })
    })
  }
  // Enter does nothing while a request is being submitted.
  function busyCase() {
    host.openSwitcher()
    t.step(60, function () {
      entry.projectClient.pending = true
      t.check(entry.projectClient.submitting, 'client is submitting')
      keys.keyClick(Qt.Key_Return)
      keys.keyClick(Qt.Key_Down)
      keys.keyClick(Qt.Key_Return)
      t.equal(host.calls.filter(function (c) {
        return c.method === 'startEnvironment' || c.method === 'returnEnvironment'
      }).length, 0, 'no start or return is sent while submitting')
      entry.projectClient.pending = false
      guardCase()
    })
  }
  // Registry work in progress blocks Enter and Alt+Enter and the rows read Busy right now.
  function guardCase() {
    host.openSwitcher()
    t.step(60, function () {
      entry.projectController.pending = true
      t.equal(t.findChild(surface, 'projectSwitcherAction:p-start').text, 'Busy right now', 'row reads Busy right now')
      keys.keyClick(Qt.Key_Return)
      keys.keyClick(Qt.Key_Return, Qt.AltModifier)
      t.equal(entry.mode, 'switcher', 'Alt+Enter does nothing while busy')
      t.equal(host.method('startEnvironment').length, 0, 'Enter starts nothing while busy')
      host.note()
      entry.projectController.pending = false
      t.equal(t.findChild(surface, 'projectSwitcherAction:p-start').text, 'Start · VS Code', 'label returns when idle')
      outsideCase()
    })
  }
  // A click outside the card closes; a click inside does not.
  function outsideCase() {
    var backdrop = t.findChild(surface, 'projectSwitcherBackdrop')
    var card = t.findChild(surface, 'projectSwitcherCard')
    t.check(!!backdrop && !!card, 'backdrop and card exist')
    t.check(card.width <= 560 && card.height <= 440 && card.width > 0, 'card is compact')
    keys.mouseClick(backdrop, backdrop.width / 2, backdrop.height / 2)
    t.check(entry.opened, 'a click inside the card keeps it open')
    keys.mouseClick(backdrop, 3, 3)
    t.check(!entry.opened, 'a click outside closes')
    loadFailureCase()
  }
  // A read failure replaces the list even with stale projects.
  function loadFailureCase() {
    host.openSwitcher()
    t.step(60, function () {
      entry.projectController.error = 'Project registry not available.'
      var problem = t.findChild(surface, 'projectSwitcherLoadProblem')
      t.check(problem.visible, 'load problem shown')
      t.check(!t.findChild(surface, 'projectSwitcherList').visible, 'list hidden')
      keys.keyClick(Qt.Key_Return)
      t.equal(host.method('startEnvironment').length, 0, 'Enter starts nothing')
      host.note()
      entry.projectController.error = ''
      t.check(t.findChild(surface, 'projectSwitcherList').visible, 'list returns')
      expandCase()
    })
  }
  // Alt+Enter and Set up first open the full layout without launching.
  function expandCase() {
    host.openSwitcher()
    t.step(60, function () {
      keys.keyClick(Qt.Key_Return, Qt.AltModifier)
      t.equal(entry.mode, '', 'Alt+Enter leaves switcher mode')
      t.check(entry.opened, 'window stays open')
      t.equal(entry.projectId, 'p-start', 'the project is selected')
      t.equal(host.calls.filter(function (c) {
        return c.method === 'startEnvironment' || c.method === 'returnEnvironment'
      }).length, 0, 'nothing launches')
      host.openSwitcher()
      t.step(60, function () {
        keys.keyClick(Qt.Key_Down)
        keys.keyClick(Qt.Key_Down)
        t.equal(host.cursor(), 'p-bare', 'cursor on the project without a profile')
        keys.keyClick(Qt.Key_Return)
        t.equal(entry.mode, '', 'Set up first behaves like Alt+Enter')
        t.equal(entry.projectId, 'p-bare', 'that project is selected')
        t.equal(host.calls.filter(function (c) {
          return c.method === 'startEnvironment' || c.method === 'returnEnvironment'
        }).length, 0, 'still nothing launches')
        inertCase()
      })
    })
  }
  // The inert switcher refuses every action.
  function inertCase() {
    host.openSwitcher()
    t.step(60, function () {
      entry.captureActive = true
      keys.keyClick(Qt.Key_Return)
      keys.keyClick(Qt.Key_Down)
      keys.keyClick(Qt.Key_Return)
      keys.keyClick(Qt.Key_Return, Qt.AltModifier)
      t.equal(entry.mode, 'switcher', 'inert keeps the switcher')
      t.equal(host.calls.filter(function (c) {
        return c.method === 'startEnvironment' || c.method === 'returnEnvironment'
      }).length, 0, 'inert sends nothing')
      t.equal(entry.open('{"mode":"switcher"}'), 'busy', 'inert refuses to open')
      entry.captureActive = false
      draftCase()
    })
  }
  // An unsaved draft keeps the full layout.
  function draftCase() {
    resetAndFull()
  }
  // Open the full layout on a project and type into its name draft.
  function resetAndFull() {
    host.resetClient()
    entry.opened = false
    entry.projectId = 'p-start'
    entry.open('{}')
    t.step(100, function () {
      t.equal(entry.mode, '', 'a plain open uses the full layout')
      var page = t.findChild(surface, 'projectsPage')
      surface.chooseSection('preferences')
      page.details.setDraft('name', 'Changed')
      t.check(surface.hasUnsavedDraft, 'a draft exists')
      t.equal(entry.open('{"mode":"switcher"}'), 'busy', 'the switcher does not replace a draft')
      t.equal(entry.mode, '', 'layout is unchanged')
      t.check(page.details.dirty && page.details.draft.name === 'Changed', 'the draft survives')
      entry.close()
      t.equal(entry.open('{"mode":"switcher"}'), 'ok', 'a hidden window with a draft opens')
      t.equal(entry.mode, '', 'as the full layout')
      t.check(entry.opened && page.details.dirty && page.details.draft.name === 'Changed', 'the draft is kept')
      t.equal(host.calls.filter(function (c) {
        return c.method === 'startEnvironment' || c.method === 'returnEnvironment'
      }).length, 0, 'nothing launches')
      page.details.discardDraft()
      escapeCase()
    })
  }
  // An empty registry offers Add project, which opens setup.
  function emptyCase() {
    host.show([])
    host.openSwitcher()
    t.step(100, function () {
      var empty = t.findChild(surface, 'projectSwitcherEmpty')
      t.check(empty.visible, 'empty state shown')
      t.check(host.texts(empty).indexOf('No projects yet') >= 0, 'empty text')
      host.note()
      var add = t.findChild(surface, 'projectSwitcherAddProject')
      t.equal(add.text, 'Add project', 'button text')
      add.clicked()
      t.equal(entry.mode, '', 'Add project leaves switcher mode')
      t.check(t.findChild(surface, 'projectsPage').setupActive, 'setup is active')
      wordsCase()
    })
  }
  // Escape closes the switcher from any focused control, not only the search field.
  function escapeCase() {
    host.show([])
    host.openSwitcher()
    t.step(100, function () {
      var add = t.findChild(surface, 'projectSwitcherAddProject')
      add.forceActiveFocus()
      t.check(add.activeFocus && !host.search().activeFocus, 'focus is on a control other than the search field')
      keys.keyClick(Qt.Key_Escape)
      t.check(!entry.opened, 'Escape closes from a focused action')
      captureModeCase()
    })
  }
  // Capture never leaves a full-screen inert switcher behind, and closing forgets the mode.
  function captureModeCase() {
    host.show([host.project('p-start', 'Alpha', true), host.project('p-ret', 'Beta', true), host.project('p-bare', 'Gamma', false)])
    host.openSwitcher()
    t.step(100, function () {
      var snapshot = entry.captureSnapshot()
      t.equal(JSON.parse(snapshot).mode, 'switcher', 'the snapshot records the mode')
      var payload = JSON.stringify({
        snapshot: snapshot,
        fixture: {
          projectsState: {
            revision: 1,
            roots: [],
            ignored: [],
            projects: []
          }
        }
      })
      t.equal(entry.captureBegin(payload), 'ok', 'capture begins')
      t.equal(entry.mode, '', 'capture starts from the full layout')
      t.equal(entry.captureRestore(snapshot), 'ok', 'capture restores')
      t.equal(entry.mode, 'switcher', 'the switcher mode comes back')
      t.check(entry.opened, 'still open')
      // A desktop capture can ask for the compact switcher over the same inert fixture.
      var before = entry.captureSnapshot()
      var fixture = {
        projectsState: {
          revision: 1,
          roots: [],
          ignored: [],
          projects: [host.project('p-fixture', 'Fixture', true)]
        }
      }
      t.equal(entry.captureBegin(JSON.stringify({
        snapshot: before,
        mode: 'grid',
        fixture: fixture
      })), 'invalid', 'an unknown capture mode is refused')
      t.check(!entry.inert, 'a refused capture changes nothing')
      host.calls = []
      var selected = host.selects.length
      t.equal(entry.captureBegin(JSON.stringify({
        snapshot: before,
        mode: 'switcher',
        fixture: fixture
      })), 'ok', 'a switcher capture begins')
      t.equal(entry.mode, 'switcher', 'the capture shows the compact switcher')
      t.check(entry.inert, 'the switcher capture is inert')
      t.equal(host.rowIds().join(','), 'p-fixture', 'the switcher lists only the fixture projects')
      t.equal(host.calls.length + host.selects.length - selected, 0, 'the switcher capture asks the owner nothing')
      t.equal(entry.captureRestore(before), 'ok', 'the switcher capture restores')
      t.check(!entry.inert && entry.mode === 'switcher', 'the earlier presentation comes back')
      entry.captureActive = true
      var inertSwitcher = t.findChild(surface, 'projectSwitcher')
      inertSwitcher.forceActiveFocus()
      keys.keyClick(Qt.Key_Escape)
      t.check(!entry.opened, 'Escape closes even while display-only')
      entry.captureActive = false
      closeCase()
    })
  }
  // Closing keeps the compact card while the window fades out; the mode resets once it is gone.
  function closeCase() {
    t.check(!entry.opened, 'closed')
    host.openSwitcher()
    t.step(60, function () {
      entry.close()
      t.equal(entry.mode, 'switcher', 'the mode is kept during the close')
      t.check(t.findChild(surface, 'projectSwitcherCard').width <= 560, 'the card stays compact while closing')
      entry.closeFinished()
      t.equal(entry.mode, '', 'the mode resets once the window is gone')
      host.openSwitcher()
      entry.close()
      entry.open('{}')
      t.equal(entry.mode, '', 'an open without a mode gives the full layout')
      entry.close()
      entry.closeFinished()
      reviewCase()
    })
  }
  // Enter on a row with agent work to review opens that checkout's Overview and launches nothing.
  function reviewCase() {
    var withTask = host.project('p-start', 'Alpha', true)
    withTask.checkouts[0].primary = true
    withTask.checkouts.push({
      id: 'x-p-start',
      path: '/fixture/alpha-x',
      branch: 'feat/x',
      primary: false
    })
    host.show([withTask, host.project('p-ret', 'Beta', true), host.project('p-bare', 'Gamma', false)])
    entry.activityClient.snapshot = {
      tasks: [
        {
          id: 't1',
          taskId: 't1',
          reportedState: 'ready-for-review',
          lastReceivedAt: 100,
          verification: {
            status: 'reported-pass'
          },
          association: {
            status: 'registered',
            projectId: 'p-start',
            checkoutId: 'x-p-start'
          }
        }
      ],
      operations: []
    }
    host.selects = []
    host.openSwitcher()
    t.step(100, function () {
      var row = t.findChild(surface, 'projectSwitcherRow:p-start')
      t.equal(t.findChild(surface, 'projectSwitcherAction:p-start').text, 'Review · feat/x', 'the review label names the branch')
      t.check(!t.findChild(surface, 'projectSwitcherReviewChip:p-start').visible, 'a review row hides the chip, the action already says Review')
      t.check(!t.findChild(surface, 'projectSwitcherReviewChip:p-ret').visible, 'other rows show no chip')
      t.check(row.hasCursor, 'the review row holds the outline Enter acts on')
      host.note()
      keys.keyClick(Qt.Key_Return)
      t.equal(entry.mode, '', 'Enter leaves the switcher for the full layout')
      t.equal(entry.projectId, 'p-start', 'the project is selected')
      t.equal(surface.section, 'overview', 'the Overview shows')
      t.equal(host.method('startEnvironment').length + host.method('returnEnvironment').length, 0, 'nothing is launched')
      t.waitFor(function () {
        return host.selects.length === 1 && entry.selectedCheckoutId === 'x-p-start'
      }, 3000, 'the review checkout is selected', function () {
        t.equal(host.selects[0], {
          projectId: 'p-start',
          checkoutId: 'x-p-start'
        }, 'select-checkout names the review checkout')
        t.check(entry.opened, 'Projects stays open')
        entry.activityClient.snapshot = {
          tasks: [],
          operations: []
        }
        lateRowsCase()
      })
    })
  }
  // While an earlier start is unconfirmed, the other rows say they are busy.
  function lateRowsCase() {
    host.openSwitcher()
    t.step(60, function () {
      keys.keyClick(Qt.Key_Return)
      host.method('startEnvironment')[0].done(1, '', 'acknowledgement lost')
      host.pumpLookups(function () {
        t.check(entry.projectClient.acceptanceUnknown, 'the start is unconfirmed')
        t.equal(t.findChild(surface, 'projectSwitcherAction:p-ret').text, 'Busy right now', 'another row reads Busy right now')
        t.equal(t.findChild(surface, 'projectSwitcherAction:p-bare').text, 'Busy right now', 'and so does the setup row')
        t.equal(t.findChild(surface, 'projectSwitcherAction:p-start').text, 'Starting…', 'the unconfirmed row reads Starting')
        var selectsBefore = host.selects.length
        t.check(!surface.switcherGo({
          id: 'p-start',
          action: {
            kind: 'review',
            target: {
              projectId: 'p-start',
              checkoutId: 'x-p-start'
            }
          }
        }), 'a review row does nothing while the switcher is busy')
        t.equal(host.selects.length, selectsBefore, 'a busy review row selects no checkout')
        host.note()
        emptyCase()
      })
    })
  }
  // No banned word appears in any text the switcher showed.
  function wordsCase() {
    var hits = host.seenTexts.filter(function (text) {
      return Problems.BANNED.some(function (word) {
        return new RegExp('\\b' + word + '\\b', 'i').test(text)
      })
    })
    t.equal(hits, [], 'no banned words in switcher text')
    t.equal(host.seenTexts.filter(function (text) {
      return text.indexOf('\u2014') >= 0
    }), [], 'no em dashes in switcher text')
    t.equal(entry.projectClient.unresolvedEnvironmentActivations.length, 0, 'Start another was never used')
    t.done()
  }
}
