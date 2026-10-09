// Production owner with real sandbox helpers and independent fake desktop evidence.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects/ProjectRecords.js" as Records

ShellRoot {
  id: root
  // Per-role counters expose duplicate Open/Resume submissions.
  property var launches: ({
      editor: 0,
      terminal: 0
    })
  // Independent fresh window evidence supplied only by the fake runtime.
  property var proven: []
  // The sibling terminal fails before an explicit role-only retry.
  property bool terminalFails: false
  // Async completion advances the actual owner flow once per operation.
  property string phase: 'first'
  // Exact registered checkout selected for each operation.
  property string activePath: Quickshell.env('ARANEA_FLOW_PATH')
  QmlTest {
    id: t
  }
  Projects.ProjectRuntime {
    id: processes
    captureActive: true
  }
  Projects.ProjectsController {
    id: owner
    captureActive: true
    runtime: ({
        sessionId: 'flow-session',
        processRunner: processes.processRunner,
        snapshot: function () {
          return {
            available: true,
            observedAt: Date.now(),
            currentWorkspaceId: 1,
            workspaces: [
              {
                id: 1,
                windows: 2
              }
            ],
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
          t.check(id >= 2, 'occupied workspace preserved')
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
          t.equal(spec.cwd, root.activePath, 'launch receives exact canonical checkout path')
          var counts = Object.assign({}, root.launches)
          counts[spec.role]++
          root.launches = counts
          if (spec.role === 'terminal' && root.terminalFails) {
            done({
              ok: false,
              status: 'failed',
              code: 'LAUNCH_FAILED'
            })
            return
          }
          done({
            ok: true,
            status: 'accepted',
            identity: {
              pid: spec.role === 'editor' ? 100 : 200,
              startTime: '123',
              sessionId: 'flow-session',
              token: spec.token
            }
          })
        },
        observe: function (spec, baseline, done) {
          var binding = {
            projectId: spec.projectId,
            checkoutId: spec.checkoutId,
            role: spec.role,
            workspaceId: spec.workspaceId,
            address: root.activePath === Quickshell.env('ARANEA_FLOW_PATH') ? (spec.role === 'editor' ? '0x100' : '0x200') : (spec.role === 'editor' ? '0x300' : '0x400'),
            pid: spec.role === 'editor' ? 100 : 200,
            appId: spec.token,
            sessionId: 'flow-session',
            evidence: {
              mode: 'process-app-id',
              processVerified: true,
              startTime: '123'
            }
          }
          root.proven = root.proven.concat([binding])
          done({
            ok: true,
            status: 'observed',
            binding: binding
          })
        }
      })
    onOperationChanged: function (op) {
      if (op.state !== 'completed')
        return
      t.equal(op.projectId, registry.projects[0].id, 'owner reports registered opaque project identity')
      t.equal(op.checkoutId, registry.projects[0].lastCheckoutId, 'owner reports selected checkout identity')
      if (root.phase === 'first') {
        t.equal(op.outcome, 'observed', 'initial Open observes both roles')
        t.equal(root.launches, {
          editor: 1,
          terminal: 1
        }, 'first Open launches each role once')
        root.phase = 'resume'
        Qt.callLater(root.submit)
      } else if (root.phase === 'resume') {
        t.equal(root.launches, {
          editor: 1,
          terminal: 1
        }, 'Resume focuses each observed role without a duplicate launch')
        root.terminalFails = true
        root.activePath = Quickshell.env('ARANEA_FLOW_SIBLING')
        root.phase = 'failed-new'
        Qt.callLater(root.submit)
      } else if (root.phase === 'failed-new') {
        t.equal(op.outcome, 'partial', 'failed terminal preserves observed editor')
        t.equal(root.launches, {
          editor: 2,
          terminal: 2
        }, 'sibling checkout first Open submits each role once')
        root.terminalFails = false
        root.phase = 'retry'
        Qt.callLater(function () {
          root.submit('terminal')
        })
      } else {
        t.equal(op.outcome, 'observed', 'targeted failed-role retry completes')
        t.equal(root.launches, {
          editor: 2,
          terminal: 3
        }, 'retry targets only failed terminal')
        var snapshot = owner.snapshot()
        var records = Records.records(owner.registry, snapshot)
        t.equal(records[0].target.checkoutId, op.checkoutId, 'search projects exact owner checkout identity')
        t.check(records[0].detail.indexOf(root.activePath) === 0, 'search reports exact registered path')
        t.equal(records[0].action, 'resume', 'search resumes freshly proven owner evidence')
        console.log('FLOW_SNAPSHOT ' + JSON.stringify(snapshot))
        t.done()
      }
    }
  }
  // Submit explicit IDs through the production owner request boundary.
  function submit(role, newRole) {
    var p = owner.registry.projects[0]
    var checkout = p.checkouts.filter(function (c) {
      return c.path === root.activePath
    })[0]
    var payload = {
      projectId: p.id,
      checkoutId: checkout.id
    }
    if (role)
      payload.retryRole = role
    if (newRole)
      payload.newWindowRole = newRole
    var result = owner.request(payload)
    if (!result.ok)
      console.log('FLOW_REFUSED ' + JSON.stringify(result))
    t.check(result.ok, 'owner accepts exact registered request')
  }
  Component.onCompleted: {
    owner.captureActive = false
    owner.refresh()
    t.waitFor(function () {
      return owner.registryReady && !owner.refreshing
    }, 5000, 'real registry loaded', function () {
      t.equal(owner.registry.projects[0].checkouts[0].path, Quickshell.env('ARANEA_FLOW_PATH'), 'owner reads JSON registered path')
      submit()
    })
  }
}
