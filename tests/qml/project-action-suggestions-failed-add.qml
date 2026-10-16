// A refused Add all reports the plain count and says nothing else changed.
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
  // One command draft.
  function draft(name) {
    return {
      name: name,
      kind: 'command',
      argv: ['npm', 'run', name],
      cwdRelative: '.',
      timeoutSeconds: 300,
      previewUrl: null
    }
  }
  Component.onCompleted: t.step(50, function () {
    actions.client.runner = function (argv, input, done) {
      root.calls.push({
        argv: argv,
        done: done
      })
    }
    var emptyState = {
      revision: 1,
      definitions: [],
      runs: [],
      requests: []
    }
    t.check(actions.client.addSuggestions([draft('a'), draft('b'), draft('c')]), 'queue accepted')
    t.equal(calls.length, 1, 'first save held')
    // Nothing is saved before the refusal.
    calls[0].done(0, JSON.stringify({
      ok: false,
      state: emptyState,
      error: {
        code: 'CAPACITY_EXCEEDED',
        message: 'Too many actions.'
      }
    }), '')
    t.step(30, function () {
      var result = t.findChild(actions, 'suggestionsResult')
      t.check(!!result && result.visible, 'a refused Add all shows its result')
      t.equal(result.text, 'Added 0 of 3. Nothing else was changed.', 'plain count and reassurance')
      t.done()
    })
  })
}
