// Explicit review stays local until the real page emits Add selected.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings
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
  Settings.ProjectsPage {
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
  Settings.ProjectFolderPicker {
    id: picker
    chooserAvailable: false
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: function (argv, done) {}
  }
  FloatingWindow {
    visible: true
    implicitWidth: 420
    implicitHeight: 260
    Settings.SettingsSurface {
      id: surface
      root: entry
      width: 420
      height: 260
    }
  }
  Component.onCompleted: t.step(50, function () {
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
    entry.close()
    t.check(!entry.projectController.request('remove', {
      projectId: 'p-fixture'
    }), 'closing capture surface retains inert project boundary until restoration')
    t.check(!entry.projectClient.request({
      projectId: 'p-fixture'
    }), 'closed capture cannot submit live owner requests')
    t.equal(entry.captureRestore(snapshot), 'ok', 'capture restores prior Settings state')
    t.equal(entry.projectId, 'p-one', 'capture restores Details destination')
    t.equal(realPage.details.draft.name, 'Unsaved', 'capture restores unsaved project details draft')
    t.check(realPage.details.dirty && realPage.details.customized, 'capture restores draft status and customization disclosure')
    t.equal(realPage.candidateList.selectedPaths, ['/review'], 'capture restores explicit candidate selection')
    var restoredLocate = t.findChild(realPage, 'locateFolder:p-one:c-real')
    t.check(!!restoredLocate && restoredLocate.pathDraft === '/replacement draft', 'capture with different project restores Locate folder draft by stable IDs')
    t.check(surface.compact, 'Projects uses compact navigation on small screens')
    entry.section = 'appearance'
    var beforeNavigation = sent.length
    var navigation = t.findChild(surface, 'settingsNavigation')
    navigation.choose('projects')
    t.equal(entry.section, 'projects', 'keyboard category action reaches Projects')
    t.equal(sent.length, beforeNavigation + 3, 'Projects navigation refreshes private registry tools and live observations')
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
    t.done()
  })
}
