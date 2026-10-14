// Actual registry and Git preflight with inert fake native launches.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Count native attempts without executing installed applications.
  property int launches: 0
  // Separate deliberate starts must persist independent environments.
  property int count: 0
  // The fake compositor exposes only explicitly observed workspace availability.
  property int workspace: 1
  // Preparation retries preserve one detached exact activation target.
  property var request: null
  QmlTest {
    id: t
  }
  Projects.ProjectRuntime {
    id: processes
    captureActive: false
  }
  Projects.ProjectsController {
    id: owner
    runtime: ({
        sessionId: 'environment-flow',
        processRunner: processes.processRunner,
        createEnvironmentId: processes.createEnvironmentId,
        snapshot: function () {
          return {
            available: true,
            currentWorkspaceId: root.workspace,
            windows: [],
            workspaces: root.workspace === 1 ? [
              {
                id: 1,
                windows: 2
              }
            ] : [
              {
                id: 1,
                windows: 2
              },
              {
                id: root.workspace,
                windows: 0
              }
            ]
          }
        },
        focusWorkspace: function (id, done) {
          root.workspace = id
          done({
            ok: true,
            status: 'observed'
          })
        },
        launch: function (spec, done) {
          t.equal(spec.cwd, owner.registry.projects[0].checkouts.filter(function (c) {
            return c.id === owner.registry.projects[0].lastCheckoutId
          })[0].path, 'launch uses actual selected registered checkout')
          t.check(spec.environmentId.indexOf('e-') === 0, 'native launch keeps opaque environment identity')
          root.launches++
          done({
            ok: false,
            code: 'FAKE_NATIVE_REFUSAL'
          })
        }
      })
  }
  // Poll only explicitly unaccepted readiness; never replay after acceptance.
  function prepare() {
    var p = owner.registry.projects[0], profile = p.profiles[0]
    root.request = {
      projectId: p.id,
      checkoutId: p.lastCheckoutId,
      profileId: profile.id,
      profileRevision: profile.revision,
      activationId: 'a-00000000-0000-4000-8000-00000000000' + (count + 1)
    }
    owner.prepareEnvironment(request)
    t.waitFor(function () {
      return owner.prepareEnvironment(request).ok
    }, 3000, 'actual store/Git/tool preflight ready', function () {
      var result = owner.startEnvironment(request)
      t.check(result.ok, 'actual prepared start accepted')
      t.equal(owner.startEnvironment(request).operationId, result.operationId, 'actual repeated activation coalesces')
      t.waitFor(function () {
        return owner.operation(result.operationId).state === 'completed'
      }, 3000, 'actual accepted launch completes', function () {
        t.equal(owner.operation(result.operationId).outcome, 'partial', 'native refusal remains partial after focus')
        if (owner.operation(result.operationId).error) {
          t.check(false, 'unexpected operation failure: ' + owner.operation(result.operationId).error.code)
          t.done()
          return
        }
        root.count++
        if (count < 2) {
          t.equal(owner.registry.projects[0].environments[0].checkoutSnapshot.branch, 'feature', 'launch context captures fresh Git branch without rewriting registered branch')
          processes.processRunner(['git', '-C', Quickshell.env('ARANEA_FLOW_PATH'), 'switch', '-qc', 'after-launch'], '', function (code) {
            t.equal(code, 0, 'isolated checkout branch changes after first launch')
            prepare()
          })
        } else {
          t.equal(owner.registry.projects[0].environments.length, 2, 'two starts persist two immutable environments')
          var before = root.launches
          var returned = owner.returnEnvironment({
            projectId: p.id,
            environmentId: result.environmentId
          })
          t.waitFor(function () {
            return owner.operation(returned.operationId).state === 'completed'
          }, 2000, 'Return complete', function () {
            t.equal(owner.operation(returned.operationId).outcome, 'observed', 'Return has observed focus')
            t.equal(root.launches, before, 'Return cannot launch missing roles')
            console.log('FLOW_SNAPSHOT ' + JSON.stringify(owner.snapshot()))
            t.done()
          })
        }
      })
    })
  }
  Component.onCompleted: {
    t.check(typeof owner.startEnvironment === 'function', 'actual owner supports prepared profile starts')
    if (typeof owner.startEnvironment !== 'function') {
      t.done()
      return
    }
    owner.refresh()
    t.waitFor(function () {
      return owner.registryReady && !owner.refreshing
    }, 3000, 'actual registry ready', prepare)
  }
}
