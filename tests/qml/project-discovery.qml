// Persistent scan client rejects stale callbacks and cancels owned scans.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects" as ProjectUi

ShellRoot {
  id: host
  // Held scan callbacks model asynchronous process output, not registry writes.
  property var scans: []
  // Number of cancellation requests sent to the scan transport.
  property int cancellations: 0
  QmlTest {
    id: t
  }
  Projects.ProjectDiscoveryController {
    id: client
    runner: function (argv, line, done) {
      host.scans.push({
        argv: argv,
        line: line,
        done: done
      })
      return function () {
        host.cancellations++
      }
    }
  }
  // Held private store/probe completions drive the actual operation client.
  property var backendCalls: []
  // Retained private helper callbacks for exact request/readback assertions.
  property var backendDone: []
  ProjectUi.ProjectRegistryClient {
    id: backend
    storePath: '/fixture/store'
    toolsPath: '/fixture/tools'
    runner: function (argv, input, done) {
      host.backendCalls.push([argv, input])
      host.backendDone.push(done)
    }
  }
  Component.onCompleted: {
    t.check(client.start('r-one'), 'explicit root starts scan')
    scans[0].line(JSON.stringify({
      event: 'step',
      data: {
        event: 'candidate',
        candidate: {
          path: '/repo',
          name: 'Repo',
          commonDir: '/repo/.git',
          checkouts: []
        }
      }
    }))
    t.equal(client.candidates.length, 1, 'candidate streams to review')
    client.visible = false
    t.check(client.pending, 'hiding page does not cancel scan')
    client.cancel()
    t.equal(cancellations, 1, 'Cancel invokes owned process group cancellation')
    scans[0].line(JSON.stringify({
      event: 'step',
      data: {
        event: 'candidate',
        candidate: {
          path: '/late'
        }
      }
    }))
    t.equal(client.candidates.length, 1, 'late cancelled response cannot publish')
    scans[0].done(1, '')
    t.check(!client.pending, 'cancel completes scan ownership')
    client.start('r-two')
    scans[1].line(JSON.stringify({
      event: 'completed',
      data: {
        outcome: 'partial',
        errors: ['Directory ceiling']
      }
    }))
    scans[1].done(1, '')
    t.check(client.partial, 'partial outcome retained')
    t.equal(client.errors, ['Directory ceiling'], 'partial reason retained')
    client.captureActive = true
    t.check(!client.start('r-three'), 'inert fixture refuses scan')
    t.equal(scans.length, 2, 'capture performs no backend call')
    backend.captureActive = true
    t.check(!backend.refresh(), 'inert operation client refuses private snapshot/probe')
    t.check(!backend.request('remove', {
      projectId: 'p-one'
    }), 'inert operation client refuses mutation')
    t.equal(backendCalls.length, 0, 'no inert registry backend call')
    backend.captureActive = false
    backend.refresh()
    t.equal(backendCalls.map(function (c) {
      return c[0]
    }), [['/fixture/store', 'snapshot'], ['/fixture/tools', '--json']], 'offline reads use safe private helper argv')
    backendDone[0](0, JSON.stringify({
      ok: true,
      state: {
        revision: 3,
        roots: [
          {
            id: 'r-one',
            path: '/root'
          }
        ],
        ignored: [
          {
            path: '/ignored',
            commonDir: '/ignored/.git'
          }
        ],
        projects: [
          {
            id: 'p-one',
            checkouts: []
          }
        ]
      },
      error: null
    }), '')
    backendDone[1](0, JSON.stringify({
      defaults: {},
      editors: [],
      terminals: []
    }), '')
    t.equal(backend.state.ignored[0].commonDir, '/ignored/.git', 'private snapshot retains durable common-directory ignores')
    t.check(backend.request('root-remove', {
      rootId: 'r-one'
    }), 'offline mutation is independent of live owner')
    t.equal(JSON.parse(backendCalls[2][1]), {
      action: 'root-remove',
      args: {
        rootId: 'r-one'
      },
      expectedRevision: 3
    }, 'mutation uses stdin JSON and observed revision')
    backendDone[2](0, JSON.stringify({
      ok: true,
      state: {
        revision: 4,
        roots: [],
        ignored: backend.state.ignored,
        projects: backend.state.projects
      },
      error: null
    }), '')
    t.equal(backend.state.projects.length, 1, 'root removal preserves registered projects')
    backend.request('remove', {
      projectId: 'p-one'
    })
    backendDone[3](1, JSON.stringify({
      ok: false,
      state: null,
      error: {
        message: 'Registry invalid',
        recovery: 'Repair registry'
      }
    }), '')
    t.equal(backend.state.projects.length, 1, 'registry error never resets cached project state')
    t.check(backend.error.indexOf('Repair registry') >= 0, 'mutation error retains actionable recovery')
    t.done()
  }
}
