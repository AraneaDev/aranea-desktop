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
  // Observable launch count and deterministic role failure for targeted retry.
  property var launches: []
  // Current bindings are fixture process proof, never inferred by the owner.
  property var proven: []
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
      processRunner: helpers.processRunner,
      snapshot: function () {
        return {
          available: true,
          observedAt: Date.now(),
          currentWorkspaceId: 1,
          workspaces: [],
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
        root.proven.push(binding)
        done({
          status: 'observed',
          binding: binding
        })
      }
    })
  IpcHandler {
    target: 'fixture'
    function mode(value: string): string {
      root.failTerminal = value === 'failure'
      root.uncertain = value === 'uncertain'
      if (value === 'readiness')
        endpoint.owner.registryReady = false
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
