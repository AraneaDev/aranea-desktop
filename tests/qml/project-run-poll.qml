// Background run polling observes without making the Projects window busy.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held backend requests; the test answers each one.
  property var calls: []
  QmlTest {
    id: t
  }
  Projects.ProjectActionsClient {
    id: client
    projectId: 'p'
    checkoutId: 'c'
    observationActive: true
    pollInterval: 60000
    runner: function (argv, input, done) {
      host.calls.push({
        method: argv[argv.length - 1],
        payload: JSON.parse(input || '{}'),
        done: done
      })
    }
  }
  // One running service run, as the backend reports it.
  function running(id) {
    return {
      id: id,
      requestId: 'req-00000000-0000-4000-8000-000000000001',
      projectId: 'p',
      checkoutId: 'c',
      actionId: 'a',
      definitionRevision: 1,
      definitionHash: 'h',
      createdAt: 1,
      processState: 'running'
    }
  }
  Component.onCompleted: t.step(20, function () {
    var run = running('r-00000000-0000-4000-8000-000000000001')
    client.publishRun(run)
    client.readRun()
    t.equal(calls.length, 1, 'a poll reads the selected running run')
    t.equal(calls[0].method, 'refresh', 'the poll is a refresh')
    t.check(!client.pending, 'a background poll does not mark the client pending, so controls stay enabled')
    t.check(client.stop(run.id), 'Stop is accepted while a background poll is in flight')
    t.equal(calls[1].method, 'stop', 'Stop reaches the backend')
    calls[0].done(0, JSON.stringify({
      ok: true,
      error: null,
      run: run,
      state: {
        revision: 2,
        definitions: [],
        runs: [run],
        requests: []
      }
    }), '')
    t.check(client.pending, 'a late poll answer does not clear the pending Stop')
    calls[1].done(0, JSON.stringify({
      ok: true,
      error: null,
      run: Object.assign({}, run, {
        processState: 'stopped'
      })
    }), '')
    t.check(!client.pending, 'the Stop answer ends pending')

    // An unchanged poll answer leaves the snapshot and selected run alone.
    var again = running('r-00000000-0000-4000-8000-000000000002')
    var state = {
      revision: 3,
      definitions: [],
      runs: [again],
      requests: []
    }
    client.snapshot = state
    client.publishRun(again)
    var announced = 0
    client.runChanged.connect(function () {
      announced++
    })
    var held = client.snapshot
    calls = []
    client.readRun()
    calls[0].done(0, JSON.stringify({
      ok: true,
      error: null,
      run: again,
      state: state
    }), '')
    t.check(client.snapshot === held, 'an unchanged poll keeps the same snapshot, so views do not rebuild')
    t.equal(announced, 0, 'an unchanged poll does not re-announce the run')
    calls = []
    client.readRun()
    calls[0].done(0, JSON.stringify({
      ok: true,
      error: null,
      run: Object.assign({}, again, {
        processState: 'succeeded'
      }),
      state: {
        revision: 4,
        definitions: [],
        runs: [Object.assign({}, again, {
            processState: 'succeeded'
          })],
        requests: []
      }
    }), '')
    t.check(client.snapshot !== held && client.snapshot.revision === 4, 'a changed poll answer replaces the snapshot')
    t.equal(announced, 1, 'a changed run is announced')
    t.done()
  })
}
