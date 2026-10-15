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
  Component.onCompleted: t.step(80, function () {
    root.view = surface
    root.projectController.state = {
      projects: [{
          id: 'p',
          name: 'Repo',
          lastCheckoutId: 'c',
          checkouts: [{
              id: 'c',
              path: '/repo',
              branch: 'main'
            }]
        }],
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
      // Once a definition exists the Overview stops offering suggestions.
      root.actionClient.snapshot = {
        revision: 2,
        definitions: [Object.assign({
            id: 'a',
            projectId: 'p',
            revision: 2
          }, row('test', 'command').definition)],
        runs: [],
        requests: []
      }
      t.equal(surface.overviewSuggestions.length, 0, 'saved actions hide Overview suggestions')
      t.done()
    })
  })
}
