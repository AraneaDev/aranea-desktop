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
  // Answer a held snapshot read for the selected project, as the backend would.
  function answerSnapshot(state) {
    actions.client.refresh()
    var call = calls.filter(function (c) {
      return c.argv[1] === 'snapshot'
    }).pop()
    call.done(0, JSON.stringify({
      ok: true,
      state: state,
      error: null
    }), '')
  }
  // Saved definition of the second project.
  function saved2(index, entry) {
    return {
      id: 'a-00000000-0000-4000-8000-0000000002' + (index < 10 ? '0' : '') + index,
      projectId: 'p-00000000-0000-4000-8000-000000000002',
      name: entry,
      kind: 'command',
      argv: ['npm', 'run', entry],
      cwdRelative: '.',
      timeoutSeconds: 300,
      previewUrl: null,
      revision: 20
    }
  }
  // Second project's state with the given saved definitions.
  function state2(definitions) {
    return {
      revision: 20,
      definitions: definitions,
      runs: [],
      requests: []
    }
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
    answerSnapshot({
      revision: 1,
      definitions: [],
      runs: [],
      requests: []
    })
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
          var result = find(actions, 'suggestionsResult')
          t.check(!!result && result.visible && result.text.indexOf('Stopped') >= 0 && result.text.indexOf('Added 0 actions') < 0, 'a cancelled Add all is not shown as success')
          actions.client.detections = ({})
          answerSnapshot({
            revision: 9,
            definitions: [],
            runs: [],
            requests: []
          })
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
                // Phase three: after a project switch the other project's snapshot is never compared.
                var p2 = 'p-00000000-0000-4000-8000-000000000002', c2 = 'c-00000000-0000-4000-8000-000000000002'
                var rows2 = [suggestion('.', 'test', 'command'), suggestion('.', 'dev', 'service'), suggestion('.', 'lint', 'command')]
                var sources2 = [
                  {
                    source: 'cargo',
                    status: 'unavailable',
                    reason: 'Needs python3'
                  }
                ]
                var cached = Object.assign({}, actions.client.detections)
                cached[p2 + '|' + c2] = {
                  projectId: p2,
                  checkoutId: c2,
                  suggestions: rows2,
                  sources: sources2,
                  error: null
                }
                actions.client.detections = cached
                actions.project = {
                  id: p2,
                  lastCheckoutId: c2,
                  checkouts: [
                    {
                      id: c2,
                      path: '/repo2',
                      branch: 'main'
                    }
                  ]
                }
                t.step(30, function () {
                  var add = find(actions, 'suggestionAdd:package.json:.:test')
                  t.check(!add || !add.visible, 'no Add against another project\'s snapshot')
                  var all = find(actions, 'suggestionsAddAll')
                  t.check(!all || !all.visible, 'no Add all against another project\'s snapshot')
                  var res = find(actions, 'suggestionsResult')
                  t.check(!res || !res.visible, 'the previous project\'s Add all result is gone')
                  answerSnapshot(state2([saved2(1, 'test')]))
                  detected(rows2, sources2)
                  t.step(30, function () {
                    var section = find(actions, 'projectActionSuggestions')
                    section.expanded = true
                    t.step(30, function () {
                      var toggle = find(actions, 'suggestionsToggle')
                      t.check(toggle && toggle.visible && toggle.text === 'Found in this repo · 2 not added', 'rows appear minus already-saved')
                      var saved = find(actions, 'suggestionAdd:package.json:.:test')
                      t.check(!saved || !saved.visible, 'already-saved command not offered')
                      t.check(!!find(actions, 'suggestionAdd:package.json:.:dev') && find(actions, 'suggestionAdd:package.json:.:dev').visible, 'unsaved command offered')
                      // Nothing left to add: the section hides entirely, note included.
                      answerSnapshot(state2([saved2(1, 'test'), saved2(2, 'dev'), saved2(3, 'lint')]))
                      t.step(30, function () {
                        t.check(!section.visible, 'section hidden once every suggestion is saved, despite the note')
                        // Near the action limit Add all becomes Add first N.
                        var many = []
                        for (var i = 0; i < 49; i++)
                          many.push(saved2(i + 10, 'other' + i))
                        answerSnapshot(state2(many))
                        t.step(30, function () {
                          var limited = find(actions, 'suggestionsAddAll')
                          t.check(!!limited && limited.visible && limited.text === 'Add first 1', 'Add first N near the limit')
                          var limit = find(actions, 'suggestionsLimit')
                          t.check(!!limit && limit.visible && limit.text === 'A project can save up to 50 actions; 2 more would exceed it.', 'limit message')
                          calls = []
                          limited.clicked()
                          t.equal(calls.filter(function (c) {
                            return c.argv[1] === 'configure'
                          }).length, 1, 'Add first 1 saves one draft')
                          t.equal(calls[0].input.definition.name, 'test', 'the first draft')
                          t.done()
                        })
                      })
                    })
                  })
                })
              })
            })
          })
        })
      })
    })
  })
}
