// Real client transport held at identity, acceptance and observation boundaries.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host
  // Hold kernel identity completion to exercise asynchronous dismissal intent.
  property var identityDone: null
  // Capture the real client transport and hold owner replies.
  property var calls: []
  QmlTest {
    id: t
  }
  Menu.DesktopSearchSources {
    id: sources
    active: false
    projectClient: entry.projectClient
    snapshotReader: function () {
      return {
        compositorAvailable: false
      }
    }
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  Component.onCompleted: t.step(60, function () {
    entry.projectController.captureActive = true
    entry.gitClient.captureActive = true
    entry.activityClient.captureActive = true
    entry.actionClient.captureActive = true
    entry.projectController.state = {
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-one',
          lastCheckoutId: 'c-one',
          checkouts: [
            {
              id: 'c-one',
              path: '/one'
            }
          ],
          profiles: [
            {
              id: 'f-one',
              revision: 2,
              name: 'Editor'
            }
          ]
        }
      ]
    }
    entry.projectId = 'p-one'
    entry.opened = true
    var client = entry.projectClient
    client.identityRunner = function (done) {
      host.identityDone = done
    }
    client.runner = function (argv, done) {
      host.calls.push({
        method: argv[2],
        args: argv.slice(3),
        done: done
      })
    }
    t.check(typeof entry.startProfile === 'function', 'presentation owns explicit profile start intent')
    if (typeof entry.startProfile !== 'function') {
      t.done()
      return
    }
    entry.startProfile('f-one', 2)
    t.check(entry.opened, 'UUID and preflight keep Projects open')
    host.identityDone('00000000-0000-4000-8000-000000000001')
    t.equal(entry.awaitedLaunchId, client.activationId, 'async UUID binds to this user action')
    var start = host.calls[0]
    t.equal(JSON.parse(start.args[0]).checkoutId, 'c-one', 'Start uses current selected checkout')
    start.done(0, JSON.stringify({
      ok: true,
      operationId: 'op-one',
      environmentId: 'e-one'
    }), '')
    t.check(!entry.opened, 'validated matching acceptance closes Projects')
    entry.open('{}')
    client.operationChanged({
      id: 'op-one',
      environmentId: 'e-one',
      state: 'completed',
      outcome: 'partial'
    })
    client.submissionAccepted('op-one', 'e-one')
    t.check(entry.opened, 'later outcomes and duplicate receipts cannot hide reopened Projects')
    entry.startProfile('f-one', 2)
    entry.open('{}')
    host.identityDone('00000000-0000-4000-8000-000000000002')
    t.equal(entry.awaitedLaunchId, '', 'reopening before async UUID clears dismissal intent')
    client.captureActive = true
    client.captureActive = false
    entry.startProfile('f-one', 2)
    entry.clearDismissalIntent()
    host.identityDone('00000000-0000-4000-8000-000000000003')
    t.equal(entry.awaitedLaunchId, '', 'cancelled readiness cannot reacquire dismissal intent')
    client.captureActive = true
    client.captureActive = false
    entry.returnEnvironment({
      projectId: 'p-one',
      environmentId: 'e-one'
    })
    client.submissionAccepted('op-return', 'e-one')
    t.check(entry.opened, 'Return acceptance never dismisses')
    client.returnObserved('other')
    t.check(entry.opened, 'another environment focus never dismisses')
    client.returnObserved('e-one')
    t.check(!entry.opened, 'exact observed Return closes Projects')
    entry.open('{}')
    client.returnObserved('e-one')
    t.check(entry.opened, 'late Return cannot close reopened Projects')
    client.captureActive = true
    client.captureActive = false
    t.check(typeof client.cancelPreparation === 'function', 'client exposes safe readiness cancellation')
    if (typeof client.cancelPreparation !== 'function') {
      t.done()
      return
    }
    host.calls = []
    entry.startProfile('f-one', 2)
    host.identityDone('00000000-0000-4000-8000-000000000004')
    t.check(!client.canCancelPreparation && !client.cancelPreparation(), 'in-flight acceptance cannot be cancelled')
    var held = host.calls[0]
    held.done(0, JSON.stringify({
      ok: false,
      error: {
        code: 'OWNER_NOT_READY',
        message: 'Preparing'
      }
    }), '')
    t.check(client.canCancelPreparation, 'known unaccepted readiness can be cancelled')
    var identity = client.activationId, target = JSON.stringify(client.environmentTarget)
    entry.cancelPreparation()
    t.check(!client.pending && !client.preparing, 'cancel stops local readiness retry')
    t.check(!client.requestError && !client.error, 'cancel clears transient Preparing feedback')
    t.equal(client.activationId, identity, 'cancel retains diagnostic activation')
    t.equal(JSON.stringify(client.environmentTarget), target, 'cancel retains exact immutable target')
    held.done(0, JSON.stringify({
      ok: true,
      operationId: 'late',
      environmentId: 'late'
    }), '')
    t.check(entry.opened && !entry.awaitedLaunchId && !client.operationId, 'late cancelled callback cannot accept or rearm dismissal')
    client.acceptanceUnknown = true
    t.check(!client.cancelPreparation(), 'unknown acknowledgement cannot be cancelled')
    client.acceptanceUnknown = false
    client.operationId = 'accepted'
    t.check(!client.cancelPreparation(), 'accepted operation cannot be cancelled')
    client.captureActive = true
    client.captureActive = false
    client.operationId = ''
    host.calls = []
    entry.startProfile('f-one', 2)
    var state = JSON.parse(JSON.stringify(entry.projectController.state))
    state.projects[0].checkouts.push({
      id: 'c-two',
      path: '/two'
    })
    state.projects[0].lastCheckoutId = 'c-two'
    entry.projectController.state = state
    t.equal(entry.launchIntent, null, 'checkout inspection clears only prior dismissal intent')
    host.identityDone('00000000-0000-4000-8000-000000000005')
    var originalStart = host.calls[0]
    t.equal(JSON.parse(originalStart.args[0]).checkoutId, 'c-one', 'selection during UUID wait never retargets original launch')
    t.equal(host.calls.filter(function (call) {
      return call.method === 'startEnvironment'
    }).length, 1, 'inspection never replays original activation')
    originalStart.done(0, JSON.stringify({
      ok: true,
      operationId: 'op-inspected',
      environmentId: 'e-inspected'
    }), '')
    t.check(entry.opened, 'acceptance for previously inspected target never dismisses current view')
    t.check(client.pending && !client.submitting, 'accepted native work remains observed independently')
    var acceptedGeneration = client.generation
    entry.close()
    entry.open('{}')
    t.check(client.pending && client.operationId === 'op-inspected' && client.generation === acceptedGeneration && !client.captureActive, 'accepted operation observation survives ordinary close and reopen')
    t.check(entry.startProfile('f-one', 2), 'another deliberate Start is allowed while accepted work observes')
    host.identityDone('00000000-0000-4000-8000-000000000006')
    t.equal(JSON.parse(host.calls[host.calls.length - 1].args[0]).checkoutId, 'c-two', 'later deliberate Start uses newly selected checkout')
    client.captureActive = true
    client.captureActive = false
    client.operationId = ''
    host.calls = []
    client.snapshot = {
      sessionId: 's'
    }
    entry.startProfile('f-one', 2)
    host.identityDone('00000000-0000-4000-8000-000000000007')
    var uncertainTarget = JSON.stringify(client.environmentTarget), uncertainId = client.activationId
    host.calls[0].done(0, JSON.stringify({
      ok: true,
      operationId: 'op-contradictory',
      environmentId: 'e-contradictory',
      error: {
        code: 'FAILED'
      }
    }), '')
    t.check(entry.opened && client.acceptanceUnknown && !client.operationId, 'contradictory initial acknowledgement stays unknown and open')
    t.equal(JSON.stringify(client.environmentTarget), uncertainTarget, 'contradiction preserves immutable original target')
    t.equal(client.activationId, uncertainId, 'contradiction preserves original activation')
    // Keep testing the retained boundary even when the initial guard regresses.
    client.pending = false
    client.acceptanceUnknown = true
    client.operationId = ''
    client.checkEnvironmentActivation()
    var receipt = {
      ok: true,
      found: true,
      sessionId: 's',
      activationId: uncertainId,
      operationId: 'op-retained',
      environmentId: 'e-retained',
      error: {
        code: 'FAILED'
      },
      operation: {
        id: 'op-retained',
        environmentId: 'e-retained',
        activationId: uncertainId,
        sessionId: 's',
        projectId: 'p-one',
        checkoutId: 'c-two',
        startTarget: JSON.parse(uncertainTarget),
        state: 'completed'
      }
    }
    host.calls[host.calls.length - 1].done(0, JSON.stringify(receipt), '')
    t.check(entry.opened && client.acceptanceUnknown && !client.operationId, 'contradictory retained acknowledgement stays unknown and open')
    t.equal(JSON.stringify(client.environmentTarget), uncertainTarget, 'retained contradiction preserves immutable target')
    t.equal(host.calls.filter(function (call) {
      return call.method === 'startEnvironment'
    }).length, 1, 'contradictory lookup never replays Start')
    client.pending = false
    client.acceptanceUnknown = true
    entry.opened = true
    t.check(entry.startProfile('f-one', 2, true), 'explicit uncertainty escape starts independent work')
    host.identityDone('00000000-0000-4000-8000-000000000008')
    t.check(client.activationId !== uncertainId, 'uncertainty escape creates fresh activation')
    t.equal(client.unresolvedEnvironmentActivations[0].target, JSON.parse(uncertainTarget), 'escape archives exact earlier target')
    var newStart = host.calls[host.calls.length - 1]
    newStart.done(0, JSON.stringify({
      ok: true,
      error: null,
      operationId: 'op-new',
      environmentId: 'e-new'
    }), '')
    t.check(!entry.opened, 'matching fresh acceptance dismisses after uncertainty escape')
    entry.open('{}')
    client.submissionAccepted('op-new', 'e-new')
    t.check(entry.opened, 'duplicate fresh acceptance cannot dismiss reopened Projects')
    client.captureActive = true
    client.captureActive = false
    client.operationId = ''
    // Synchronous identity and acknowledgement must bind the same explicit intent.
    var heldRunner = client.runner, heldIdentityRunner = client.identityRunner
    client.identityRunner = function (done) {
      done('00000000-0000-4000-8000-000000000009')
    }
    client.runner = function (argv, done) {
      if (argv[2] === 'startEnvironment')
        done(0, JSON.stringify({
          ok: true,
          operationId: 'op-sync',
          environmentId: 'e-sync'
        }), '')
    }
    entry.startProfile('f-one', 2)
    t.check(!entry.opened, 'request notification binds synchronous identity and acceptance before dismissal')
    entry.open('{}')
    client.runner = heldRunner
    client.identityRunner = heldIdentityRunner
    client.captureActive = true
    client.captureActive = false
    client.operationId = ''
    host.calls = []
    client.recoverEnvironment({
      projectId: 'p-one',
      environmentId: 'e-saved',
      retryRole: 'editor'
    })
    host.identityDone('00000000-0000-4000-8000-000000000010')
    var recoveryTarget = JSON.stringify(client.environmentTarget), recoveryId = client.activationId
    host.calls[0].done(0, JSON.stringify({
      ok: true,
      operationId: 'op-recovery',
      environmentId: 'e-saved',
      error: {
        code: 'FAILED'
      }
    }), '')
    t.check(client.acceptanceUnknown && !client.operationId && entry.opened, 'contradictory recovery acknowledgement stays unknown and open')
    client.pending = false
    client.acceptanceUnknown = true
    client.operationId = ''
    client.checkEnvironmentActivation()
    host.calls[host.calls.length - 1].done(0, JSON.stringify({
      ok: true,
      found: true,
      error: {
        code: 'FAILED'
      },
      sessionId: 's',
      activationId: recoveryId,
      operationId: 'op-recovery',
      environmentId: 'e-saved',
      operation: {
        id: 'op-recovery',
        projectId: 'p-one',
        environmentId: 'e-saved',
        activationId: recoveryId,
        sessionId: 's',
        recoveryTarget: JSON.parse(recoveryTarget),
        state: 'completed'
      }
    }), '')
    t.check(client.acceptanceUnknown && !client.operationId && entry.opened, 'contradictory retained recovery stays unknown and open')
    t.equal(JSON.stringify(client.environmentTarget), recoveryTarget, 'recovery contradiction retains immutable target')
    t.equal(client.activationId, recoveryId, 'recovery contradiction retains activation')
    t.equal(host.calls.filter(function (call) {
      return call.method === 'recoverEnvironment'
    }).length, 1, 'retained recovery never replays role dispatch')
    client.captureActive = true
    client.captureActive = false
    client.acceptanceUnknown = false
    client.operationId = ''
    // Malformed success envelopes must never look like known refusal or acceptance.
    var malformedReplies = [
      {
        ok: 'true',
        operationId: 'op-invalid',
        environmentId: 'e-invalid'
      },
      {
        ok: 'true'
      }
    ]
    malformedReplies.forEach(function (reply, index) {
      host.calls = []
      entry.startProfile('f-one', 2)
      host.identityDone('00000000-0000-4000-8000-00000000002' + index)
      var target = JSON.stringify(client.environmentTarget)
      host.calls[0].done(0, JSON.stringify(reply), '')
      t.check(client.acceptanceUnknown && entry.opened && !client.operationId, 'nonboolean initial success remains unconfirmed ' + index)
      t.equal(JSON.stringify(client.environmentTarget), target, 'malformed initial reply retains target ' + index)
      client.pending = false
      client.acceptanceUnknown = true
      client.checkEnvironmentActivation()
      var original = JSON.parse(target)
      host.calls[host.calls.length - 1].done(0, JSON.stringify({
        ok: index ? true : 'true',
        found: index ? 'true' : true,
        sessionId: 's',
        activationId: client.activationId,
        operationId: 'op-invalid',
        environmentId: 'e-invalid',
        operation: {
          id: 'op-invalid',
          environmentId: 'e-invalid',
          activationId: client.activationId,
          projectId: original.projectId,
          checkoutId: original.checkoutId,
          sessionId: 's',
          startTarget: original,
          state: 'completed'
        }
      }), '')
      t.check(client.acceptanceUnknown && entry.opened && !client.operationId, 'nonboolean retained success remains unconfirmed ' + index)
      t.equal(host.calls.length, 2, 'malformed success does not replay Start or observe an unconfirmed operation ' + index)
      client.captureActive = true
      client.captureActive = false
      client.acceptanceUnknown = false
      client.operationId = ''
    })
    host.calls = []
    entry.startProfile('f-one', 2)
    host.identityDone('00000000-0000-4000-8000-000000000030')
    host.calls[0].done(1, '', 'lost acknowledgement')
    client.checkEnvironmentActivation()
    var retainedTarget = JSON.parse(JSON.stringify(client.environmentTarget))
    host.calls[host.calls.length - 1].done(0, JSON.stringify({
      ok: true,
      found: true,
      error: null,
      sessionId: 's',
      activationId: client.activationId,
      operationId: 'op-confirmed',
      environmentId: 'e-confirmed',
      operation: {
        id: 'op-confirmed',
        environmentId: 'e-confirmed',
        activationId: client.activationId,
        projectId: retainedTarget.projectId,
        checkoutId: retainedTarget.checkoutId,
        sessionId: 's',
        startTarget: retainedTarget,
        state: 'completed'
      }
    }), '')
    t.check(!entry.opened && !client.acceptanceUnknown, 'conforming retained acceptance dismisses matching original intent')
    entry.open('{}')
    client.submissionAccepted('op-confirmed', 'e-confirmed')
    t.check(entry.opened, 'retained acceptance cannot dismiss reopened Projects twice')
    client.captureActive = true
    client.captureActive = false
    client.operationId = ''
    client.snapshot = {
      sessionId: 's',
      availability: {
        compositor: true
      },
      projects: entry.projectController.state.projects,
      environments: [
        {
          id: 'e-search',
          projectId: 'p-one',
          checkoutId: 'old',
          workspaceId: 9,
          profileSnapshot: {
            name: 'Original terminal'
          },
          checkoutSnapshot: {
            branch: 'old',
            path: '/old'
          },
          observedRoles: []
        }
      ]
    }
    sources.active = true
    sources.publish()
    t.check(sources.records.some(function (r) {
      return r.type === 'project-environment'
    }), 'typed environment survives real search source publication')
    t.check(sources.activate('project-environment:e-search'), 'search Return activates retained exact environment')
    var searchCall = host.calls[host.calls.length - 1]
    t.equal(searchCall.method, 'returnEnvironment', 'environment search dispatches focus-only owner method')
    t.equal(JSON.parse(searchCall.args[0]), {
      projectId: 'p-one',
      environmentId: 'e-search'
    }, 'search Return carries no current checkout override')
    sources.active = false
    client.captureActive = true
    t.done()
  })
}
