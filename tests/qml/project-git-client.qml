// Held backend responses exercise identity, freshness and inert scheduling guards.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Only the external helper boundary is replaced; the scheduler remains real.
  property var calls: []
  QmlTest {
    id: t
  }
  Projects.ProjectGitClient {
    id: client
    runner: function (argv, done) {
      host.calls.push({
        argv: argv,
        done: done
      })
    }
  }
  Projects.ProjectsSidebar {
    id: viewport
    width: 300
    height: 240
    projects: Array.from({
      length: 20
    }, function (_, i) {
      return {
        id: 'p-row-' + i,
        name: 'Row ' + String(i).padStart(2, '0'),
        lastCheckoutId: 'c-row-' + i,
        checkouts: [
          {
            id: 'c-row-' + i,
            path: '/fixture/' + i,
            branch: 'main'
          }
        ]
      }
    })
  }
  Projects.ProjectsPresentation {
    id: presentation
    windowEnabled: false
  }
  Projects.ProjectsSurface {
    id: captureSurface
    root: presentation
    width: 1080
    height: 720
  }
  // Complete helper-shaped data includes raw file paths and observation time.
  function successFor(project, checkout, time) {
    return {
      ok: true,
      error: null,
      data: {
        projectId: project,
        checkoutId: checkout,
        path: '/fixture/repo',
        observedAt: time,
        branch: 'main',
        detached: false,
        upstream: null,
        ahead: null,
        behind: null,
        counts: {
          staged: 0,
          unstaged: 1,
          untracked: 0,
          conflicts: 0
        },
        files: [
          {
            path: 'raw\nfile',
            staged: false,
            unstaged: true,
            untracked: false,
            conflict: false
          }
        ],
        truncated: false
      }
    }
  }
  // Deliver an exact recorded request, including late or duplicate callbacks.
  function respond(index, response) {
    calls[index].done(response.ok ? 0 : 1, JSON.stringify(response), '')
  }
  // Reset observations only after each scenario has drained its accepted helper.
  function reset() {
    client.active = false
    client.projectId = ''
    client.checkoutId = ''
    client.cache = ({})
    calls = []
    client.active = true
  }
  Component.onCompleted: t.step(20, function () {
    var firstRow = t.findChild(viewport, 'selectProject:p-row-0')
    t.check(viewport.visibleProjectIds().length > 0 && viewport.visibleProjectIds().length < 20, 'background viewport excludes wholly clipped rows')
    viewport.contentY = firstRow.y + firstRow.height - 1
    t.check(viewport.visibleProjectIds().indexOf('p-row-0') >= 0, 'partially clipped row remains a visible target')
    viewport.contentY = firstRow.y + firstRow.height
    t.check(viewport.visibleProjectIds().indexOf('p-row-0') < 0, 'fully clipped row leaves visible targets')
    viewport.visible = false
    t.equal(viewport.visibleProjectIds(), [], 'hidden viewport cannot supply background targets')
    reset()
    client.projectId = 'p-first'
    client.checkoutId = 'c-first'
    client.queueBackground([
      {
        projectId: 'p-row',
        checkoutId: 'c-row'
      }
    ])
    t.equal(calls[0].argv[2], 'p-first', 'deferred selected read takes priority over a simultaneous viewport pass')
    respond(0, successFor(calls[0].argv[2], calls[0].argv[4], Date.now()))
    client.active = false
    if (calls.length > 1)
      respond(1, successFor(calls[1].argv[2], calls[1].argv[4], Date.now()))
    reset()
    client.projectId = 'p-a'
    client.checkoutId = 'c-a'
    client.refresh()
    t.equal(calls[0].argv.slice(1), ['--project', 'p-a', '--checkout', 'c-a', '--json'], 'helper receives exact IDs as distinct argv')
    client.projectId = 'p-b'
    client.checkoutId = 'c-b'
    client.refresh()
    t.equal(calls.length, 1, 'switching selection cannot start a second concurrent helper')
    respond(0, successFor('p-a', 'c-a', 101))
    t.check(!client.current && client.loading && !client.error, 'late A result cannot replace B current, loading or error')
    t.equal(client.cache[JSON.stringify(['p-a', 'c-a'])].data.observedAt, 101, 'late A success may warm its own cache')
    t.equal(calls[1].argv.slice(1), ['--project', 'p-b', '--checkout', 'c-b', '--json'], 'selected checkout runs as soon as the process slot is free')
    respond(1, successFor('p-b', 'c-b', 102))
    t.equal(client.current.projectId, 'p-b', 'current publishes only the exact selected pair')
    client.refresh()
    client.refresh()
    client.refresh()
    t.equal(calls.length, 3, 'repeated refreshes coalesce behind the running helper')
    respond(2, successFor('p-b', 'c-b', 103))
    t.equal(client.current.observedAt, 102, 'superseded refresh cannot replace retained data')
    respond(3, successFor('p-b', 'c-b', 104))
    respond(2, successFor('p-b', 'c-b', 105))
    t.equal(client.current.observedAt, 104, 'duplicate old completion cannot replace the later refresh')
    client.refresh()
    respond(4, {
      ok: false,
      data: null,
      error: {
        code: 'TIMEOUT',
        message: 'Deadline exceeded',
        recovery: 'Refresh'
      }
    })
    t.equal(client.current.observedAt, 104, 'deadline failure retains last good observation timestamp')
    t.equal(client.error.code, 'TIMEOUT', 'current read error stays separate from stale data')
    client.checkoutId = 'c-other'
    client.refresh()
    t.check(!client.current && !client.error, 'another checkout never falls back to cached checkout data')
    respond(5, successFor('p-b', 'c-b', 106))
    t.check(!client.current && !!client.error, 'mismatched helper identity is a read failure')
    reset()
    client.projectId = 'p-a'
    client.checkoutId = 'c-a'
    client.refresh()
    client.queueBackground([
      {
        projectId: 'p-b',
        checkoutId: 'c-b'
      }
    ])
    client.active = false
    respond(0, successFor('p-a', 'c-a', 201))
    t.check(!client.loading && !client.refresh(), 'closing during a read stops loading and refuses refresh')
    t.equal(calls.length, 1, 'closing drops queued background reads')
    reset()
    client.projectId = 'p-a'
    client.checkoutId = 'c-a'
    client.refresh()
    client.captureActive = true
    var before = JSON.stringify(client.cache)
    respond(0, successFor('p-a', 'c-a', 301))
    t.equal(JSON.stringify(client.cache), before, 'capture invalidates a pre-capture callback')
    t.check(!client.refresh(), 'inert capture refuses explicit reads')
    client.queueBackground([
      {
        projectId: 'p-b',
        checkoutId: 'c-b'
      }
    ])
    t.equal(calls.length, 1, 'inert capture refuses background reads')
    client.captureActive = false
    reset()
    var targets = [
      {
        projectId: 'p-0',
        checkoutId: 'c-0'
      }
    ]
    for (var i = 0; i < 20; i++)
      targets.push({
        projectId: 'p-' + i,
        checkoutId: 'c-' + i
      })
    client.queueBackground(targets)
    client.projectId = 'p-selected'
    client.checkoutId = 'c-selected'
    client.refresh()
    respond(0, successFor('p-0', 'c-0', Date.now()))
    t.equal(calls[1].argv[2], 'p-selected', 'selected read takes priority over the queued background pass')
    respond(1, successFor('p-selected', 'c-selected', Date.now()))
    for (var j = 2; j < 13; j++)
      respond(j, successFor('p-' + (j - 1), 'c-' + (j - 1), Date.now()))
    t.equal(calls.length, 13, 'one background pass coalesces duplicates and reads at most twelve targets')
    client.queueBackground(targets.slice(0, 13))
    t.equal(calls.length, 13, 'background skips observations younger than thirty seconds')
    client.cache = Object.assign({}, client.cache, {
      '["p-0","c-0"]': {
        data: successFor('p-0', 'c-0', Date.now() - 31000).data,
        error: null
      }
    })
    client.queueBackground([
      {
        projectId: 'p-0',
        checkoutId: 'c-0'
      }
    ])
    t.equal(calls.length, 14, 'background refreshes an old observation')
    respond(13, successFor('p-0', 'c-0', Date.now()))
    client.active = false
    t.step(40, function () {
      t.equal(calls.length, 14, 'deferred selection reads cannot escape a hidden window')
      presentation.projectController.captureActive = true
      presentation.projectClient.captureActive = true
      presentation.activityClient.captureActive = true
      presentation.discoveryClient.captureActive = true
      var nativeCalls = 0
      presentation.gitClient.runner = function (argv, done) {
        nativeCalls++
      }
      presentation.gitClient.cache = {
        '["p-live","c-live"]': {
          data: successFor('p-live', 'c-live', 401).data,
          error: {
            code: 'TIMEOUT'
          }
        }
      }
      presentation.view = captureSurface
      presentation.projectController.state = {
        roots: [],
        ignored: [],
        projects: [
          {
            id: 'p-live',
            name: 'Live',
            tools: {},
            lastCheckoutId: 'c-live',
            checkouts: [
              {
                id: 'c-live',
                path: '/fixture/live',
                branch: 'main'
              }
            ]
          }
        ]
      }
      presentation.projectId = 'p-live'
      presentation.opened = true
      t.findChild(captureSurface, 'projectsPage').details.actions.client.captureActive = true
      t.findChild(captureSurface, 'projectsPage').details.setDraft('name', 'Retained draft')
      var snapshot = presentation.captureSnapshot()
      var fixture = {
        projectsState: {
          roots: [],
          ignored: [],
          projects: []
        },
        projectGitCache: {
          '["p-fixture","c-fixture"]': {
            data: successFor('p-fixture', 'c-fixture', 402).data,
            error: null
          }
        }
      }
      t.equal(presentation.captureBegin(JSON.stringify({
        snapshot: snapshot,
        fixture: fixture
      })), 'ok', 'Git cache participates in scoped inert capture')
      t.equal(presentation.gitClient.cache, fixture.projectGitCache, 'capture uses supplied Git observations')
      t.check(!presentation.gitClient.refresh(), 'capture composition refuses Git I/O')
      t.equal(presentation.captureRestore(snapshot), 'ok', 'capture restores the retained Git cache')
      t.equal(JSON.parse(presentation.captureSnapshot()).gitCache, JSON.parse(snapshot).gitCache, 'capture restores timestamps and independent read errors exactly')
      t.equal(t.findChild(captureSurface, 'projectsPage').details.draft.name, 'Retained draft', 'Git cache restoration preserves the production project draft')
      t.step(40, function () {
        t.equal(nativeCalls, 0, 'capture and restoration perform no native Git I/O')
        presentation.opened = false
        client.projectId = 'p-auto'
        client.checkoutId = 'c-auto'
        client.active = true
        t.waitFor(function () {
          return calls.length === 15
        }, 1000, 'opening automatically refreshes the selected pair', function () {
          t.equal(calls[14].argv.slice(1), ['--project', 'p-auto', '--checkout', 'c-auto', '--json'], 'automatic refresh observes settled selection properties')
          respond(14, successFor('p-auto', 'c-auto', Date.now()))
          var started = Date.now()
          t.waitFor(function () {
            return calls.length === 16
          }, 11000, 'visible selected checkout refreshes on its interval', function () {
            t.check(Date.now() - started >= 9500, 'visible observation interval is ten seconds rather than rapid polling')
            client.active = false
            respond(15, successFor('p-auto', 'c-auto', Date.now()))
            t.check(!client.loading, 'interval response after hiding does not restore loading')
            t.done()
          })
        })
      })
    })
  })
}
