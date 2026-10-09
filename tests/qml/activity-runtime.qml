// Session focus proves reverse ancestry, exact window and current compositor lifetime.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  id: root
  // Count native process proofs on each focus attempt.
  property int proofs: 0
  // Only validated exact-window dispatches are recorded.
  property var dispatches: []
  // Simulate current kernel proof validity.
  property bool valid: true
  // Authoritative compositor rows replace all real desktop reads.
  property var windows: [
    {
      pid: 10,
      address: '0xa',
      appId: 'terminal',
      workspaceId: 2
    }
  ]
  // Fixture active address supplies independent dispatch readback.
  property string active: ''
  // Inject PID reuse between process and compositor proofs.
  property bool replaceWindow: false
  // Inject compositor restart before focus dispatch.
  property bool replaceInstance: false
  // Saved native evidence is independently revalidated through injected helpers.
  property var session: ({
      provider: 'claude',
      providerSessionId: 's',
      producerEpoch: 'epoch',
      connection: {
        connected: true,
        receivedAt: Math.floor(Date.now() / 1000)
      },
      nativeMetadata: {
        observedHooks: ['SessionStart']
      },
      provenance: {
        pid: 20,
        startTime: '200',
        bootId: 'b',
        executable: '/claude',
        commandHash: 'hash',
        ancestors: [
          {
            pid: 10,
            startTime: '100'
          }
        ]
      }
    })
  QmlTest {
    id: t
  }
  Activity.ActivityRuntime {
    id: runtime
    processRunner: function (argv, input, done) {
      if (argv[0].endsWith('aranea-agent-identity')) {
        root.proofs++
        var query = JSON.parse(input)
        t.equal(query.terminalPid, 10, 'provider must descend from compositor terminal PID')
        if (root.replaceWindow)
          root.windows = [
            {
              pid: 11,
              address: '0xa',
              appId: 'terminal'
            }
          ]
        if (root.replaceInstance)
          runtime.engine.compositorInstance = 'other-instance'
        done(0, JSON.stringify({
          ok: true,
          verified: root.valid
        }), '')
      } else {
        t.check(false, 'unexpected runtime process')
        done(1, '', 'trapped')
      }
    }
  }
  Component.onCompleted: {
    runtime.engine.compositorInstance = 'instance'
    runtime.engine.compositor = {
      snapshot: function () {
        return {
          available: true,
          observedAt: Date.now(),
          windows: root.windows,
          workspaces: [],
          activeAddress: root.active
        }
      }
    }
    runtime.engine.dispatchRunner = function (argv, done) {
      root.dispatches.push(argv)
      root.active = '0xa'
      done(0, '', '')
    }
    runtime.focusSession({}, session, function (result) {
      t.equal(result.status, 'observed', 'fresh exact hosting terminal focused')
      t.equal(proofs, 2, 'native process proof revalidated immediately before dispatch')
      t.equal(dispatches.length, 1, 'one exact focus')
    })
    valid = false
    runtime.focusSession({}, session, function (result) {
      t.equal(result.status, 'unconfirmed', 'invalid native process refuses focus')
    })
    valid = true
    replaceWindow = true
    runtime.focusSession({}, session, function (result) {
      t.equal(result.status, 'unconfirmed', 'same address with reused PID refuses focus')
    })
    windows = [
      {
        pid: 10,
        address: '0xa',
        appId: 'terminal'
      }
    ]
    replaceWindow = false
    replaceInstance = true
    runtime.focusSession({}, session, function (result) {
      t.equal(result.status, 'unconfirmed', 'compositor instance change refuses focus')
    })
    replaceInstance = false
    windows = [
      {
        pid: 99,
        address: '0xa',
        appId: 'terminal'
      }
    ]
    runtime.focusSession({}, session, function (result) {
      t.equal(result.status, 'unconfirmed', 'class alone never proves session ownership')
    })
    windows = [
      {
        pid: 20,
        address: '0xa',
        appId: 'terminal'
      }
    ]
    runtime.focusSession({}, session, function (result) {
      t.equal(result.status, 'unconfirmed', 'provider PID is not hosting ancestor PID')
    })
    t.equal(dispatches.length, 1, 'all uncertain cases never dispatch')
    runtime.captureActive = true
    var before = proofs
    runtime.focusSession({}, session, function (result) {
      t.equal(result.status, 'unconfirmed', 'capture refuses focus')
    })
    t.equal(proofs, before, 'capture starts no helper')
    runtime.captureActive = false
    var requests = 0, queries = 0
    runtime.processRunner = function (argv, input, done) {
      var method = argv[4]
      if (method === 'prepareWorkspace') {
        requests++
        done(0, JSON.stringify(requests === 1 ? {
          ok: false,
          operationId: null,
          error: {
            code: 'OWNER_NOT_READY'
          }
        } : {
          ok: true,
          operationId: 'p-op'
        }), '')
      } else if (method === 'operation') {
        queries++
        done(0, JSON.stringify({
          id: 'p-op',
          projectId: 'p',
          checkoutId: 'c',
          sessionId: 'projects',
          workspaceId: 2,
          state: queries === 1 ? 'observing' : 'completed',
          outcome: queries === 1 ? null : 'observed',
          steps: []
        }), '')
      } else if (method === 'snapshot') {
        done(0, JSON.stringify({
          sessionId: 'projects',
          projects: [
            {
              id: 'p',
              commonDir: '/repo/.git',
              tools: {
                terminalId: 'kitty'
              },
              checkouts: [
                {
                  id: 'c',
                  path: '/repo'
                }
              ]
            }
          ]
        }), '')
      } else {
        t.check(false, 'only project owner IPC during preparation')
        done(1, '', 'trapped')
      }
    }
    runtime.prepare({
      association: {
        projectId: 'p',
        checkoutId: 'c',
        cwd: '/repo'
      }
    }, true, function (result) {
      t.check(result.ok, 'workspace preparation reaches observed project owner outcome')
      t.equal(result.terminalId, 'kitty', 'saved terminal preference comes from project authority')
      t.equal(requests, 2, 'retry only explicit preaccept readiness refusal')
      t.equal(queries, 2, 'accepted project ID queried without resubmission')
      t.equal(dispatches.length, 1, 'preparation has no duplicate activity workspace dispatch')
      t.done()
    })
  }
}
