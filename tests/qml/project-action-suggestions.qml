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
        checkouts: [
          {
            id: 'c-00000000-0000-4000-8000-000000000001',
            path: '/repo',
            branch: 'main'
          }
        ]
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
  // The empty-state fallback label under the page.
  function fallbackVisible() {
    var label = find(actions, 'actionsEmptyFallback')
    return !!label && label.visible
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
    detected([suggestion('.', 'test', 'command'), suggestion('.', 'dev', 'service'), suggestion('apps/web', 'build', 'command')], [
      {
        source: 'cargo',
        status: 'unavailable',
        reason: 'Needs python3'
      }
    ])
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
          // Phase two: no saved actions; failures and notes only.
          actions.client.disconnect()
          actions.client.detections = ({})
          actions.client.snapshot = {
            revision: 9,
            definitions: [],
            runs: [],
            requests: []
          }
          calls = []
          actions.detectSuggestions(false)
          actions.detectSuggestions(false)
          t.equal(calls.length, 1, 'a second unforced detect while in flight is skipped')
          actions.detectSuggestions(true)
          t.equal(calls.length, 2, 'forced detect while in flight reads again')
          calls[1].done(1, JSON.stringify({
            ok: false,
            state: null,
            error: {
              code: 'DETECTION_FAILED',
              message: 'no'
            }
          }), '')
          t.step(30, function () {
            var heading = find(actions, 'suggestionsHeading')
            t.check(!heading || !heading.visible, 'no heading for a failed detection')
            t.check(find(actions, 'suggestionsRetry').visible, 'Retry offered')
            t.check(fallbackVisible(), 'fallback shown with the error')
            actions.client.detect(true)
            detected([], [
              {
                source: 'cargo',
                status: 'unavailable',
                reason: 'Needs python3'
              }
            ])
            t.step(30, function () {
              var h = find(actions, 'suggestionsHeading')
              t.check(!h || !h.visible, 'no heading for a note-only result')
              t.check(find(actions, 'suggestionsNote').visible, 'note shown')
              t.check(fallbackVisible(), 'fallback shown with the note')
              actions.client.detect(true)
              detected([suggestion('.', 'test', 'command')], [])
              t.step(30, function () {
                t.check(find(actions, 'suggestionsHeading').visible, 'heading with rows')
                t.check(!fallbackVisible(), 'fallback hidden with rows')
                t.done()
              })
            })
          })
        })
      })
    })
  })
}
