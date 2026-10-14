// Prepared launches exercise the real owner with isolated store and native boundaries.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Isolated schema-2 registry snapshots exercise real owner transactions.
  property var state: ({
      schemaVersion: 2,
      revision: 0,
      projects: [
        {
          id: 'p-one',
          commonDir: '/repo/.git',
          lastCheckoutId: 'c-one',
          tools: {},
          associations: [],
          environments: [],
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
              id: 'f-two',
              name: 'Terminal',
              revision: 1,
              roles: ['terminal'],
              tools: {
                editorId: null,
                terminalId: 'kitty',
                agentId: null
              }
            }
          ]
        }
      ]
    })
  // Fresh fake desktop occupancy includes unrelated native windows.
  property var occupied: [
    {
      id: 1,
      windows: 2
    }
  ]
  // Native attempt specs expose exact environment and workspace targeting.
  property var launched: []
  // Captured store mutations prove acceptance ordering and revision guards.
  property var writes: []
  // Focus targets reveal reservation changes without moving unrelated windows.
  property var focused: []
  // A missing Git identity fails preflight before acceptance.
  property bool checkoutValid: true
  // Fresh tool probe availability controls only the requested supported adapter.
  property bool installed: true
  // Revision conflicts fail persistence after the owner has accepted.
  property bool conflict: false
  // Native focus acceptance alone cannot satisfy Return.
  property bool focusObserved: true
  // An external window can occupy a reservation after initial focus.
  property bool raceAtFocus: false
  // Missing native callbacks exercise the real role deadline.
  property bool silentLaunch: false
  // One stalled external read must not block the shared queue forever.
  property bool hangNextRead: false
  // Post-dispatch unrelated occupancy must hold all later ambiguous work.
  property bool occupyOnLaunch: false
  // Deterministic fixture UUID suffixes remain distinct across preparations.
  property int serial: 0
  // The first accepted receipt is retained throughout eviction and recovery checks.
  property var first: null
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
            workspaces: root.occupied,
            windows: []
          }
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
          if (root.raceAtFocus) {
            root.occupied = root.occupied.concat([
              {
                id: id,
                windows: 1
              }
            ])
            root.raceAtFocus = false
          }
          done({
            ok: root.focusObserved,
            status: root.focusObserved ? 'observed' : 'unconfirmed'
          })
        },
        launch: function (spec, done) {
          root.launched.push(spec)
          if (root.occupyOnLaunch)
            root.occupied = root.occupied.filter(function (row) {
              return row.id !== spec.workspaceId
            }).concat([
              {
                id: spec.workspaceId,
                windows: 1
              }
            ])
          if (!root.silentLaunch)
            done({
              ok: false,
              code: 'FIXTURE_FAILURE'
            })
        }
      })
    metadataRunner: function (argv, done) {
      done({
        ok: root.checkoutValid,
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
            available: root.installed,
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
      if (!input && root.hangNextRead) {
        root.hangNextRead = false
        return
      }
      Qt.callLater(function () {
        if (input) {
          var request = JSON.parse(input)
          root.writes.push(request)
          if (root.conflict) {
            done({
              ok: false,
              error: {
                code: 'REGISTRY_CONFLICT',
                message: 'changed'
              }
            })
            return
          }
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
  // Independent explicit activations use stable opaque identities.
  function payload(n, profile) {
    return {
      projectId: 'p-one',
      checkoutId: 'c-one',
      profileId: profile || 'f-one',
      profileRevision: 1,
      activationId: 'a-00000000-0000-4000-8000-' + ('000000000000' + n).slice(-12)
    }
  }
  // Repeated prepare reads cannot accept work or mutate the registry.
  function ready(request, done) {
    owner.prepareEnvironment(request)
    t.waitFor(function () {
      var response = owner.prepareEnvironment(request)
      return response.ok || response.error.code !== 'OWNER_NOT_READY'
    }, 1500, 'preflight finishes', function () {
      done(owner.prepareEnvironment(request))
    })
  }
  // Wait on observable completion rather than assuming dispatch callback order.
  function complete(response, done) {
    t.waitFor(function () {
      return owner.operation(response.operationId).state === 'completed'
    }, 1500, 'accepted operation completes', done)
  }
  Component.onCompleted: {
    t.check(typeof owner.startEnvironment === 'function', 'owner implements prepared environment acceptance')
    if (typeof owner.startEnvironment !== 'function') {
      t.done()
      return
    }
    owner.refresh()
    t.waitFor(function () {
      return owner.registryReady && !owner.refreshing
    }, 1500, 'owner ready', function () {
      var request = payload(1)
      t.equal(owner.startEnvironment(request).error.code, 'OWNER_NOT_READY', 'start without lease is explicit refusal')
      t.equal(owner.operations.length, 0, 'refusal creates no operation')
      ready(request, function (prepared) {
        t.check(prepared.ok, 'valid checkout and installed profile prepare')
        t.equal(writes.length, 0, 'preflight performs no writes')
        t.equal(launched.length, 0, 'preflight launches nothing')
        t.equal(focused.length, 0, 'preflight never focuses')
        t.equal(owner.chooseEnvironmentWorkspace(owner.runtime.snapshot()), 3, 'lease reserves workspace against legacy allocator')
        root.first = owner.startEnvironment(request)
        t.check(first.ok && !!first.environmentId, 'accepted receipt includes exact environment')
        t.equal(writes.length, 0, 'acceptance precedes persistence')
        t.equal(owner.startEnvironment(request).operationId, first.operationId, 'duplicate activation coalesces')
        complete(first, function () {
          t.equal(launched.length, 1, 'duplicate activation dispatches one native attempt')
          t.equal(state.projects[0].environments.length, 1, 'accepted environment persisted once')
          t.equal(state.projects[0].environments[0].checkoutSnapshot.path, '/repo', 'immutable selected checkout recorded')
          t.equal(launched[0].environmentId, first.environmentId, 'runtime receives environment identity')
          t.equal(owner.operation(first.operationId).outcome, 'partial', 'native failure remains honest after workspace focus')
          owner.operations = []
          var receipt = owner.environmentActivation({
            activationId: request.activationId
          })
          t.equal(receipt.operationId, first.operationId, 'receipt survives completed operation eviction')
          receipt.operation.environmentId = 'tampered'
          t.equal(owner.environmentActivation({
            activationId: request.activationId
          }).environmentId, first.environmentId, 'lookup returns detached receipt')
          t.equal(owner.startEnvironment(request).operationId, first.operationId, 'evicted activation still cannot launch twice')
          ready(payload(2, 'f-two'), function () {
            root.raceAtFocus = true
            var second = owner.startEnvironment(payload(2, 'f-two'))
            complete(second, function () {
              t.check(second.environmentId !== first.environmentId, 'later activation creates another environment')
              t.equal(launched[1].role, 'terminal', 'second profile uses its own role')
              t.equal(launched[1].workspaceId, 4, 'occupation after focus reallocates before dispatch')
              t.equal(owner.operation(second.operationId).steps[0].workspaceId, 4, 'workspace observation follows final pre-dispatch reassociation')
              var moved = writes.filter(function (row) {
                return row.action === 'environment-associate'
              })[0]
              t.equal(moved.args.previousWorkspaceId, 3, 'reassociation guards old reservation')
              t.check(Number.isInteger(moved.expectedRevision), 'reassociation guards global revision')
              recoveryTests()
            })
          })
        })
      })
    })
  }
  // Recovery targets immutable environment snapshots and never creates another saved environment.
  function recoveryTests() {
    t.check(typeof owner.recoverEnvironment === 'function', 'owner exposes exact environment role recovery')
    if (typeof owner.recoverEnvironment !== 'function') {
      t.done()
      return
    }
    var target = {
      projectId: 'p-one',
      environmentId: first.environmentId,
      activationId: payload(20).activationId,
      retryRole: 'editor'
    }
    var result = owner.recoverEnvironment(target)
    t.check(result.ok, 'failed role accepts exact recovery')
    t.equal(owner.recoverEnvironment(target).operationId, result.operationId, 'repeated recovery activation coalesces')
    complete(result, function () {
      t.equal(launched.length, 3, 'failed editor retried once')
      t.equal(launched[2].environmentId, first.environmentId, 'recovery retains original environment identity')
      t.equal(launched[2].workspaceId, 2, 'recovery never reallocates existing environment')
      t.equal(state.projects[0].environments.length, 2, 'recovery cannot create a saved environment')
      t.equal(state.projects[0].environments[0].activationId, payload(1).activationId, 'recovery keeps original immutable saved activation')
      t.equal(owner.recoverEnvironment({
        projectId: 'p-one',
        environmentId: first.environmentId,
        activationId: payload(21).activationId,
        newWindowRole: 'terminal'
      }).error.code, 'INVALID_REQUEST', 'recovery refuses a role outside immutable profile')
      root.installed = false
      var observation = owner.recoverEnvironment({
        projectId: 'p-one',
        environmentId: first.environmentId,
        activationId: payload(22).activationId,
        reobserveRole: 'editor'
      })
      complete(observation, function () {
        t.equal(launched.length, 3, 'reobserve never dispatches absent adapters')
        t.equal(owner.operation(observation.operationId).steps[0].code, 'OWNERSHIP_UNCONFIRMED', 'reobserve reaches retained identity guard without requiring installation')
        root.installed = true
        postDispatchRace()
      })
    })
  }
  // A native attempt makes relocation unsafe even when later roles remain unstarted.
  function postDispatchRace() {
    var next = JSON.parse(JSON.stringify(state))
    next.projects[0].profiles.push({
      id: 'f-three',
      name: 'Both',
      revision: 1,
      roles: ['editor', 'terminal'],
      tools: {
        editorId: 'code',
        terminalId: 'kitty',
        agentId: null
      }
    })
    next.revision++
    root.state = next
    ready(payload(30, 'f-three'), function () {
      root.occupyOnLaunch = true
      var before = launched.length, moves = writes.filter(function (row) {
        return row.action === 'environment-associate'
      }).length
      var result = owner.startEnvironment(payload(30, 'f-three'))
      complete(result, function () {
        t.equal(launched.length, before + 1, 'ambiguous occupancy after first native attempt holds remaining roles')
        t.equal(writes.filter(function (row) {
          return row.action === 'environment-associate'
        }).length, moves, 'native attempt forbids reassociation')
        t.equal(owner.operation(result.operationId).outcome, 'partial', 'post-dispatch ambiguity remains honest partial')
        root.occupyOnLaunch = false
        preflightFailures()
      })
    })
  }
  // Missing dependencies and changed identity must refuse before acceptance.
  function preflightFailures() {
    root.installed = false
    ready(payload(3), function (result) {
      t.equal(result.error.code, 'TOOL_MISSING', 'missing editor refuses preflight')
      root.installed = true
      root.checkoutValid = false
      ready(payload(4), function (result) {
        t.equal(result.error.code, 'CHECKOUT_INVALID', 'invalid Git checkout refuses preflight')
        root.checkoutValid = true
        var changed = payload(5)
        changed.profileRevision = 2
        ready(changed, function (result) {
          t.equal(result.error.code, 'PROFILE_CHANGED', 'stale profile revision refuses preflight')
          ready(payload(6), function () {
            root.conflict = true
            var response = owner.startEnvironment(payload(6))
            complete(response, function () {
              t.equal(owner.operation(response.operationId).error.code, 'REGISTRY_CONFLICT', 'persistence conflict fails already accepted operation')
              t.equal(launched.length, 4, 'write conflict launches nothing')
              root.conflict = false
              root.focusObserved = false
              var returned = owner.returnEnvironment({
                projectId: 'p-one',
                environmentId: first.environmentId
              })
              complete(returned, function () {
                t.equal(owner.operation(returned.operationId).outcome, 'failed', 'Return requires observed workspace focus')
                t.equal(launched.length, 4, 'Return never launches missing roles')
                root.focusObserved = true
                ready(payload(7), function () {
                  root.silentLaunch = true
                  var timed = owner.startEnvironment(payload(7))
                  complete(timed, function () {
                    t.equal(owner.operation(timed.operationId).outcome, 'partial', 'native timeout preserves accepted uncertainty')
                    reservationRace()
                  })
                })
              })
            })
          })
        })
      })
    })
  }
  // Another association can claim an empty leased location before the queued start drains.
  function reservationRace() {
    ready(payload(41), function () {
      var result = owner.startEnvironment(payload(41))
      var reserved = owner.operation(result.operationId).workspaceId
      var next = JSON.parse(JSON.stringify(state))
      next.projects[0].associations.push({
        checkoutId: 'c-one',
        mode: 'dedicated',
        workspaceId: reserved,
        separate: false
      })
      next.revision++
      root.state = next
      complete(result, function () {
        t.check(owner.operation(result.operationId).workspaceId !== reserved, 'new environment excludes an empty workspace claimed by another association after preparation')
        leaseLifecycle()
      })
    })
  }
  // Saved metadata after restart is never proof that a missing role is safe to relaunch.
  function restartRecovery() {
    var before = launched.length
    var request = {
      projectId: 'p-one',
      environmentId: first.environmentId,
      activationId: payload(60).activationId,
      retryRole: 'editor'
    }
    var result = owner.recoverEnvironment(request)
    complete(result, function () {
      t.equal(launched.length, before, 'retry after restart cannot duplicate a role from saved metadata alone')
      t.equal(owner.operation(result.operationId).steps.filter(function (step) {
        return step.role === 'editor'
      })[0].code, 'RETRY_NOT_FAILED', 'missing session evidence is held instead of treated as unstarted')
      var observed = owner.recoverEnvironment({
        projectId: 'p-one',
        environmentId: first.environmentId,
        activationId: payload(61).activationId,
        reobserveRole: 'editor'
      })
      complete(observed, function () {
        t.equal(owner.operation(observed.operationId).outcome, 'partial', 'reobserve after restart remains unconfirmed without accepted native proof')
        t.equal(launched.length, before, 'reobserve never adopts or launches from metadata')
        root.silentLaunch = false
        var fresh = owner.recoverEnvironment({
          projectId: 'p-one',
          environmentId: first.environmentId,
          activationId: payload(62).activationId,
          newWindowRole: 'editor'
        })
        complete(fresh, function () {
          t.equal(launched.length, before + 1, 'explicit New window can deliberately start a role after restart')
          t.equal(launched[launched.length - 1].environmentId, first.environmentId, 'explicit New window stays in the exact saved environment')
          t.equal(launched[launched.length - 1].workspaceId, 2, 'explicit New window never relocates the old environment')
          preparationTimeout()
        })
      })
    })
  }
  // A stalled preflight must release the shared queue so ordinary Open remains usable.
  function preparationTimeout() {
    root.hangNextRead = true
    owner.prepareEnvironment(payload(50))
    var legacy = owner.prepareWorkspaceRequest({
      projectId: 'p-one',
      checkoutId: 'c-one'
    })
    t.waitFor(function () {
      return owner.operation(legacy.operationId).state === 'completed'
    }, 6500, 'hung preflight releases shared queue after bounded preparation', function () {
      t.equal(owner.operation(legacy.operationId).outcome, 'observed', 'ordinary workspace preparation survives a stalled profile preflight')
      t.done()
    })
  }
  // Leases survive unrelated registry changes but expire without leaving reservations.
  function leaseLifecycle() {
    ready(payload(9), function () {
      var next = JSON.parse(JSON.stringify(state))
      next.revision++
      root.state = next
      owner.refresh()
      t.waitFor(function () {
        return !owner.refreshing
      }, 1000, 'unrelated refresh completes', function () {
        t.check(owner.prepareEnvironment(payload(9)).ok, 'unrelated revision preserves exact prepared target')
        var began = Date.now()
        t.waitFor(function () {
          return Date.now() - began > 5100
        }, 6000, 'unused lease expires after five seconds', function () {
          t.equal(owner.startEnvironment(payload(9)).error.code, 'OWNER_NOT_READY', 'expired lease cannot accept a start')
          ready(payload(8), function () {
            owner.runtime = Object.assign({}, owner.runtime, {
              sessionId: 'session-two'
            })
            t.equal(owner.startEnvironment(payload(8)).error.code, 'OWNER_NOT_READY', 'owner restart invalidates unused leases')
            t.equal(owner.environmentActivation({
              activationId: payload(1).activationId
            }).found, false, 'restart cannot claim old acceptance')
            t.equal(owner.snapshot().environments[0].status, 'unconfirmed', 'saved environment is not live proof after restart')
            restartRecovery()
          })
        })
      })
    })
  }
}
