// Explicit review stays local until the real page emits Add selected.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as ProjectUi
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Typed view requests collected without touching registry or desktop state.
  property var sent: []
  // Held Settings project backend responses drive canonical root and capture tests.
  property var entryResponses: []
  QmlTest {
    id: t
  }
  QtObject {
    id: discovery
    property var candidates: [
      {
        path: '/tmp/fixture/repo',
        name: 'Same',
        commonDir: '/tmp/fixture/repo/.git',
        checkouts: [
          {
            path: '/tmp/fixture/repo',
            branch: 'main',
            primary: true
          },
          {
            path: '/outside/worktree',
            branch: 'other',
            primary: false
          }
        ]
      },
      {
        path: '/other/repo',
        name: 'Same',
        commonDir: '/other/repo/.git',
        checkouts: []
      }
    ]
    property bool pending: false
    property bool partial: true
    property var errors: ['Depth limit reached']
    // No scan backend exists in this inert fixture.
    function start(id) {
      return false
    }
    // Cancellation only changes this fixture's observed state.
    function cancel() {
      pending = false
    }
  }
  ProjectUi.ProjectsPage {
    id: page
    width: 420
    discoveryClient: discovery
    registryState: ({
        roots: [
          {
            id: 'r-one',
            path: '/tmp/fixture'
          }
        ],
        ignored: [
          {
            path: '/ignored',
            commonDir: '/ignored/.git'
          }
        ],
        projects: []
      })
    onRegisterRequested: function (paths) {
      host.sent = host.sent.concat([paths])
    }
  }
  QtObject {
    id: owner
    property var snapshot: ({
        sessionId: 'session-one',
        availability: {
          compositor: true
        },
        operations: []
      })
    property bool available: true
    property bool pending: false
    property string error: ''
    // Inert owner operation observations never submit or launch desktop work.
    signal operationChanged(var operation)
  }
  // Held real-client refresh callbacks exercise the complete view recovery boundary.
  property var refreshCallbacks: []
  Projects.ProjectClient {
    id: refreshOwner
    runner: function (argv, done) {
      host.refreshCallbacks.push(done)
    }
  }
  ProjectUi.ProjectFolderPicker {
    id: picker
    chooserAvailable: false
  }
  ProjectUi.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 420
    implicitHeight: 260
    ProjectUi.ProjectsSurface {
      id: surface
      root: entry
      width: 420
      height: 260
    }
  }
  // Independent geometry checks use the existing production focus-reveal behavior.
  function checkActionLayout(surface, label) {
    var scroll = t.findChild(surface, 'settingsScrollBar').parent
    while (scroll && scroll.contentY === undefined)
      scroll = scroll.parent
    t.check(!!scroll && scroll.contentHeight > scroll.height, label + ' has scrollable action content')
    var names = ['actionExecutable', 'actionSave', 'actionCancel', 'actionStart:a-layout', 'actionRun:refresh', 'actionRun:logs', 'actionRun:stop', 'actionRun:restart']
    names.forEach(function (name) {
      var control = t.findChild(surface, name)
      t.check(!!control && control.visible && control.enabled, label + ' exposes ' + name)
      if (!control || !scroll)
        return
      control.forceActiveFocus(Qt.TabFocusReason)
      surface.revealFocus(control)
      var point = control.mapToItem(scroll.contentItem, 0, 0)
      t.check(control.activeFocus && point.y - scroll.contentY >= -1 && point.y - scroll.contentY + control.height <= scroll.height + 1 && point.x >= -1 && point.x + control.width <= scroll.width + 1, label + ' reveals complete ' + name + ' ' + JSON.stringify([point.x, point.y - scroll.contentY, control.width, control.height, scroll.width, scroll.height, control.activeFocus, surface.height, window.height, Style.fontBaseSize]))
    })
  }
  Component.onCompleted: t.step(50, function () {
    t.check(!!page.details.actions, 'actual Projects page includes action view')
    if (!page.details.actions) {
      t.done()
      return
    }
    page.details.actions.client.runner = function (argv, input, done) {}
    var fixturePage = t.findChild(surface, 'projectsPage')
    fixturePage.details.actions.client.runner = function (argv, input, done) {}

    page.candidateList.select('/tmp/fixture/repo', true)
    t.equal(sent.length, 0, 'selection alone never registers')
    page.addSelected()
    t.equal(sent, [['/tmp/fixture/repo']], 'only selected path is submitted')
    page.candidateList.select('/outside/worktree', true)
    t.equal(page.candidateList.selectedPaths, ['/tmp/fixture/repo', '/outside/worktree'], 'external worktree selected separately')
    t.equal(page.candidateList.groups.length, 2, 'duplicate names retain distinct groups')
    page.registryState = {
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-review',
          name: 'Same',
          commonDir: '/tmp/fixture/repo/.git',
          tools: {},
          workspaceMode: 'dedicated',
          lastCheckoutId: 'c-anchor',
          checkouts: [
            {
              id: 'c-anchor',
              path: '/tmp/fixture/repo'
            }
          ]
        }
      ]
    }
    t.equal(page.candidateList.groups.length, 2, 'anchor registration preserves unregistered related worktree group')
    page.candidateList.select('/tmp/fixture/repo', true)
    t.equal(page.candidateList.selectedPaths, ['/outside/worktree'], 'registered anchor cannot be reselected')
    page.addSelected()
    t.equal(sent[1], ['/outside/worktree'], 'external sibling can be added after anchor registration')
    page.registryState = {
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-review',
          name: 'Same',
          commonDir: '/tmp/fixture/repo/.git',
          tools: {},
          workspaceMode: 'dedicated',
          lastCheckoutId: 'c-anchor',
          checkouts: [
            {
              id: 'c-anchor',
              path: '/tmp/fixture/repo'
            },
            {
              id: 'c-external',
              path: '/outside/worktree'
            }
          ]
        }
      ]
    }
    t.equal(page.candidateList.groups.length, 1, 'fully registered group disappears after last selectable checkout is added')
    page.projectClient = owner
    page.projectId = 'p-review'
    owner.operationChanged({
      id: 'op-old',
      generation: 1,
      sessionId: 'session-one',
      projectId: 'p-review',
      checkoutId: 'c-anchor',
      state: 'completed',
      steps: [
        {
          role: 'terminal',
          status: 'unconfirmed'
        }
      ]
    })
    t.check(page.details.recoveryAllowed('terminal', 'new'), 'exact observed unconfirmed role offers explicit recovery')
    owner.snapshot = {
      sessionId: 'session-one',
      availability: {
        compositor: true
      },
      operations: [
        {
          id: 'op-old',
          generation: 1,
          sessionId: 'session-one',
          projectId: 'p-review',
          checkoutId: 'c-anchor',
          state: 'completed',
          steps: [
            {
              role: 'terminal',
              status: 'unconfirmed'
            }
          ]
        },
        {
          id: 'op-new',
          generation: 2,
          sessionId: 'session-one',
          projectId: 'p-review',
          checkoutId: 'c-anchor',
          state: 'completed',
          steps: [
            {
              role: 'terminal',
              status: 'observed'
            }
          ]
        }
      ]
    }
    t.check(!page.details.recoveryAllowed('terminal', 'new'), 'newer observed owner snapshot clears old unconfirmed recovery')
    t.equal(page.details.operation.id, 'op-new', 'snapshot selects latest exact checkout outcome')
    owner.snapshot = {
      sessionId: 'session-one',
      availability: {
        compositor: true
      },
      operations: [
        {
          id: 'op-other-checkout',
          generation: 3,
          sessionId: 'session-one',
          projectId: 'p-review',
          checkoutId: 'c-external',
          state: 'completed',
          steps: [
            {
              role: 'terminal',
              status: 'unconfirmed'
            }
          ]
        },
        {
          id: 'op-new',
          generation: 2,
          sessionId: 'session-one',
          projectId: 'p-review',
          checkoutId: 'c-anchor',
          state: 'completed',
          steps: [
            {
              role: 'terminal',
              status: 'observed'
            }
          ]
        }
      ]
    }
    t.equal(page.details.operation.id, 'op-new', 'another checkout outcome does not replace exact checkout recovery')
    owner.operationChanged({
      id: 'op-delayed',
      generation: 1,
      sessionId: 'session-one',
      projectId: 'p-review',
      checkoutId: 'c-anchor',
      state: 'completed',
      steps: [
        {
          role: 'terminal',
          status: 'unconfirmed'
        }
      ]
    })
    t.equal(page.details.operation.id, 'op-new', 'delayed client outcome cannot supersede newer snapshot generation')
    var recoverySnapshot = page.captureSnapshot()
    page.recoveryCheckoutId = 'c-external'
    page.captureRestore(recoverySnapshot)
    t.equal(page.recoveryCheckoutId, 'c-anchor', 'capture retains exact owner recovery checkout destination')
    owner.snapshot = {
      sessionId: 'session-two',
      availability: {
        compositor: true
      },
      operations: []
    }
    t.equal(page.details.operation, null, 'session change clears stale recovery')
    owner.operationChanged({
      id: 'op-stale',
      generation: 9,
      sessionId: 'session-one',
      projectId: 'p-review',
      checkoutId: 'c-anchor',
      state: 'completed',
      steps: [
        {
          role: 'terminal',
          status: 'unconfirmed'
        }
      ]
    })
    t.equal(page.details.operation, null, 'old-session event cannot resurrect recovery')
    page.projectClient = refreshOwner
    refreshOwner.refresh()
    refreshOwner.refresh()
    refreshCallbacks[1](0, JSON.stringify({
      sessionId: 'fresh-owner',
      availability: {
        compositor: true
      },
      operations: [
        {
          id: 'op-fresh',
          generation: 2,
          sessionId: 'fresh-owner',
          projectId: 'p-review',
          checkoutId: 'c-anchor',
          state: 'completed',
          steps: [
            {
              role: 'terminal',
              status: 'observed'
            }
          ]
        }
      ]
    }), '')
    refreshCallbacks[0](0, JSON.stringify({
      sessionId: 'fresh-owner',
      availability: {
        compositor: true
      },
      operations: [
        {
          id: 'op-stale',
          generation: 1,
          sessionId: 'fresh-owner',
          projectId: 'p-review',
          checkoutId: 'c-anchor',
          state: 'completed',
          steps: [
            {
              role: 'terminal',
              status: 'unconfirmed'
            }
          ]
        }
      ]
    }), '')
    t.equal(page.details.operation.id, 'op-fresh', 'real client inverted Refresh cannot restore stale recovery outcome')
    t.check(!page.details.recoveryAllowed('terminal', 'new'), 'older in-flight Refresh cannot enable another new window')
    refreshOwner.refresh()
    refreshCallbacks[2](0, JSON.stringify({
      sessionId: 'fresh-owner',
      availability: {
        compositor: true
      },
      operations: []
    }), '')
    t.equal(page.details.operation, null, 'genuinely current absent owner result clears recovery')
    refreshOwner.refresh()
    refreshCallbacks[3](0, JSON.stringify({
      sessionId: 'restarted-owner',
      availability: {
        compositor: true
      },
      operations: [
        {
          id: 'op-old-session',
          generation: 99,
          sessionId: 'fresh-owner',
          projectId: 'p-review',
          checkoutId: 'c-anchor',
          state: 'completed',
          steps: [
            {
              role: 'terminal',
              status: 'unconfirmed'
            }
          ]
        }
      ]
    }), '')
    t.equal(page.details.operation, null, 'current owner session change clears session-invalid recovery')
    page.displayOnly = true
    page.addSelected()
    t.equal(sent.length, 2, 'inert capture refuses registration')
    page.registryState = Object.assign({}, page.registryState, {
      ignored: [
        {
          path: '/ignored',
          commonDir: '/ignored/.git'
        }
      ]
    })
    t.check(page.partial, 'partial scan remains actionable')
    t.equal(page.ignored.length, 1, 'ignored review comes from durable metadata')
    picker.setPath('file:///tmp/a%20folder')
    t.equal(picker.pathDraft, '/tmp/a folder', 'file URLs normalize to editable absolute paths')
    picker.setPath('relative')
    t.check(!picker.validPath, 'relative folder rejected before backend')
    picker.choose()
    t.check(picker.error.length > 0, 'unavailable chooser explains editable fallback')
    t.check(picker.fallbackVisible, 'unavailable chooser offers editable fallback')
    entry.projectController.runner = function (argv, input, done) {
      host.sent = host.sent.concat([['backend', argv, input]])
      host.entryResponses.push(done)
    }
    entry.projectClient.runner = function (argv, done) {
      host.sent = host.sent.concat([['owner', argv]])
    }
    entry.view = surface
    entry.projectController.state = {
      revision: 1,
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-one',
          name: 'Saved',
          tools: {
            editorId: 'code',
            terminalId: 'kitty'
          },
          workspaceMode: 'dedicated',
          checkouts: [
            {
              id: 'c-real',
              path: '/real',
              branch: 'main',
              primary: true
            }
          ],
          lastCheckoutId: 'c-real'
        }
      ]
    }
    entry.projectController.tools = {
      defaults: {
        editorId: 'code',
        terminalId: 'kitty'
      },
      editors: [
        {
          id: 'code',
          label: 'Code',
          supported: true,
          available: true
        }
      ],
      terminals: [
        {
          id: 'kitty',
          label: 'Kitty',
          supported: true,
          available: true
        }
      ]
    }
    entry.discoveryClient.candidates = [
      {
        path: '/review',
        name: 'Review',
        commonDir: '/review/.git',
        checkouts: []
      }
    ]
    entry.open(JSON.stringify({
      section: 'projects',
      projectId: 'p-one'
    }))
    var observed = JSON.parse(entry.captureSnapshot())
    t.equal(observed.section, 'projects', 'IPC normalizes Projects destination')
    t.equal(observed.projectId, 'p-one', 'Details readback exposes exact project ID')
    t.check(observed.opened, 'Details readback reports actual opened surface')
    t.equal(entry.captureBegin(JSON.stringify({
      snapshot: entry.captureSnapshot(),
      section: 'projects',
      fixture: {
        state: {},
        projectsState: {
          roots: [],
          ignored: [],
          projects: []
        }
      }
    })), 'busy', 'unfinished project reads refuse capture')
    entry.projectController.reading = false
    entry.projectClient.pending = false
    var realPage = t.findChild(surface, 'projectsPage')
    realPage.details.setDraft('name', 'Unsaved')
    realPage.details.customized = true
    var locate = t.findChild(realPage, 'locateFolder:p-one:c-real')
    t.check(!!locate, 'registered checkout exposes stable Locate folder draft')
    if (locate)
      locate.setPath('/replacement draft')
    realPage.candidateList.select('/review', true)
    realPage.details.actions.addAction()
    realPage.details.actions.editor.setField('name', 'Unsaved action')
    realPage.details.actions.client.pending = true
    t.equal(entry.captureBegin('{}'), 'busy', 'capture cannot interrupt action acceptance or mutation')
    realPage.details.actions.client.pending = false
    var snapshot = entry.captureSnapshot()
    var before = sent.length
    t.equal(entry.captureBegin(JSON.stringify({
      snapshot: snapshot,
      section: 'projects',
      projectId: 'p-fixture',
      fixture: {
        state: {},
        projectsState: {
          roots: [],
          ignored: [],
          projects: [
            {
              id: 'p-fixture',
              name: 'Fixture',
              tools: {},
              workspaceMode: 'dedicated',
              checkouts: [
                {
                  id: 'c-fixture',
                  path: '/fixture',
                  branch: 'fixture',
                  primary: true
                }
              ],
              lastCheckoutId: 'c-fixture'
            }
          ]
        }
      }
    })), 'ok', 'Projects accepts typed inert fixtures')
    t.check(!entry.projectController.request('register', {
      paths: ['/fixture']
    }), 'capture refuses registry mutation before runner')
    t.check(!entry.discoveryClient.start('r-one'), 'capture refuses process discovery before runner')
    t.check(!entry.projectClient.request({
      projectId: 'p-fixture'
    }), 'capture refuses owner submission before runner')
    t.equal(sent.length, before, 'capture invokes no project backend process or owner')
    t.check(realPage.details.actions.client.captureActive, 'Settings capture gates action client before IO')
    entry.close()
    t.check(realPage.details.actions.client.captureActive, 'capture stays inert after Settings close')
    t.check(!entry.projectController.request('remove', {
      projectId: 'p-fixture'
    }), 'closing capture surface retains inert project boundary until restoration')
    t.check(!entry.projectClient.request({
      projectId: 'p-fixture'
    }), 'closed capture cannot submit live owner requests')
    t.equal(entry.captureRestore(snapshot), 'ok', 'capture restores prior Settings state')
    t.equal(entry.projectId, 'p-one', 'capture restores Details destination')
    t.equal(realPage.details.actions.editor.draft.name, 'Unsaved action', 'capture restores action draft')
    t.check(realPage.details.actions.editing, 'capture restores action editor visibility')
    t.equal(realPage.details.draft.name, 'Unsaved', 'capture restores unsaved project details draft')
    t.check(realPage.details.dirty && realPage.details.customized, 'capture restores draft status and customization disclosure')
    t.equal(realPage.candidateList.selectedPaths, ['/review'], 'capture restores explicit candidate selection')
    var restoredLocate = t.findChild(realPage, 'locateFolder:p-one:c-real')
    t.check(!!restoredLocate && restoredLocate.pathDraft === '/replacement draft', 'capture with different project restores Locate folder draft by stable IDs')
    t.check(surface.compact, 'Projects uses compact navigation on small screens')
    var beforeNavigation = sent.length
    entry.projectController.refresh()
    entry.projectClient.refresh()
    t.equal(sent.length, beforeNavigation + 3, 'Projects refreshes registry tools and owner observations')
    entryResponses[entryResponses.length - 2](0, JSON.stringify({
      ok: true,
      state: entry.projectController.state,
      error: null
    }), '')
    entryResponses[entryResponses.length - 1](0, JSON.stringify(entry.projectController.tools), '')
    entry.discoveryClient.candidates = [discovery.candidates[0]]
    entry.projectController.request('register', {
      paths: ['/tmp/fixture/repo']
    })
    entryResponses[entryResponses.length - 1](0, JSON.stringify({
      ok: true,
      state: {
        revision: 2,
        roots: [],
        ignored: [],
        projects: [
          {
            id: 'p-review',
            name: 'Same',
            commonDir: '/tmp/fixture/repo/.git',
            tools: {},
            workspaceMode: 'dedicated',
            lastCheckoutId: 'c-anchor',
            checkouts: [
              {
                id: 'c-anchor',
                path: '/tmp/fixture/repo'
              }
            ]
          }
        ]
      },
      error: null
    }), '')
    t.equal(entry.discoveryClient.candidates.length, 1, 'Settings registration retains sibling discovery cache')
    entry.discoveryClient.runner = function (argv, line, done) {
      return function () {}
    }
    entry.projectController.request('root-add', {
      path: '/raw/../canonical'
    })
    entryResponses[entryResponses.length - 1](0, JSON.stringify({
      ok: true,
      state: {
        revision: 2,
        roots: [
          {
            id: 'r-new',
            path: '/canonical'
          }
        ],
        ignored: [],
        projects: entry.projectController.state.projects
      },
      error: null
    }), '')
    t.equal(entry.discoveryClient.rootId, 'r-new', 'choosing folder scans its backend canonical root ID')
    // Real settings scrolling must reveal every action input/control at all widths.
    surface.section = 'actions'
    var view = realPage.details.actions
    view.client.pollInterval = 60000
    view.client.pending = false
    view.client.availability = {
      execution: true
    }
    var action = {
      id: 'a-layout',
      projectId: 'p-review',
      revision: 1,
      name: 'Layout action',
      kind: 'command',
      argv: ['printf', '<b>literal</b>'],
      cwdRelative: '.',
      timeoutSeconds: 300,
      previewUrl: null
    }
    var run = {
      id: 'r-layout',
      projectId: 'p-review',
      checkoutId: 'c-anchor',
      actionId: 'a-old',
      definitionRevision: 1,
      definitionHash: 'old',
      definitionSnapshot: action,
      processState: 'running',
      submissionUnconfirmed: false,
      readiness: 'unknown',
      cwd: '/tmp/fixture/repo',
      createdAt: 1
    }
    view.client.snapshot = {
      revision: 1,
      definitions: [action, Object.assign({}, action, {
          id: 'a-old'
        })],
      runs: [run],
      requests: []
    }
    view.client.currentRun = run
    view.client.runId = run.id
    view.addAction()
    surface.width = 840
    surface.height = 680
    t.step(100, function () {
      host.checkActionLayout(surface, 'wide')
      surface.width = 420
      t.step(100, function () {
        host.checkActionLayout(surface, 'narrow')
        Style.fontBaseSize = Math.round(Style.fontBaseSize * 1.5)
        var fonts = Object.assign({}, Style.fontOverrides)
        Object.keys(fonts).forEach(function (k) {
          fonts[k] = Math.round(Number(fonts[k]) * 1.5)
        })
        Style.fontOverrides = fonts
        t.step(100, function () {
          host.checkActionLayout(surface, 'narrow font 1.5')
          t.done()
        })
      })
    })
  })
}
