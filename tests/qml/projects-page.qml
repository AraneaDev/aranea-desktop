// Explicit review stays local until the real page emits Add selected.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

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
    page.displayOnly = true
    page.addSelected()
    t.equal(sent.length, 1, 'inert capture refuses registration')
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
          checkouts: [],
          lastCheckoutId: null
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
          projects: []
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
