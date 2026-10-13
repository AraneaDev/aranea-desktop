// All genuine selection entry paths record one visit; captures and refreshes do not.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held registry observations prove IPC selection waits for registered identity.
  property var snapshotDone: null
  // Tools complete the existing grouped registry read.
  property var toolsDone: null
  // Real client requests stay held until explicit backend publication.
  property var writes: []
  // Registration transport is independent of the IPC read callbacks.
  property var registrationWrites: []
  // Epoch-independent fixture registration with a literal exact checkout identity.
  property var cliProject: ({
      id: 'p-cli',
      name: 'CLI repo',
      lastCheckoutId: 'c-cli',
      tools: {},
      checkouts: [
        {
          id: 'c-cli',
          path: '/work/cli',
          branch: 'main'
        }
      ]
    })
  // Separate newly registered repository selected by successful readback.
  property var addedProject: ({
      id: 'p-added',
      name: 'Added repo',
      lastCheckoutId: 'c-added',
      tools: {},
      checkouts: [
        {
          id: 'c-added',
          path: '/work/added',
          branch: 'topic'
        }
      ]
    })
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  Projects.ProjectsPresentation {
    id: registrationEntry
    windowEnabled: false
  }
  // Full backend fixture state has the same navigation schema as the registry.
  function state(revision, projects, lastId) {
    return {
      revision: revision,
      roots: [],
      ignored: [],
      projects: projects,
      navigation: {
        lastProjectId: lastId,
        pinnedProjectIds: [],
        visitedAt: {}
      }
    }
  }
  Component.onCompleted: {
    entry.projectClient.captureActive = true
    entry.discoveryClient.captureActive = true
    entry.activityClient.captureActive = true
    entry.projectController.runner = function (argv, input, done) {
      if (argv[1] === 'snapshot')
        host.snapshotDone = done
      else if (argv[1] === '--json')
        host.toolsDone = done
      else
        host.writes.push({
          request: JSON.parse(input),
          done: done
        })
    }
    t.equal(entry.open(JSON.stringify({
      projectId: 'p-cli'
    })), 'ok', 'explicit IPC Details selects without launching')
    t.equal(entry.projectId, 'p-cli', 'IPC retains the exact requested identity while reading')
    t.step(80, function () {
      t.equal(host.writes.length, 0, 'IPC visit waits for registry identity validation')
      host.snapshotDone(0, JSON.stringify({
        ok: true,
        state: host.state(1, [host.cliProject], null)
      }), '')
      host.toolsDone(0, JSON.stringify({
        defaults: {},
        editors: [],
        terminals: []
      }), '')
      t.equal(host.writes.length, 1, 'explicit IPC Details records one visit after registry read')
      if (host.writes.length) {
        t.equal(host.writes[0].request, {
          action: 'navigation-set',
          args: {
            projectId: 'p-cli',
            visit: true
          },
          expectedRevision: 1
        }, 'IPC visit uses exact registered identity and observed revision')
        entry.projectController.state = Object.assign({}, entry.projectController.state)
        entry.open(JSON.stringify({
          projectId: 'p-cli'
        }))
        t.equal(host.writes.length, 1, 'refresh and repeated same-ID IPC do not duplicate a held visit')
        host.writes[0].done(0, JSON.stringify({
          ok: true,
          state: host.state(2, [host.cliProject], 'p-cli')
        }), '')
      }
      registration()
    })
  }
  // Successful registration must record its own selection independently of IPC.
  function registration() {
    registrationEntry.projectClient.captureActive = true
    registrationEntry.discoveryClient.captureActive = true
    registrationEntry.activityClient.captureActive = true
    registrationEntry.projectController.state = state(1, [cliProject], 'p-cli')
    registrationEntry.projectController.runner = function (argv, input, done) {
      host.registrationWrites.push({
        request: JSON.parse(input),
        done: done
      })
    }
    t.check(registrationEntry.projectController.request('register', {
      paths: ['/work/added']
    }), 'registration uses the existing serialized mutation boundary')
    t.equal(host.registrationWrites[0].request.action, 'register', 'registration is a distinct native mutation')
    host.registrationWrites[0].done(0, JSON.stringify({
      ok: true,
      state: state(2, [cliProject, addedProject], 'p-cli')
    }), '')
    t.step(80, function () {
      t.equal(registrationEntry.projectId, 'p-added', 'successful registration selects the exact returned project')
      t.equal(host.registrationWrites.length, 2, 'successful registration records its selected project once')
      if (host.registrationWrites.length !== 2) {
        t.done()
        return
      }
      t.equal(host.registrationWrites[1].request, {
        action: 'navigation-set',
        args: {
          projectId: 'p-added',
          visit: true
        },
        expectedRevision: 2
      }, 'registration visit follows successful revision-bound readback')
      host.registrationWrites[1].done(0, JSON.stringify({
        ok: true,
        state: state(3, [cliProject, addedProject], 'p-added')
      }), '')
      var snapshot = registrationEntry.captureSnapshot()
      t.equal(registrationEntry.captureBegin(JSON.stringify({
        snapshot: snapshot,
        projectId: 'p-cli',
        fixture: {
          projectsState: state(3, [cliProject, addedProject], 'p-added')
        }
      })), 'ok', 'capture selects a fixture identity inside the inert boundary')
      t.equal(registrationEntry.captureRestore(snapshot), 'ok', 'capture restores the genuine selection inside the inert boundary')
      t.step(80, function () {
        t.equal(host.registrationWrites.length, 2, 'inert fixture and restoration create no navigation writes')
        t.check(!entry.projectClient.pending && !entry.projectClient.preparing && !registrationEntry.projectClient.pending && !registrationEntry.projectClient.preparing, 'IPC and registration inspection never request an application launch')
        t.done()
      })
    })
  }
}
