// Guided setup advances only from explicit, successful registry readback.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as ProjectUi

ShellRoot {
  // Explicit registry requests captured without native side effects.
  property var requests: []
  // Held callbacks exercise the real Settings composition wiring.
  property var responses: []
  // Best-effort visit metadata is acknowledged separately from held mandatory saves.
  property var navigationCalls: []
  QmlTest {
    id: t
  }
  QtObject {
    id: discovery
    property bool pending: false
    property bool partial: false
    property var errors: []
    property var candidates: [
      {
        name: 'Demo',
        path: '/work/demo',
        commonDir: '/work/demo/.git',
        checkouts: []
      }
    ]
  }
  ProjectUi.ProjectsPage {
    id: page
    width: 420
    discoveryClient: discovery
    registryState: ({
        roots: [],
        projects: [],
        ignored: []
      })
    tools: ({
        defaults: {
          editorId: 'code',
          terminalId: 'foot'
        },
        editors: [
          {
            id: 'code',
            label: 'VS Code',
            available: true,
            supported: true
          }
        ],
        terminals: [
          {
            id: 'foot',
            label: 'Foot',
            available: true,
            supported: true
          }
        ]
      })
    onRegisterRequested: function (paths) {
      requests.push(paths)
    }
  }
  ProjectUi.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    visible: true
    width: 420
    height: 620
    ProjectUi.ProjectsSurface {
      id: surface
      root: entry
      width: 420
      height: 620
    }
  }
  Component.onCompleted: t.step(80, function () {
    t.check(typeof page.startSetup === 'function', 'guided project setup is available')
    if (typeof page.startSetup !== 'function') {
      t.done()
      return
    }
    t.findChild(page, 'agentHelpToggle').activate()
    t.check(page.helpExpanded && page.helpTopic === 'agents', 'agent setup help is available without a registered project or bar item')
    t.equal(requests.length, 0, 'offline help performs no registry action')
    page.startBulkSetup()
    t.equal(page.setupStep, 0, 'setup starts with choosing a folder')
    page.advanceSetup()
    t.equal(page.setupStep, 0, 'cannot skip an unsaved folder')
    page.registryState = {
      roots: [
        {
          id: 'r',
          path: '/work'
        }
      ],
      projects: [],
      ignored: []
    }
    page.pending = true
    page.advanceSetup()
    t.equal(page.setupStep, 0, 'pending save blocks progress')
    page.pending = false
    page.advanceSetup()
    t.equal(page.setupStep, 1, 'approved folder permits repository review')
    page.candidateList.select('/work/demo', true)
    page.advanceSetup()
    t.equal(page.setupStep, 1, 'selection never counts as successful registration')
    t.equal(requests.length, 0, 'wizard navigation does not mutate the registry')
    page.addSelected()
    t.equal(requests, [['/work/demo']], 'explicit registration keeps exact selected paths')
    page.registryMutationCompleted('register', {
      paths: ['/other']
    }, {
      projects: []
    })
    t.equal(page.setupStep, 1, 'another registration cannot advance this setup')
    var project = {
      id: 'p-demo',
      name: 'Demo',
      lastCheckoutId: 'c',
      tools: {},
      checkouts: [
        {
          id: 'c',
          path: '/work/demo',
          branch: 'main'
        }
      ]
    }
    page.registryState = {
      roots: [
        {
          id: 'r',
          path: '/work'
        }
      ],
      ignored: [],
      projects: [project]
    }
    page.registryMutationCompleted('register', {
      paths: ['/work/demo']
    }, page.registryState)
    t.equal(page.setupStep, 2, 'successful exact registration opens configuration')
    t.equal(page.selectedProject.id, 'p-demo', 'configuration resolves returned project identity')
    page.details.actions.client.runner = function () {}
    page.details.setDraft('name', 'Renamed')
    page.backSetup()
    t.equal(page.setupStep, 2, 'Back cannot hide unsaved preferences behind another registration')
    page.advanceSetup()
    t.equal(page.setupStep, 2, 'unsaved preferences stay visible')
    page.registryMutationCompleted('configure', {
      projectId: 'unrelated'
    }, page.registryState)
    t.check(page.details.dirty, 'another project save cannot discard this draft')
    page.registryState = Object.assign({}, page.registryState, {
      projects: [Object.assign({}, project, {
          name: 'Renamed'
        })]
    })
    page.registryMutationCompleted('configure', {
      projectId: 'p-demo',
      name: 'Renamed'
    }, page.registryState)
    t.check(!page.details.dirty, 'successful preference save clears draft')
    page.details.actions.editing = true
    page.backSetup()
    t.equal(page.setupStep, 2, 'Back cannot hide an unsaved action draft')
    page.advanceSetup()
    t.equal(page.setupStep, 2, 'an unsaved action draft cannot be skipped')
    page.details.actions.editing = false
    page.advanceSetup()
    t.equal(page.setupStep, 3, 'saved preferences permit optional agent setup')
    var saved = page.captureSnapshot()
    page.finishSetup()
    t.check(!page.setupActive, 'finish returns to project management')
    page.projectId = 'p-demo'
    page.details.setDraft('name', 'Keep my draft')
    page.startBulkSetup()
    t.check(!page.setupActive && page.details.dirty, 'starting setup preserves an existing unsaved project draft')
    page.details.discardDraft()
    page.captureRestore(saved)
    t.check(page.setupActive && page.setupStep === 3, 'capture restores setup progress without I/O')
    page.captureReset({})
    t.check(!page.setupActive, 'inert fixture reset does not inherit setup progress')
    page.displayOnly = true
    page.startBulkSetup()
    t.check(!page.setupActive, 'read-only capture cannot start setup')
    t.equal(requests.length, 1, 'all progress and help controls remain local')
    quickSetup()
    bulkSetup()
    integratedSetup()
  })
  // Exact repository registration skips optional configuration stages.
  function quickSetup() {
    page.displayOnly = false
    page.startSetup()
    var picker = t.findChild(page, 'projectExactPicker')
    t.check(!!picker && picker.visible, 'Add project defaults to an exact repository')
    if (!picker) {
      page.captureReset({})
      return
    }
    picker.setPath('/work/exact')
    var before = requests.length
    picker.confirm()
    t.equal(requests[before], ['/work/exact'], 'exact folder uses existing registration transport')
    var project = {
      id: 'p-exact',
      name: 'Exact',
      tools: {},
      lastCheckoutId: 'c-exact',
      checkouts: [
        {
          id: 'c-exact',
          path: '/work/exact',
          branch: 'main'
        }
      ]
    }
    page.registryState = {
      roots: [],
      projects: [project],
      ignored: []
    }
    page.registryMutationCompleted('register', {
      paths: ['/wrong']
    }, page.registryState)
    t.check(page.setupActive, 'unrelated acknowledgement cannot finish exact registration')
    page.registryMutationCompleted('register', {
      paths: ['/work/exact']
    }, page.registryState)
    t.check(!page.setupActive, 'exact registration reaches usable Overview without configuration')
    t.equal(page.setupProjectId, 'p-exact', 'exact registration retains returned identity')
    page.captureReset({})
  }
  // A parent-folder batch configures every distinct repository in selection order.
  function bulkSetup() {
    page.displayOnly = false
    entry.projectClient.runner = function () {}
    entry.projectClient.pending = true
    page.projectClient = entry.projectClient
    page.startBulkSetup()
    t.check(!page.setupActive, 'setup cannot replace an in-flight project owner operation')
    t.check(!t.findChild(page, 'projectSetupStart').enabled, 'start button is disabled during an owner operation')
    page.projectClient = null
    entry.projectClient.pending = false
    page.startBulkSetup()
    page.advanceSetup()
    var first = {
      id: 'bulk-a',
      name: 'Alpha',
      tools: {},
      lastCheckoutId: 'a',
      checkouts: [
        {
          id: 'a',
          path: '/work/alpha'
        },
        {
          id: 'aw',
          path: '/work/alpha-feature'
        }
      ]
    }
    var second = {
      id: 'bulk-b',
      name: 'Beta',
      tools: {},
      lastCheckoutId: 'b',
      checkouts: [
        {
          id: 'b',
          path: '/work/beta'
        }
      ]
    }
    var unrelated = {
      id: 'other',
      name: 'Other',
      tools: {},
      checkouts: [
        {
          id: 'o',
          path: '/work/other'
        }
      ]
    }
    page.candidateList.selectedPaths = ['/work/alpha-feature', '/work/beta', '/work/alpha']
    page.addSelected()
    page.registryState = {
      roots: [
        {
          id: 'r',
          path: '/work'
        }
      ],
      ignored: [],
      projects: [unrelated, second, first]
    }
    page.registryMutationCompleted('register', {
      paths: ['/work/beta', '/work/alpha', '/work/alpha-feature']
    }, page.registryState)
    t.equal(page.selectedProject.id, 'bulk-a', 'bulk configuration follows selected paths rather than registry ordering')
    t.equal(page.setupProjectIds, ['bulk-a', 'bulk-b'], 'related worktrees configure once and unrelated projects are excluded')
    var progress = t.findChild(page, 'setupProgress')
    t.check(progress && progress.projectCount === 2 && progress.projectIndex === 0, 'bulk wizard exposes project 1 of 2')
    page.details.setDraft('name', 'Unsaved Alpha')
    page.advanceSetup()
    t.equal(page.selectedProject.id, 'bulk-a', 'next project cannot discard unsaved preferences')
    page.details.discardDraft()
    page.details.actions.editing = true
    page.advanceSetup()
    t.equal(page.selectedProject.id, 'bulk-a', 'next project cannot discard an action draft')
    page.details.actions.editing = false
    page.details.actions.client.pending = true
    page.advanceSetup()
    t.equal(page.selectedProject.id, 'bulk-a', 'pending action save blocks project navigation')
    page.details.actions.client.pending = false
    var count = requests.length
    page.advanceSetup()
    t.equal(page.setupStep, 2, 'next stays in configuration while projects remain')
    t.equal(page.selectedProject.id, 'bulk-b', 'next configures the second selected repository')
    t.equal(page.details.draft.name, 'Beta', 'next project starts with its own saved preferences')
    t.equal(requests.length, count, 'keeping defaults does not register or save again')
    page.details.setDraft('name', 'Unsaved Beta')
    page.backSetup()
    t.equal(page.selectedProject.id, 'bulk-b', 'previous project preserves dirty preferences')
    page.details.discardDraft()
    page.backSetup()
    t.equal(page.selectedProject.id, 'bulk-a', 'Back revisits the previous repository within configuration')
    page.advanceSetup()
    var saved = page.captureSnapshot()
    page.captureReset({})
    page.captureRestore(saved)
    t.equal(page.setupProjectIds, ['bulk-a', 'bulk-b'], 'capture preserves the complete project queue')
    t.equal(page.selectedProject.id, 'bulk-b', 'capture restores the exact current bulk project')
    page.advanceSetup()
    t.equal(page.setupStep, 3, 'agents stage appears only after the last project')
    page.backSetup()
    t.equal(page.selectedProject.id, 'bulk-b', 'Back from agent help returns to the last project')
    page.advanceSetup()
    page.finishSetup()
    page.captureReset({})
  }
  // Exercise chooser → real registry client → composition callbacks → next stage.
  function integratedSetup() {
    var realPage = t.findChild(surface, 'projectsPage')
    realPage.details.actions.client.runner = function () {}
    entry.projectClient.runner = function () {}
    entry.discoveryClient.runner = function () {
      return function () {}
    }
    entry.projectController.runner = function (argv, input, done) {
      var request = JSON.parse(input)
      if (request.action === 'profile-save') {
        var profile = Object.assign({}, request.args.profile, {
          id: 'f-preset-' + entry.projectController.state.revision,
          revision: 1
        })
        var presetState = Object.assign({}, entry.projectController.state, {
          revision: entry.projectController.state.revision + 1,
          projects: entry.projectController.state.projects.map(function (project) {
            return project.id === request.args.projectId ? Object.assign({}, project, {
              profiles: (project.profiles || []).concat([profile])
            }) : project
          })
        })
        done(0, JSON.stringify({
          ok: true,
          state: presetState
        }), '')
        return
      }
      if (request.action === 'navigation-set') {
        navigationCalls.push(request)
        var visits = {}
        visits[request.args.projectId] = Date.now()
        var state = Object.assign({}, entry.projectController.state, {
          revision: entry.projectController.state.revision + 1,
          navigation: {
            lastProjectId: request.args.projectId,
            pinnedProjectIds: [],
            visitedAt: visits
          }
        })
        done(0, JSON.stringify({
          ok: true,
          state: state
        }), '')
        return
      }
      responses.push(done)
    }
    entry.projectController.tools = page.tools
    entry.section = 'projects'
    realPage.startBulkSetup()
    var picker = t.findChild(realPage, 'projectFolderPicker')
    picker.setPath('/work')
    picker.confirm()
    t.check(entry.projectController.pending, 'wizard folder confirmation uses real registry client')
    t.equal(realPage.setupStep, 0, 'folder stage waits for backend approval')
    responses.pop()(1, JSON.stringify({
      ok: false,
      error: {
        message: 'Folder refused'
      }
    }), '')
    t.equal(realPage.setupStep, 0, 'failed folder save does not advance the wizard')
    t.check(!realPage.setupAwaitingFolder, 'failed folder save clears pending progress intent')
    picker.confirm()

    responses.pop()(0, JSON.stringify({
      ok: true,
      state: {
        revision: 1,
        roots: [
          {
            id: 'r-real',
            path: '/work'
          }
        ],
        projects: [],
        ignored: []
      }
    }), '')
    t.equal(realPage.setupStep, 1, 'successful folder readback advances real Settings wizard')
    t.equal(entry.discoveryClient.rootId, 'r-real', 'real setup scans only returned canonical root identity')
    entry.discoveryClient.pending = false
    entry.discoveryClient.candidates = discovery.candidates.concat([
      {
        name: 'Beta',
        path: '/work/beta',
        commonDir: '/work/beta/.git',
        checkouts: []
      }
    ])
    realPage.candidateList.select('/work/demo', true)
    realPage.addSelected()
    responses.pop()(1, JSON.stringify({
      ok: false,
      error: {
        message: 'Registration refused'
      }
    }), '')
    t.equal(realPage.setupStep, 1, 'failed registration stays on repository review')
    t.equal(realPage.candidateList.selectedPaths, ['/work/demo'], 'failed registration preserves explicit selection for retry')
    realPage.candidateList.select('/work/beta', true)
    realPage.addSelected()

    var project = {
      id: 'p-real',
      name: 'Demo',
      lastCheckoutId: 'c',
      tools: {},
      checkouts: [
        {
          id: 'c',
          path: '/work/demo',
          branch: 'main'
        }
      ]
    }
    var second = {
      id: 'p-beta',
      name: 'Beta',
      lastCheckoutId: 'b',
      tools: {},
      checkouts: [
        {
          id: 'b',
          path: '/work/beta',
          branch: 'main'
        }
      ]
    }
    var state = {
      revision: 2,
      roots: [
        {
          id: 'r-real',
          path: '/work'
        }
      ],
      ignored: [],
      projects: [project, second]
    }
    responses.pop()(0, JSON.stringify({
      ok: true,
      state: state
    }), '')
    t.equal(entry.projectId, 'p-real', 'registration routes returned ID to real Settings destination')
    t.equal(realPage.setupStep, 2, 'composition callback advances to configuration')
    realPage.details.setDraft('name', 'Saved name')
    realPage.details.applyDraft()
    t.check(entry.projectController.pending, 'wizard preferences use existing typed save boundary')
    realPage.details.setDraft('name', 'Edited during save')
    state = Object.assign({}, state, {
      revision: 3,
      projects: [Object.assign({}, project, {
          name: 'Saved name'
        }), second]
    })
    responses.pop()(0, JSON.stringify({
      ok: true,
      state: state
    }), '')
    t.equal(realPage.details.draft.name, 'Edited during save', 'save acknowledgement preserves a newer preference draft')
    t.check(realPage.details.dirty, 'newer preference edits remain unsaved after earlier acknowledgement')
    t.check(!realPage.setupCanContinue, 'earlier save does not release the newer draft navigation guard')
    realPage.details.applyDraft()
    state = Object.assign({}, state, {
      revision: 5,
      projects: [Object.assign({}, project, {
          name: 'Edited during save'
        }), second]
    })
    responses.pop()(0, JSON.stringify({
      ok: true,
      state: state
    }), '')
    t.check(!realPage.details.dirty, 'matching successful readback releases the preference draft guard')
    realPage.advanceSetup()
    t.equal(realPage.setupStep, 2, 'real batch stays in configuration for the second project')
    t.equal(realPage.selectedProject.id, 'p-beta', 'real batch selects the exact second identity')
    t.equal(t.findChild(surface, 'projectsSidebar').selectedId, 'p-beta', 'sidebar follows the current project in the bulk setup queue')
    realPage.details.setDraft('name', 'Unsaved second project')
    var exits = t.findChildren(surface, 'pill').filter(function (item) {
      return item.text === 'Exit setup' && item.visible
    })
    t.check(exits.length > 0 && exits.every(function (item) {
      return !item.enabled
    }), 'Exit setup controls refuse unsaved preferences')
    realPage.finishSetup()
    t.check(realPage.setupActive, 'Exit setup handler refuses unsaved preferences')
    t.equal(realPage.selectedProject.id, 'p-beta', 'refused Exit keeps the second project identity')
    t.equal(realPage.details.draft.name, 'Unsaved second project', 'refused Exit keeps the second project draft')
    realPage.details.discardDraft()
    realPage.details.actions.addAction()
    realPage.details.actions.editor.setField('name', 'Unsaved second action')
    exits = t.findChildren(surface, 'pill').filter(function (item) {
      return item.text === 'Exit setup' && item.visible
    })
    t.check(exits.length > 0 && exits.every(function (item) {
      return !item.enabled
    }), 'Exit setup controls refuse an action draft')
    realPage.finishSetup()
    t.check(realPage.setupActive && realPage.details.actions.editing, 'Exit setup handler preserves an action draft')
    t.equal(realPage.details.actions.editor.draft.name, 'Unsaved second action', 'refused Exit keeps action draft values')
    realPage.details.actions.editing = false
    realPage.advanceSetup()
    t.equal(realPage.setupStep, 3, 'real setup reaches optional agent instructions after all projects')
    realPage.finishSetup()
    t.check(!realPage.setupActive && entry.projectId === 'p-beta', 'finish keeps the exact last configured project selected')
    t.equal(navigationCalls, [
      {
        action: 'navigation-set',
        args: {
          projectId: 'p-real',
          visit: true
        },
        expectedRevision: 3
      },
      {
        action: 'navigation-set',
        args: {
          projectId: 'p-beta',
          visit: true
        },
        expectedRevision: 5
      }
    ], 'registration and finished wizard record each selected project once separately from mandatory saves')
    t.check(!entry.projectController.pending, 'acknowledged visit metadata leaves registry saves available')
    realPage.details.actions.client.captureActive = true
    realPage.setupActive = true
    realPage.setupProjectId = 'p-real'
    checkStageLayout(0, false)
  }
  // Real Settings focus reveal must expose the footer on every narrow wizard stage.
  function checkStageLayout(stage, large) {
    var realPage = t.findChild(surface, 'projectsPage')
    realPage.setupStep = stage
    t.step(80, function () {
      var scroll = t.findChild(surface, 'settingsScrollBar').parent
      while (scroll && scroll.contentY === undefined)
        scroll = scroll.parent
      var name = stage === 3 ? 'setupFinish' : 'setupNext'
      var control = t.findChildren(surface, name).filter(function (item) {
        return item.visible
      })[0]
      t.check(!!control && control.enabled, 'wizard stage ' + stage + ' exposes navigation at font scale ' + (large ? 1.5 : 1))
      if (control && scroll) {
        control.forceActiveFocus(Qt.TabFocusReason)
        surface.revealFocus(control)
        var position = control.mapToItem(scroll.contentItem, 0, 0)
        t.check(control.activeFocus && position.y - scroll.contentY >= -1 && position.y - scroll.contentY + control.height <= scroll.height + 1 && position.x >= -1 && position.x + control.width <= scroll.width + 1, 'wizard navigation is fully reachable at stage ' + stage)
      }
      if (stage < 3)
        checkStageLayout(stage + 1, large)
      else if (!large) {
        Style.fontBaseSize = Math.round(Style.fontBaseSize * 1.5)
        var fonts = Object.assign({}, Style.fontOverrides)
        Object.keys(fonts).forEach(function (key) {
          fonts[key] = Math.round(Number(fonts[key]) * 1.5)
        })
        Style.fontOverrides = fonts
        checkStageLayout(0, true)
      } else
        integratedExactSetup()
    })
  }
  // Default exact registration crosses the real controller and lands on Overview.
  function integratedExactSetup() {
    var realPage = t.findChild(surface, 'projectsPage')
    realPage.captureReset({})
    surface.chooseSection('preferences')
    realPage.startSetup()
    var picker = t.findChild(realPage, 'projectExactPicker')
    picker.setPath('/work/exact-native')
    picker.confirm()
    t.check(entry.projectController.pending && realPage.setupActive, 'exact registration waits for the actual controller acknowledgement')
    responses.pop()(1, JSON.stringify({
      ok: false,
      error: {
        message: 'Not a Git repository'
      }
    }), '')
    t.check(realPage.setupActive && picker.pathDraft === '/work/exact-native', 'failed exact registration retains the path for retry')
    picker.confirm()
    var exact = {
      id: 'p-exact-real',
      name: 'Exact repository',
      lastCheckoutId: 'c-exact',
      tools: {},
      checkouts: [
        {
          id: 'c-exact',
          path: '/work/exact-native',
          branch: 'main'
        }
      ]
    }
    responses.pop()(0, JSON.stringify({
      ok: true,
      state: {
        revision: 20,
        roots: [],
        ignored: [],
        projects: [exact]
      }
    }), '')
    t.equal(entry.projectId, exact.id, 'exact registration selects the returned identity')
    t.check(!realPage.setupActive && surface.section === 'overview', 'real exact registration goes directly from Preferences to Overview')
    t.equal(realPage.details.draft.editorId, 'code', 'available supported editor default is resolved without mandatory save')
    t.equal(realPage.details.draft.terminalId, 'foot', 'available supported terminal default is resolved without agent setup')
    t.check(!realPage.details.dirty, 'default tool resolution does not introduce an unsaved draft')
    t.done()
  }
}
