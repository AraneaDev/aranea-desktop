// Empty Overview offers up to three detected commands; Add saves through the shared client only.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held shared-client transport calls.
  property var calls: []
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: root
    windowEnabled: false
    captureActive: true
  }
  Projects.ProjectsSurface {
    id: surface
    root: root
    width: 1080
    height: 720
  }
  // Detected row fixture.
  function row(entry, kind) {
    return {
      key: 'package.json:.:' + entry,
      source: 'package.json',
      sourcePath: 'package.json',
      entry: entry,
      label: entry,
      definition: {
        name: entry,
        kind: kind,
        argv: ['npm', 'run', entry],
        cwdRelative: '.',
        timeoutSeconds: kind === 'command' ? 300 : null,
        previewUrl: null
      },
      previewEvidence: null,
      alreadySaved: false
    }
  }
  // Answers the latest held snapshot read with these definitions.
  function answerSnapshot(definitions) {
    host.calls.filter(function (c) {
      return c.method === 'snapshot'
    }).pop().done(0, JSON.stringify({
      ok: true,
      state: {
        revision: 1,
        definitions: definitions,
        runs: [],
        requests: []
      },
      error: null
    }), '')
  }
  Component.onCompleted: t.step(80, function () {
    root.view = surface
    root.projectController.state = {
      projects: [
        {
          id: 'p',
          name: 'Repo',
          lastCheckoutId: 'c',
          checkouts: [
            {
              id: 'c',
              path: '/repo',
              branch: 'main'
            }
          ]
        },
        {
          id: 'q',
          name: 'Other',
          lastCheckoutId: 'd',
          checkouts: [
            {
              id: 'd',
              path: '/other',
              branch: 'main'
            }
          ]
        }
      ],
      roots: [],
      ignored: []
    }
    root.projectId = 'p'
    root.actionClient.runner = function (argv, input, done) {
      host.calls.push({
        method: argv[argv.length - 1],
        payload: JSON.parse(input || '{}'),
        done: done
      })
    }
    root.actionClient.snapshot = {
      revision: 1,
      definitions: [],
      runs: [],
      requests: []
    }
    var detections = {}
    detections['p|c'] = {
      projectId: 'p',
      checkoutId: 'c',
      suggestions: [row('lint', 'command'), row('test', 'command'), row('dev', 'service')],
      sources: [],
      error: null
    }
    root.actionClient.detections = detections
    t.equal(surface.overviewSuggestions.length, 0, 'inert surface offers nothing')
    surface.addOverviewSuggestion('package.json:.:test')
    t.equal(host.calls.filter(function (c) {
      return c.method === 'configure'
    }).length, 0, 'inert surface refuses Add')
    root.captureActive = false
    t.step(30, function () {
      t.equal(surface.overviewSuggestions.length, 0, 'no picks before a snapshot answers for this project')
      root.actionClient.refresh()
      answerSnapshot([])
      t.equal(surface.overviewSuggestions.map(function (r) {
        return r.entry
      }).join(','), 'test,dev', 'picks test and dev, not lint')
      var overview = t.findChild(surface, 'projectOverview')
      t.check(!!t.findChild(overview, 'overviewSuggestionAdd:package.json:.:test'), 'Overview renders the pick')
      host.calls = []
      t.findChild(overview, 'overviewSuggestionAdd:package.json:.:test').clicked()
      t.equal(host.calls.length, 1, 'one save')
      t.equal(host.calls[0].method, 'configure', 'Add saves through configure')
      t.equal(host.calls[0].payload.definition.argv.join(' '), 'npm run test', 'exact draft')
      surface.addOverviewSuggestion('package.json:.:lint')
      t.equal(host.calls.length, 1, 'a key the Overview does not show is refused')
      // A project switch re-detects for the new exact pair once both identities settle.
      host.calls = []
      root.projectId = 'q'
      t.step(30, function () {
        t.check(host.calls.some(function (c) {
          return c.method === 'detect' && c.payload.projectId === 'q' && c.payload.checkoutId === 'd'
        }), 'project switch detects the new project and checkout')
        t.equal(surface.overviewSuggestions.length, 0, 'no picks against the previous project\'s snapshot')
        root.projectId = 'p'
        t.step(30, function () {
          // The switch cleared the snapshot owner; answer a read for this project first.
          root.actionClient.refresh()
          answerSnapshot([])
          t.check(surface.overviewSuggestions.length > 0, 'picks return once this project\'s snapshot answers')
          // Once a definition exists the Overview stops offering suggestions.
          root.actionClient.refresh()
          answerSnapshot([Object.assign({
              id: 'a',
              projectId: 'p',
              revision: 1
            }, row('test', 'command').definition)])
          t.check(root.actionClient.suggestionsReady, 'suggestions stay ready for this project')
          t.equal(surface.selectedDefinitions.length, 1, 'the saved definition is this project\'s own')
          t.equal(surface.overviewSuggestions.length, 0, 'saved actions hide Overview suggestions')
          // Only other scripts detected: the first two still show, not the save hint.
          root.actionClient.refresh()
          answerSnapshot([])
          var others = {}
          others['p|c'] = {
            projectId: 'p',
            checkoutId: 'c',
            suggestions: [row('lint', 'command'), row('format', 'command'), row('typecheck', 'command')],
            sources: [],
            error: null
          }
          root.actionClient.detections = others
          t.equal(surface.overviewSuggestions.map(function (r) {
            return r.entry
          }).join(','), 'lint,format', 'other scripts fall back to the first two')
          var commands = t.findChild(t.findChild(surface, 'projectOverview'), 'overviewCommands')
          t.check(!!t.findChild(surface, 'overviewSuggestionAdd:package.json:.:lint'), 'Overview renders the fallback pick')
          t.equal(commands.emptyHint, '', 'no save hint while picks show')
          root.actionClient.detections = {}
          t.check(commands.emptyHint !== '', 'the save hint returns when nothing was detected')
          t.done()
        })
      })
    })
  })
}
