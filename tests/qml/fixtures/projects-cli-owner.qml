// Actual public IPC composition and owner; external desktop boundaries remain inert.
import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Separate helper adapter reads only the test's real sandbox registry.
  Projects.ProjectRuntime {
    id: helpers
    captureActive: true
  }
  // Delay only the next snapshot response to exercise readiness retries.
  property bool delayRefresh: false
  // Hold readiness until the first production request has actually been refused.
  property bool holdRefresh: false
  // Retained completion callback for that delayed snapshot.
  property var delayedSnapshot: null
  Timer {
    id: snapshotDelay
    interval: 1000
    onTriggered: {
      var done = root.delayedSnapshot
      root.delayedSnapshot = null
      done()
    }
  }
  // Observable launch count and deterministic role failure for targeted retry.
  property var launches: []
  // Current bindings are fixture process proof, never inferred by the owner.
  property var proven: []
  // Fake compositor tracks exact owner focus and known workspaces.
  property bool environmentMode: false
  // Exact fake focus readback for environment Return.
  property int currentWorkspace: 1
  // Known workspace identities used only in the profile fixture phase.
  property var workspaces: [
    {
      id: 1
    }
  ]
  // Control only the external application acceptance boundary.
  property bool failTerminal: false
  // Withhold window observation for safe explicit re-observation tests.
  property bool uncertain: false
  Projects.Projects {
    id: endpoint
    captureActive: true
  }
  // Fake desktop replaces every launcher/compositor call before owner activation.
  property var desktop: ({
      sessionId: 'cli-owner',
      createEnvironmentId: function (done) {
        helpers.processRunner(['cat', '/proc/sys/kernel/random/uuid'], '', function (code, output) {
          done(code === 0 ? 'e-' + String(output).trim() : null)
        })
      },
      processRunner: function (argv, input, done) {
        helpers.processRunner(argv, input, function (code, output, diagnostics) {
          if ((root.delayRefresh || root.holdRefresh) && argv[1] === 'snapshot') {
            root.delayRefresh = false
            root.delayedSnapshot = function () {
              done(code, output, diagnostics)
            }
            if (!root.holdRefresh)
              snapshotDelay.start()
          } else
            done(code, output, diagnostics)
        })
      },
      snapshot: function () {
        return {
          available: true,
          observedAt: Date.now(),
          currentWorkspaceId: root.environmentMode ? root.currentWorkspace : 1,
          workspaces: !root.environmentMode ? [] : root.workspaces.map(function (row) {
            return {
              id: row.id,
              windows: root.proven.filter(function (binding) {
                return binding.workspaceId === row.id
              }).length
            }
          }),
          windows: root.proven.map(function (b) {
            return {
              address: b.address,
              pid: b.pid,
              appId: b.appId,
              workspaceId: b.workspaceId
            }
          })
        }
      },
      validateBindings: function (bindings, done) {
        done({
          bindings: root.proven,
          missing: []
        })
      },
      focusWorkspace: function (id, done) {
        root.currentWorkspace = id
        if (!root.workspaces.some(function (row) {
          return row.id === id
        }))
          root.workspaces = root.workspaces.concat([
            {
              id: id
            }
          ])
        done({
          ok: true,
          status: 'observed'
        })
      },
      focusBinding: function (binding, done) {
        done({
          ok: true,
          status: 'observed',
          binding: binding
        })
      },
      launch: function (spec, done) {
        root.launches.push(spec.role)
        done(root.failTerminal && spec.role === 'terminal' ? {
          ok: false,
          status: 'failed',
          code: 'LAUNCH_FAILED'
        } : {
          ok: true,
          status: 'accepted',
          identity: {
            pid: 200 + root.launches.length,
            startTime: '123',
            token: spec.token,
            sessionId: 'cli-owner'
          }
        })
      },
      observe: function (spec, baseline, done) {
        if (root.uncertain) {
          done({
            status: 'unconfirmed',
            code: 'OBSERVATION_TIMEOUT'
          })
          return
        }
        var binding = {
          projectId: spec.projectId,
          checkoutId: spec.checkoutId,
          role: spec.role,
          workspaceId: spec.workspaceId,
          address: '0x' + spec.launchIdentity.pid.toString(16),
          appId: spec.token,
          pid: spec.launchIdentity.pid,
          sessionId: 'cli-owner',
          launchIdentity: spec.launchIdentity,
          evidence: {
            mode: 'process-app-id',
            processVerified: true,
            startTime: '123',
            verifiedAt: Date.now()
          }
        }
        if (spec.environmentId)
          binding.environmentId = spec.environmentId
        root.proven.push(binding)
        done({
          status: 'observed',
          binding: binding
        })
      }
    })
  IpcHandler {
    target: 'fixture'
    function releaseRefresh(): bool {
      root.holdRefresh = false
      if (root.delayedSnapshot)
        snapshotDelay.start()
      return true
    }
    function mode(value: string): string {
      if (value === 'profiles')
        root.environmentMode = true
      root.failTerminal = value === 'failure'
      root.uncertain = value === 'uncertain'
      if (value === 'readiness' || value === 'readiness-delayed') {
        root.holdRefresh = true
        root.delayRefresh = true
        snapshotDelay.interval = value === 'readiness-delayed' ? 1000 : 0
        endpoint.owner.registryReady = false
      }
      return JSON.stringify({
        launches: root.launches,
        ready: endpoint.owner.registryReady
      })
    }
  }
  Component.onCompleted: {
    endpoint.owner.runtime = desktop
    endpoint.owner.roleTimeout = 150
    endpoint.captureActive = false
    endpoint.owner.refresh()
  }
}
