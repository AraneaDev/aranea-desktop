// Workspace placement: saved records yield empty workspaces, current mode shares.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // A saved environment whose windows are gone, as left by an earlier session.
  function staleEnvironment(id, workspaceId, createdAt) {
    return {
      id: id,
      projectId: 'p-one',
      checkoutId: 'c-one',
      activationId: 'a-99999999-0000-4000-8000-' + ('000000000000' + workspaceId).slice(-12),
      workspaceId: workspaceId,
      sessionId: 'session-old',
      createdAt: createdAt,
      checkoutSnapshot: {
        id: 'c-one',
        path: '/repo',
        branch: 'main',
        primary: true
      },
      profileSnapshot: {
        id: 'f-one',
        name: 'Code',
        revision: 1,
        roles: ['editor'],
        tools: {
          editorId: 'code',
          terminalId: null,
          agentId: null
        }
      },
      resolvedTools: {
        editorId: 'code',
        terminalId: null,
        agentId: null
      }
    }
  }
  // Records on 1-4 with no windows there; only workspace 5 is occupied.
  property var state: ({
      schemaVersion: 2,
      revision: 0,
      projects: [
        {
          id: 'p-one',
          commonDir: '/repo/.git',
          lastCheckoutId: 'c-one',
          workspaceMode: 'dedicated',
          tools: {},
          associations: [
            {
              checkoutId: 'c-one',
              mode: 'dedicated',
              workspaceId: 1,
              separate: false
            }
          ],
          environments: [staleEnvironment('e-11111111-0000-4000-8000-000000000002', 2, 1000), staleEnvironment('e-11111111-0000-4000-8000-000000000004', 4, 2000)],
          checkouts: [
            {
              id: 'c-one',
              path: '/repo',
              branch: 'main',
              primary: true
            }
          ],
          profiles: [
            {
              id: 'f-one',
              name: 'Code',
              revision: 1,
              roles: ['editor'],
              tools: {
                editorId: 'code',
                terminalId: null,
                agentId: null
              }
            },
            {
              id: 'f-both',
              name: 'Both',
              revision: 1,
              roles: ['editor', 'terminal'],
              tools: {
                editorId: 'code',
                terminalId: 'kitty',
                agentId: null
              }
            }
          ]
        }
      ]
    })
  property var occupied: [
    {
      id: 5,
      windows: 1
    }
  ]
  // Focused workspace reported by the fake compositor.
  property var currentWorkspace: 5
  property var launched: []
  property var focused: []
  property var nativeBindings: []
  property int serial: 0
  // The environment the dedicated start created, for later mode checks.
  property string firstEnvironment: ''
  QmlTest {
    id: t
  }
  Projects.ProjectsController {
    id: owner
    roleTimeout: 40
    runtime: ({
        sessionId: 'session-one',
        snapshot: function () {
          return {
            available: true,
            currentWorkspaceId: root.currentWorkspace,
            workspaces: root.occupied,
            windows: root.nativeBindings.map(function (binding) {
              return {
                address: binding.address,
                pid: binding.pid,
                workspaceId: binding.workspaceId
              }
            })
          }
        },
        validateBindings: function (bindings, done) {
          done({
            bindings: root.nativeBindings,
            missing: []
          })
        },
        observe: function (spec, baseline, done) {
          var binding = {
            environmentId: spec.environmentId,
            projectId: spec.projectId,
            checkoutId: spec.checkoutId,
            sessionId: spec.sessionId,
            role: spec.role,
            workspaceId: spec.workspaceId,
            pid: 420 + root.nativeBindings.length,
            address: '0x' + (420 + root.nativeBindings.length),
            evidence: {
              mode: 'process-only',
              processVerified: true,
              startTime: '123',
              verifiedAt: Date.now()
            }
          }
          root.nativeBindings = root.nativeBindings.concat([binding])
          done({
            ok: true,
            status: 'observed',
            binding: binding
          })
        },
        createEnvironmentId: function (done) {
          root.serial++
          done('e-00000000-0000-4000-8000-' + ('000000000000' + root.serial).slice(-12))
        },
        focusWorkspace: function (id, done) {
          root.focused.push(id)
          if (!root.occupied.some(function (row) {
            return row.id === id
          }))
            root.occupied = root.occupied.concat([
              {
                id: id,
                windows: 0
              }
            ])
          root.currentWorkspace = id
          done({
            ok: true,
            status: 'observed'
          })
        },
        launch: function (spec, done) {
          root.launched.push(spec)
          done({
            ok: true,
            status: 'accepted',
            identity: {
              pid: 420 + root.nativeBindings.length,
              startTime: '123',
              sessionId: spec.sessionId,
              token: spec.token
            }
          })
        }
      })
    metadataRunner: function (argv, done) {
      done({
        ok: true,
        metadata: {
          path: '/repo',
          commonDir: '/repo/.git',
          checkouts: [
            {
              path: '/repo',
              branch: 'main',
              primary: true
            }
          ]
        }
      })
    }
    toolsRunner: function (argv, done) {
      done({
        editors: [
          {
            id: 'code',
            available: true,
            supported: true
          }
        ],
        terminals: [
          {
            id: 'kitty',
            available: true,
            supported: true
          }
        ],
        agents: [],
        defaults: {}
      })
    }
    storeRunner: function (argv, done, input) {
      Qt.callLater(function () {
        if (input) {
          var request = JSON.parse(input)
          var next = JSON.parse(JSON.stringify(root.state))
          if (request.action === 'environment-register') {
            next.projects[0].environments.push(request.args.environment)
            next.projects[0].lastProfileId = request.args.environment.profileSnapshot.id
          }
          if (request.action === 'environment-associate')
            next.projects[0].environments.forEach(function (env) {
              if (env.id === request.args.environmentId)
                env.workspaceId = request.args.workspaceId
            })
          next.revision++
          root.state = next
        }
        done({
          ok: true,
          state: JSON.parse(JSON.stringify(root.state))
        })
      })
    }
  }
  function payload(n, profile) {
    return {
      projectId: 'p-one',
      checkoutId: 'c-one',
      profileId: profile || 'f-one',
      profileRevision: 1,
      activationId: 'a-00000000-0000-4000-8000-' + ('000000000000' + n).slice(-12)
    }
  }
  function ready(request, done) {
    owner.prepareEnvironment(request)
    t.waitFor(function () {
      var response = owner.prepareEnvironment(request)
      return response.ok || response.error.code !== 'OWNER_NOT_READY'
    }, 1500, 'preflight finishes', function () {
      done(owner.prepareEnvironment(request))
    })
  }
  function complete(response, done) {
    t.waitFor(function () {
      return owner.operation(response.operationId).state === 'completed'
    }, 1500, 'accepted operation completes', done)
  }
  // The failure code of a completed operation, or '' when it did not fail.
  function failure(op) {
    var step = (op.steps || []).filter(function (row) {
      return row.role === 'operation' && row.status === 'failed'
    })[0]
    return step ? step.code : ''
  }
  // Rewrite the fake registry, then let the owner reload it.
  function setState(change, done) {
    var next = JSON.parse(JSON.stringify(root.state))
    change(next.projects[0])
    next.revision++
    root.state = next
    owner.refresh()
    t.waitFor(function () {
      return owner.registryReady && !owner.refreshing && owner.registry.revision === root.state.revision
    }, 1500, 'registry reload', done)
  }
  function environmentNamed(id) {
    return root.state.projects[0].environments.filter(function (env) {
      return env.id === id
    })[0]
  }
  Component.onCompleted: {
    owner.refresh()
    t.waitFor(function () {
      return owner.registryReady && !owner.refreshing
    }, 1500, 'owner ready', dedicatedTests)
  }
  // Saved records on 1-4 without windows no longer push a start to 5.
  function dedicatedTests() {
    t.equal(owner.chooseEnvironmentWorkspace(owner.runtime.snapshot()), 1, 'records without windows do not reserve their workspaces')
    var request = payload(1)
    ready(request, function (prepared) {
      t.check(prepared.ok, 'dedicated start prepares')
      t.equal(owner.chooseEnvironmentWorkspace(owner.runtime.snapshot()), 2, 'in-flight lease still blocks its workspace')
      var started = owner.startEnvironment(request)
      complete(started, function () {
        t.equal(failure(owner.operation(started.operationId)), '', 'dedicated start completes')
        t.equal(launched[0].workspaceId, 1, 'dedicated start lands on the lowest empty workspace')
        root.firstEnvironment = started.environmentId
        sharedTests()
      })
    })
  }
  function sharedTests() {
    // Task 3 replaces this body.
    t.done()
  }
}
