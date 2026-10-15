// Production Actions page with the actual client; only the transport is held.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as ProjectUi

ShellRoot {
  id: root
  // Held backend calls.
  property var calls: []
  QmlTest {
    id: t
  }
  ProjectUi.ProjectActions {
    id: actions
    width: 420
    // Inert until the held transport is installed; no real backend is spawned.
    displayOnly: true
    project: ({
        id: 'p-00000000-0000-4000-8000-000000000001',
        lastCheckoutId: 'c-00000000-0000-4000-8000-000000000001',
        checkouts: [{
            id: 'c-00000000-0000-4000-8000-000000000001',
            path: '/repo',
            branch: 'main'
          }]
      })
  }
  // Suggestion fixture.
  function suggestion(cwd, entry, kind) {
    return {
      key: 'package.json:' + cwd + ':' + entry,
      source: 'package.json',
      sourcePath: 'package.json',
      entry: entry,
      label: entry,
      definition: {
        name: entry,
        kind: kind,
        argv: ['npm', 'run', entry],
        cwdRelative: cwd,
        timeoutSeconds: kind === 'command' ? 300 : null,
        previewUrl: null
      },
      previewEvidence: null,
      alreadySaved: false
    }
  }
  // Delegate lookup by objectName under the page.
  function find(item, name) {
    return t.findChild(item, name)
  }
  // Answer the held detection call.
  function detected(rows, sources) {
    var call = calls.filter(function (c) {
      return c.argv[1] === 'detect'
    }).pop()
    call.done(0, JSON.stringify({
      ok: true,
      state: null,
      error: null,
      projectId: actions.project.id,
      checkoutId: actions.checkout.id,
      suggestions: rows,
      sources: sources || []
    }), '')
  }
  Component.onCompleted: t.step(50, function () {
    actions.client.runner = function (argv, input, done) {
      root.calls.push({
        argv: argv,
        input: input ? JSON.parse(input) : null,
        done: done
      })
    }
    actions.displayOnly = false
    actions.client.snapshot = {
      revision: 1,
      definitions: [],
      runs: [],
      requests: []
    }
    actions.detectSuggestions(false)
    t.check(calls.some(function (c) {
      return c.argv[1] === 'detect'
    }), 'visible Actions page detects')
    detected([suggestion('.', 'test', 'command'), suggestion('.', 'dev', 'service'), suggestion('apps/web', 'build', 'command')], [{
        source: 'cargo',
        status: 'unavailable',
        reason: 'Needs python3'
      }])
    t.step(30, function () {
      t.check(!!find(actions, 'suggestionAdd:package.json:.:test'), 'expanded with no saved actions')
      t.check(!find(actions, 'suggestionsToggle') || !find(actions, 'suggestionsToggle').visible, 'no disclosure without saved actions')
      // Add saves exactly that definition and does not start it.
      calls = []
      find(actions, 'suggestionAdd:package.json:.:test').clicked()
      t.equal(calls.length, 1, 'one save')
      t.equal(calls[0].argv[1], 'configure', 'Add uses configure')
      t.equal(calls[0].input.definition.argv.join(' '), 'npm run test', 'exact draft')
      var saved = {
        id: 'a-00000000-0000-4000-8000-000000000001',
        projectId: actions.project.id,
        name: 'test',
        kind: 'command',
        argv: ['npm', 'run', 'test'],
        cwdRelative: '.',
        timeoutSeconds: 300,
        previewUrl: null,
        revision: 2
      }
      calls[0].done(0, JSON.stringify({
        ok: true,
        state: {
          revision: 2,
          definitions: [saved],
          runs: [],
          requests: []
        },
        error: null
      }), '')
      t.step(30, function () {
        t.check(!find(actions, 'suggestionAdd:package.json:.:test'), 'saved suggestion disappears')
        t.check(calls.every(function (c) {
          return c.argv[1] !== 'start'
        }), 'nothing started')
        var toggle = find(actions, 'suggestionsToggle')
        t.check(toggle && toggle.visible && toggle.text === 'Found in this repo · 2 not added', 'collapses once actions exist')
        t.check(!find(actions, 'suggestionAdd:package.json:.:dev') || !find(actions, 'suggestionAdd:package.json:.:dev').visible, 'rows hidden while collapsed')
        toggle.clicked()
        t.step(30, function () {
          // Edit opens the prefilled editor as a new draft.
          find(actions, 'suggestionEdit:package.json:.:dev').clicked()
          t.check(actions.editing, 'editor open')
          t.equal(actions.editor.draft.name, 'dev', 'prefilled name')
          t.equal(actions.editor.draft.kind, 'service', 'prefilled kind')
          t.check(!actions.editor.draft.id, 'new draft, not an edit')
          actions.editing = false
          // Add all saves both remaining suggestions in order.
          calls = []
          find(actions, 'suggestionsAddAll').clicked()
          t.equal(calls.length, 1, 'sequential saves')
          t.equal(calls[0].input.definition.name, 'dev', 'root first')
          t.check(find(actions, 'suggestionsNote').text.indexOf('Cargo (needs python3)') >= 0, 'unavailable source note')
          t.done()
        })
      })
    })
  })
}
