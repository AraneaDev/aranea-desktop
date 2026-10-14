// Draft navigation uses actual presentation, mutations and retained editor state.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held registry callbacks exercise authoritative draft acknowledgement.
  property var saves: []
  // Action saves hold only the real configure transport callback.
  property var actionSaves: []
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
  Component.onCompleted: t.step(80, function () {
    entry.projectController.runner = function (argv, input, done) {
      var request = JSON.parse(input)
      if (request.action === 'navigation-set') {
        done(0, JSON.stringify({
          ok: true,
          state: entry.projectController.state
        }), '')
      } else
        host.saves.push(done)
    }
    entry.projectClient.runner = function () {}
    entry.actionClient.runner = function (argv, input, done) {
      if (argv[argv.length - 1] === 'configure')
        host.actionSaves.push(done)
    }
    entry.gitClient.runner = function () {}
    var original = {
      id: 'p-original',
      name: 'Original',
      tools: {},
      lastCheckoutId: 'c-one',
      checkouts: [
        {
          id: 'c-one',
          path: '/fixture/one'
        }
      ]
    }
    var next = {
      id: 'p-next',
      name: 'Next',
      tools: {},
      lastCheckoutId: 'c-next',
      checkouts: [
        {
          id: 'c-next',
          path: '/fixture/next'
        }
      ]
    }
    entry.projectController.state = {
      revision: 1,
      projects: [original, next],
      roots: [],
      ignored: []
    }
    entry.projectController.tools = {
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
    }
    entry.view = surface
    entry.projectId = original.id
    var page = t.findChild(surface, 'projectsPage')
    surface.chooseSection('preferences')
    page.details.setDraft('name', 'Changed')
    entry.open(JSON.stringify({
      projectId: next.id
    }))
    var guard = t.findChild(surface, 'projectDraftGuard')
    t.check(!!guard && guard.opened, 'dirty project navigation opens focused draft guard')
    t.equal(entry.projectId, original.id, 'draft retains original selection until choice')
    if (!guard || !guard.opened) {
      t.done()
      return
    }
    guard.keepEditingRequested()
    t.equal(entry.projectId, original.id, 'keep editing preserves selection')
    t.check(page.details.dirty, 'keep editing retains dirty draft')
    surface.navigate(next.id)
    guard.discardRequested()
    t.equal(entry.projectId, next.id, 'explicit discard continues requested navigation')
    surface.navigate(original.id)
    surface.chooseSection('preferences')
    page.details.setDraft('name', 'Saved')
    surface.chooseSection('actions')
    guard.saveRequested()
    t.equal(surface.section, 'preferences', 'Save waits for authoritative acknowledgement')
    host.saves.pop()(1, JSON.stringify({
      ok: false,
      error: {
        message: 'Save refused'
      }
    }), '')
    t.equal(surface.section, 'preferences', 'failed Save leaves editor visible')
    t.check(page.details.dirty, 'failed Save retains draft')
    guard.saveRequested()
    host.saves.pop()(0, JSON.stringify({
      ok: true,
      state: {
        revision: 2,
        roots: [],
        ignored: [],
        projects: [Object.assign({}, original, {
            name: 'Saved'
          }), next]
      }
    }), '')
    t.step(40, function () {
      t.equal(surface.section, 'actions', 'matching successful Save continues destination')
      page.details.actions.addAction()
      page.details.actions.editor.setField('name', 'Retained on close')
      entry.close()
      t.check(page.details.actions.editing, 'closing Projects retains editor draft')
      t.equal(page.details.actions.editor.draft.name, 'Retained on close', 'close retains draft values')
      surface.navigate(next.id)
      guard.keepEditingRequested()
      t.check(page.details.actions.editing && entry.projectId === original.id, 'action Keep editing preserves identity and editor')
      surface.navigate(next.id)
      guard.saveRequested()
      t.check(page.details.actions.editing && entry.projectId === original.id && host.actionSaves.length === 0, 'invalid action Save keeps draft and selection without transport')
      page.details.actions.editor.setField('executable', 'true')
      guard.saveRequested()
      t.check(entry.actionClient.pending && entry.projectId === original.id, 'action Save waits for acknowledgement')
      host.actionSaves.pop()(1, JSON.stringify({
        ok: false,
        error: {
          code: 'ACTION_CONFLICT',
          message: 'Action changed'
        }
      }), '')
      t.check(page.details.actions.editing && entry.projectId === original.id && guard.opened, 'action save conflict retains draft and pending destination')
      guard.keepEditingRequested()
      surface.navigate(next.id)
      guard.discardRequested()
      t.equal(entry.projectId, next.id, 'action Discard continues project selection')
      surface.navigate(original.id)
      surface.chooseSection('actions')
      page.details.actions.addAction()
      page.details.actions.editor.setField('name', 'Valid action')
      page.details.actions.editor.setField('executable', 'true')
      surface.chooseSection('overview')
      guard.saveRequested()
      host.actionSaves.pop()(0, JSON.stringify({
        ok: true,
        error: null,
        state: {
          revision: 2,
          definitions: [],
          runs: [],
          requests: []
        }
      }), '')
      t.step(40, function () {
        t.check(!page.details.actions.editing && surface.section === 'overview', 'successful action Save continues destination')
        entry.actionClient.pending = true
        t.check(!surface.navigate(next.id), 'accepted mutation still serializes navigation')
        t.done()
      })
    })
  })
}
