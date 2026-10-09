// Production source/client distinguish accepted observer failures from stale submission refusals.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: root
  // Transport requests prove observer failures never resubmit accepted work.
  property var requests: []
  // The next accepted observation remains held until the fixture disconnects it.
  property var observation: null
  // A later local submission refusal may race newer authoritative owner feedback.
  property var submission: null
  // Menu-facing notices stay separate from the authoritative operation outcome.
  property var notices: []
  // Current snapshot can recover a completed operation without another request.
  property var state: ({
      sessionId: 'observer-session',
      availability: {
        compositor: true
      },
      projects: [
        {
          id: 'p-observer',
          name: 'Observer',
          lastCheckoutId: 'c-observer',
          workspaceMode: 'dedicated',
          tools: {},
          checkouts: [
            {
              id: 'c-observer',
              path: '/fixture',
              branch: 'main'
            }
          ],
          associations: []
        }
      ],
      bindings: [],
      operations: []
    })
  QmlTest {
    id: t
  }
  Projects.ProjectClient {
    id: client
    captureActive: true
    pollInterval: 10
    runner: function (argv, done) {
      if (argv[2] === 'snapshot')
        done(0, JSON.stringify(root.state), '')
      else if (argv[2] === 'request') {
        root.requests.push(JSON.parse(argv[3]))
        if (root.requests.length === 1)
          done(0, JSON.stringify({
            ok: true,
            operationId: 'op-observed',
            error: null
          }), '')
        else
          root.submission = done
      } else if (argv[2] === 'operation') {
        if (!root.observation) {
          root.observation = done
          done(0, JSON.stringify(root.operation(1, 'observing')), '')
        } else
          root.observation = done
      } else
        t.check(false, 'fixture refuses unknown IPC')
    }
  }
  Menu.DesktopSearchSources {
    id: sources
    compositor: null
    projectClient: client
    snapshotReader: function () {
      return {
        compositorAvailable: false,
        windows: [],
        workspaces: []
      }
    }
    runner: function (argv) {
      t.check(false, 'fixture cannot execute desktop commands')
      return false
    }
    onFailed: function (message) {
      root.notices.push(message)
    }
  }
  // Hand-authored owner records preserve exact session/checkout and generation identities.
  function operation(generation, state) {
    return {
      id: generation === 1 ? 'op-observed' : 'op-newer',
      projectId: 'p-observer',
      checkoutId: 'c-observer',
      sessionId: 'observer-session',
      generation: generation,
      state: state,
      outcome: state === 'completed' ? 'observed' : null,
      steps: [],
      error: null
    }
  }
  // Accepted observer failure is visible while the last authoritative owner result is retained.
  function disconnect() {
    var previous = JSON.stringify(sources.feedbackForProject('p-observer', 'c-observer'))
    observation(1, '', 'Connection lost; refresh to observe the accepted operation.')
    t.check(!client.available && !client.pending && !!client.error, 'transport failure stops only the local observer')
    t.equal(notices, ['Connection lost; refresh to observe the accepted operation.'], 'accepted observer disconnect emits a separate recovery notice')
    t.equal(JSON.stringify(sources.feedbackForProject('p-observer', 'c-observer')), previous, 'disconnect preserves authoritative pending outcome')
    t.equal(client.operationId, 'op-observed', 'disconnect retains accepted operation identity for recovery')
    t.step(60, function () {
      t.equal(requests.length, 1, 'disconnect never cancels or resubmits accepted owner work')
      root.state = Object.assign({}, root.state, {
        operations: [operation(1, 'completed')]
      })
      client.refresh()
      t.check(client.available && !client.error, 'fresh owner snapshot restores observer availability')
      t.equal(sources.feedbackForProject('p-observer', 'c-observer').status, 'observed', 'fresh snapshot restores completed authoritative outcome')
      t.equal(requests.length, 1, 'snapshot recovery does not submit work')
      staleRefusal()
    })
  }
  // A rejected local request cannot issue a late notice over a newer accepted owner operation.
  function staleRefusal() {
    t.check(sources.activate('project:p-observer'), 'a later user action can submit after completed work')
    t.check(!!submission, 'later request remains in flight at the transport boundary')
    root.state = Object.assign({}, root.state, {
      operations: [operation(2, 'completed')]
    })
    client.refresh()
    t.equal(sources.projectSubmission, null, 'newer owner outcome supersedes synthetic submission feedback')
    submission(0, JSON.stringify({
      ok: false,
      operationId: null,
      error: {
        code: 'CHECKOUT_MISSING',
        message: 'Late local refusal',
        recovery: 'Review project details'
      }
    }), '')
    t.equal(notices, ['Connection lost; refresh to observe the accepted operation.'], 'stale local refusal cannot emit a new error notice')
    t.equal(sources.feedbackForProject('p-observer', 'c-observer').operationId, 'op-newer', 'stale refusal leaves newer accepted outcome intact')
    t.step(60, function () {
      t.equal(requests.length, 2, 'only the two explicit user actions submit requests')
      client.captureActive = true
      t.done()
    })
  }
  Component.onCompleted: {
    client.captureActive = false
    client.refresh()
    sources.active = true
    sources.refreshNow()
    t.check(sources.activate('project:p-observer'), 'actual source activation submits through production client')
    t.equal(sources.projectSubmission, null, 'accepted progress clears synthetic submission feedback')
    var firstRead = observation
    t.waitFor(function () {
      return observation !== firstRead
    }, 1000, 'next accepted operation poll reaches transport', disconnect)
  }
}
