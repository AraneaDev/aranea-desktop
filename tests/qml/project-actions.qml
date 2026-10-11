// Production action view plus actual client; only transport is injected.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as ProjectUi

ShellRoot {
  id: root
  // Only backend transport is replaced; all view/client logic remains production.
  property var calls: []
  QmlTest {
    id: t
  }
  ProjectUi.ProjectActions {
    id: actions
    width: 380
    displayOnly: true
    project: ({
        id: 'p-00000000-0000-4000-8000-000000000001',
        lastCheckoutId: 'c-00000000-0000-4000-8000-000000000001',
        checkouts: [
          {
            id: 'c-00000000-0000-4000-8000-000000000001',
            path: '/repo one',
            branch: 'main'
          },
          {
            id: 'c-00000000-0000-4000-8000-000000000002',
            path: '/repo two',
            branch: 'next'
          }
        ]
      })
  }
  // Approved definition fixture preserves opaque identity and displayed revision.
  function definition(revision) {
    return {
      id: 'a-00000000-0000-4000-8000-000000000001',
      projectId: 'p-00000000-0000-4000-8000-000000000001',
      name: 'Checks',
      kind: 'command',
      argv: ['printf', '<b>literal</b>', ''],
      cwdRelative: '.',
      timeoutSeconds: 300,
      previewUrl: null,
      revision: revision
    }
  }
  // Complete inert snapshot consumed by the actual client.
  function state(revision) {
    return {
      revision: revision,
      definitions: [definition(revision)],
      runs: [],
      requests: []
    }
  }
  // Deliver the authoritative envelope through the held client callback.
  function reply(index, response) {
    calls[index].done(response.ok ? 0 : 1, JSON.stringify(response), '')
  }
  Component.onCompleted: t.step(50, function () {
    actions.client.runner = function (argv, input, done) {
      root.calls.push({
        argv: argv,
        input: input,
        done: done
      })
    }
    actions.client.snapshot = state(3)
    actions.refresh()
    actions.selectAction('a-00000000-0000-4000-8000-000000000001', 3)
    actions.activateAction('a-00000000-0000-4000-8000-000000000001', 3)
    t.equal(calls.length, 0, 'capture guards selection, refresh and start before transport')
    actions.displayOnly = false
    actions.client.availability = {
      execution: true
    }
    calls = []
    actions.selectAction('a-00000000-0000-4000-8000-000000000001', 3)
    t.equal(calls.length, 0, 'selecting action never launches')
    t.equal(actions.checkout.path, '/repo one', 'exact selected checkout visible')
    actions.selectedActionId = ''
    actions.activateAction('a-00000000-0000-4000-8000-000000000001', 3)
    t.equal(calls.length, 0, 'first keyboard activation reveals definition only')
    actions.rememberAction('a-00000000-0000-4000-8000-000000000001', 3)
    actions.client.snapshot = state(4)
    actions.releaseAction('a-00000000-0000-4000-8000-000000000001', 4)
    t.equal(calls.length, 0, 'pointer revision change cannot transfer start')
    actions.rememberAction('a-00000000-0000-4000-8000-000000000001', 4)
    actions.project = Object.assign({}, actions.project, {
      lastCheckoutId: 'c-00000000-0000-4000-8000-000000000002'
    })
    calls = []
    actions.releaseAction('a-00000000-0000-4000-8000-000000000001', 4)
    t.equal(calls.length, 0, 'pointer checkout change cannot transfer start')
    actions.selectAction('a-00000000-0000-4000-8000-000000000001', 4)
    actions.activateAction('a-00000000-0000-4000-8000-000000000001', 4)
    t.equal(calls.length, 1, 'explicit activation requests UUID once')
    calls[0].done(0, '00000000-0000-4000-8000-000000000001', '')
    t.equal(JSON.parse(calls[1].input).expectedDefinitionRevision, 4, 'displayed revision always submitted')
    t.equal(JSON.parse(calls[1].input).checkoutId, 'c-00000000-0000-4000-8000-000000000002', 'explicit exact checkout submitted')
    var run = {
      id: 'r-00000000-0000-4000-8000-000000000001',
      requestId: 'req-00000000-0000-4000-8000-000000000001',
      projectId: 'p-00000000-0000-4000-8000-000000000001',
      checkoutId: 'c-00000000-0000-4000-8000-000000000002',
      actionId: 'a-00000000-0000-4000-8000-000000000001',
      definitionRevision: 4,
      definitionHash: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      processState: 'running',
      definitionSnapshot: definition(4),
      cwd: '/repo two',
      createdAt: 1
    }
    reply(1, {
      ok: true,
      error: null,
      run: run,
      state: Object.assign(state(4), {
        runs: [run],
        requests: [
          {
            requestId: run.requestId,
            runId: run.id
          }
        ]
      })
    })
    t.equal(actions.client.runId, 'r-00000000-0000-4000-8000-000000000001', 'actual consumer retains accepted run ID')
    actions.activateAction('a-00000000-0000-4000-8000-000000000001', 4)
    t.equal(calls.length, 2, 'protected run cannot duplicate start')
    var history = t.findChildren(actions, 'pill').filter(function (button) {
      return button.modelData && button.modelData.id === 'r-00000000-0000-4000-8000-000000000001'
    })[0]
    history.pressed()
    var replacementRun = Object.assign({}, run, {
      id: 'r-00000000-0000-4000-8000-000000000002'
    })
    actions.client.snapshot = Object.assign(state(4), {
      runs: [replacementRun]
    })
    var replacedHistory = t.findChildren(actions, 'pill').filter(function (button) {
      return button.modelData && button.modelData.id === 'r-00000000-0000-4000-8000-000000000002'
    })[0]
    replacedHistory.clicked()
    t.equal(calls.length, 2, 'replaced history row pointer cannot transfer inspect IO')
    actions.client.snapshot = Object.assign(state(4), {
      runs: [run]
    })
    var editButton = t.findChild(actions, 'actionEdit:a-00000000-0000-4000-8000-000000000001')
    editButton.pressed()
    actions.client.snapshot = state(5)
    t.findChild(actions, 'actionEdit:a-00000000-0000-4000-8000-000000000001').clicked()
    t.check(!actions.editing, 'changed definition pointer release cannot transfer Edit')
    actions.client.snapshot = state(4)
    actions.client.availability = {
      execution: false
    }
    actions.editAction('a-00000000-0000-4000-8000-000000000001', 4)
    actions.editor.setField('name', 'New name')
    actions.editor.save()
    t.equal(calls[2].argv.slice(-1), ['configure'], 'manager unavailable Save configures without running')
    reply(2, {
      ok: false,
      error: {
        code: 'ACTION_CONFLICT',
        message: 'Changed elsewhere',
        recovery: 'Refresh then review'
      },
      state: state(5)
    })
    t.check(actions.editing && actions.editor.draft.name === 'New name', 'stale edit keeps draft')
    actions.refresh()
    reply(3, {
      ok: true,
      error: null,
      state: state(6)
    })
    reply(4, {
      ok: true,
      error: null,
      state: null,
      availability: {
        execution: true
      }
    })
    t.check(actions.conflictRefreshed, 'explicit refresh makes conflict review available')
    actions.saveOverLatest()
    t.equal(JSON.parse(calls[5].input).expectedRevision, 6, 'explicit overwrite uses freshly reviewed state revision')
    reply(5, {
      ok: false,
      error: {
        code: 'ACTION_CONFLICT',
        message: 'Changed again',
        recovery: 'Refresh again'
      },
      state: state(7)
    })
    t.check(actions.editing && !actions.conflictRefreshed && actions.editor.draft.name === 'New name', 'renewed concurrent edit refuses and retains draft')
    var saved = actions.captureSnapshot()
    actions.displayOnly = true
    actions.captureReset({})
    actions.captureRestore(saved)
    t.equal(actions.editor.draft.name, 'New name', 'capture restores presentation draft')
    var count = calls.length
    actions.refresh()
    actions.client.readRun()
    actions.removeAction('a-00000000-0000-4000-8000-000000000001', 5)
    t.equal(calls.length, count, 'capture restore and controls remain inert')
    actions.project = Object.assign({}, actions.project, {
      lastCheckoutId: 'c-00000000-0000-4000-8000-000000000001'
    })
    actions.displayOnly = false
    t.step(50, function () {
      t.equal(root.calls.length, count, 'selection changes queued during capture never perform later IO')
      t.done()
    })
  })
}
