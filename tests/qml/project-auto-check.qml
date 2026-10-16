// Uncertain starts, runs and role windows re-check on their own, and never launch anything.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Every held owner call from every client, tagged by the scenario that made it.
  property var calls: []
  // Held backend calls of the actions client.
  property var runCalls: []
  // Role recoveries requested by the details view.
  property var opens: []
  // Launch acknowledgements seen by the start scenarios.
  property int accepted: 0
  // Activation identity shared by every start scenario.
  readonly property string activation: 'a-00000000-0000-4000-8000-000000000001'
  QmlTest {
    id: t
  }
  Component {
    id: clientFactory
    Projects.ProjectClient {
      autoCheckDelays: [50, 100, 150]
      pollInterval: 60000
      runner: function (argv, done) {
        root.calls.push({
          method: argv[2],
          done: done,
          owner: this
        })
      }
      onSubmissionAccepted: root.accepted++
    }
  }
  Projects.ProjectActionsClient {
    id: actions
    projectId: 'p-00000000-0000-4000-8000-000000000001'
    checkoutId: 'c-00000000-0000-4000-8000-000000000001'
    autoCheckDelays: [50, 100, 150]
    observationActive: false
    runner: function (argv, input, done) {
      root.runCalls.push({
        method: argv[1],
        done: done
      })
    }
  }
  Projects.ProjectDetails {
    id: details
    width: 400
    roleAutoDelay: 50
    project: ({
        id: 'p-one',
        name: 'Repo',
        lastCheckoutId: 'c-main',
        workspaceMode: 'dedicated',
        tools: {
          editorId: 'code',
          terminalId: 'kitty'
        },
        checkouts: [
          {
            id: 'c-main',
            path: '/repo',
            branch: 'main',
            primary: true
          }
        ]
      })
    onOpenRequested: function (payload) {
      root.opens.push(payload)
    }
  }
  // Calls to one client for one method.
  function callsOf(client: var, method: string): var {
    return calls.filter(function (call) {
      return call.owner === client && call.method === method
    })
  }
  // Start a profile launch and lose its acknowledgement so acceptance is unknown.
  function uncertainStart(): var {
    var client = clientFactory.createObject(root)
    client.startEnvironment({
      projectId: 'p-one',
      checkoutId: 'c-one',
      profileId: 'f-one',
      profileRevision: 1,
      activationId: activation
    })
    callsOf(client, 'startEnvironment')[0].done(1, '', 'acknowledgement lost')
    return client
  }
  // Lookup answer that proves nothing.
  function notFound(): string {
    return JSON.stringify({
      ok: true,
      sessionId: 'owner-one',
      activationId: activation,
      found: false
    })
  }
  // Lookup answer carrying the accepted start.
  function found(): string {
    var op = {
      id: 'op-start',
      projectId: 'p-one',
      checkoutId: 'c-one',
      environmentId: 'e-00000000-0000-4000-8000-000000000001',
      activationId: activation,
      startTarget: {
        projectId: 'p-one',
        checkoutId: 'c-one',
        profileId: 'f-one',
        profileRevision: 1,
        activationId: activation
      },
      sessionId: 'owner-one',
      state: 'completed',
      outcome: 'partial',
      steps: []
    }
    return JSON.stringify({
      ok: true,
      found: true,
      sessionId: 'owner-one',
      activationId: activation,
      environmentId: op.environmentId,
      operationId: op.id,
      operation: op
    })
  }
  // Never launch: neither start command may follow the first one.
  function neverLaunched(client: var, name: string): void {
    t.equal(callsOf(client, 'startEnvironment').length, 1, name + ': start was sent once')
    t.equal(callsOf(client, 'startAnotherEnvironment').length, 0, name + ': Start another was never called')
  }
  // Answer each automatic lookup with not-found as it arrives.
  function answerLookups(client: var, count: int, next: var): void {
    var seen = 0
    var step = function () {
      if (seen === count) {
        next()
        return
      }
      t.waitFor(function () {
        return callsOf(client, 'environmentActivation').length === seen + 1
      }, 2000, 'lookup ' + (seen + 1) + ' arrives', function () {
        callsOf(client, 'environmentActivation')[seen].done(0, notFound(), '')
        seen++
        step()
      })
    }
    step()
  }
  // Three lookups, then still unknown, never launched.
  function startCase(): void {
    var client = uncertainStart()
    t.check(client.acceptanceUnknown, 'start: acceptance is unknown')
    t.check(client.autoChecking, 'start: automatic checking is scheduled')
    t.equal(client.autoChecksDone, 0, 'start: no lookup yet')
    answerLookups(client, 3, function () {
      t.step(300, function () {
        t.equal(callsOf(client, 'environmentActivation').length, 3, 'start: exactly three lookups')
        t.equal(client.autoChecksDone, 3, 'start: three checks done')
        t.check(!client.autoChecking, 'start: checking has ended')
        t.check(client.acceptanceUnknown, 'start: still unknown after not-found')
        neverLaunched(client, 'start')
        resolveCase()
      })
    })
  }
  // A found answer stops further lookups.
  function resolveCase(): void {
    root.accepted = 0
    var client = uncertainStart()
    answerLookups(client, 1, function () {
      t.waitFor(function () {
        return callsOf(client, 'environmentActivation').length === 2
      }, 2000, 'second lookup arrives', function () {
        callsOf(client, 'environmentActivation')[1].done(0, found(), '')
        t.equal(root.accepted, 1, 'resolve: launch acknowledged')
        t.check(!client.acceptanceUnknown && !client.autoChecking, 'resolve: checking stops')
        t.step(300, function () {
          t.equal(callsOf(client, 'environmentActivation').length, 2, 'resolve: no third lookup')
          neverLaunched(client, 'resolve')
          switchCase()
        })
      })
    })
  }
  // A project switch stops the lookups and discards a late answer.
  function switchCase(): void {
    var client = uncertainStart()
    t.waitFor(function () {
      return callsOf(client, 'environmentActivation').length === 1
    }, 2000, 'switch: first lookup arrives', function () {
      client.stopAutoCheck()
      t.check(!client.autoChecking, 'switch: scheduling stops')
      callsOf(client, 'environmentActivation')[0].done(0, found(), '')
      t.check(client.acceptanceUnknown && !client.operationId, 'switch: a late answer changes nothing')
      t.check(!client.pending, 'switch: the discarded lookup no longer holds the client')
      t.step(300, function () {
        t.equal(callsOf(client, 'environmentActivation').length, 1, 'switch: no further lookups')
        neverLaunched(client, 'switch')
        captureCase()
      })
    })
  }
  // Capture stops the lookups.
  function captureCase(): void {
    var client = uncertainStart()
    t.waitFor(function () {
      return callsOf(client, 'environmentActivation').length === 1
    }, 2000, 'capture: first lookup arrives', function () {
      callsOf(client, 'environmentActivation')[0].done(0, notFound(), '')
      client.captureActive = true
      t.check(!client.autoChecking, 'capture: scheduling stops')
      t.step(300, function () {
        t.equal(callsOf(client, 'environmentActivation').length, 1, 'capture: no further lookups')
        neverLaunched(client, 'capture')
        runCase()
      })
    })
  }
  // An uncertain run re-reads three times and never submits.
  function runCase(): void {
    actions.submissionUncertain = true
    t.check(actions.autoChecking, 'run: automatic checking is scheduled')
    var seen = 0
    var step = function () {
      if (seen === 3) {
        t.step(300, function () {
          t.equal(root.runCalls.length, 3, 'run: exactly three checks')
          t.check(!actions.autoChecking && actions.submissionUncertain, 'run: ended, still uncertain')
          t.equal(root.runCalls.filter(function (call) {
            return call.method === 'start' || call.method === 'restart'
          }).length, 0, 'run: never submits a second run')
          actions.stopAutoCheck()
          roleCase()
        })
        return
      }
      t.waitFor(function () {
        return root.runCalls.length === seen + 1
      }, 2000, 'run check ' + (seen + 1) + ' arrives', function () {
        t.equal(root.runCalls[seen].method, 'snapshot', 'run: check ' + (seen + 1) + ' only reads')
        root.runCalls[seen].done(1, '', 'still unknown')
        seen++
        step()
      })
    }
    step()
  }
  // Completed operation with one unconfirmed terminal step.
  function roleOperation(id: string): var {
    return {
      id: id,
      projectId: 'p-one',
      checkoutId: 'c-main',
      state: 'completed',
      steps: [
        {
          role: 'terminal',
          status: 'unconfirmed',
          reobserveAvailable: true
        }
      ]
    }
  }
  // One automatic reobserve per role and operation.
  function roleCase(): void {
    details.operation = roleOperation('op-a')
    t.waitFor(function () {
      return root.opens.length === 1
    }, 2000, 'role: one automatic reobserve', function () {
      t.equal(root.opens[0], {
        projectId: 'p-one',
        checkoutId: 'c-main',
        reobserveRole: 'terminal'
      }, 'role: reobserves only the unconfirmed role')
      details.operation = roleOperation('op-a')
      details.operation = Object.assign(roleOperation('op-a'), {
        outcome: 'partial'
      })
      t.step(300, function () {
        t.equal(root.opens.length, 1, 'role: later updates of the same operation do not repeat it')
        details.operation = roleOperation('op-b')
        t.waitFor(function () {
          return root.opens.length === 2
        }, 2000, 'role: a new operation gets its own check', function () {
          t.equal(calls.filter(function (call) {
            return call.method === 'startAnotherEnvironment'
          }).length, 0, 'Start another is never called automatically')
          roleGuardCase()
        })
      })
    })
  }
  // Closed windows, display-only views and id-less operations never re-check; reopening does.
  function roleGuardCase(): void {
    var before = root.opens.length
    details.windowOpen = false
    details.operation = roleOperation('op-c')
    t.step(250, function () {
      t.equal(root.opens.length, before, 'role: a closed window never re-checks')
      details.windowOpen = true
      t.waitFor(function () {
        return root.opens.length === before + 1
      }, 2000, 'role: reopening the window schedules the check', function () {
        details.displayOnly = true
        details.operation = roleOperation('op-d')
        t.step(250, function () {
          t.equal(root.opens.length, before + 1, 'role: a display-only view never re-checks')
          details.displayOnly = false
          t.waitFor(function () {
            return root.opens.length === before + 2
          }, 2000, 'role: leaving display-only schedules the check', function () {
            var noId = roleOperation('')
            delete noId.id
            details.operation = noId
            t.step(250, function () {
              t.equal(root.opens.length, before + 2, 'role: an operation without an id is skipped')
              neverAnsweredCase()
            })
          })
        })
      })
    })
  }
  // A lookup that never answers still ends the schedule after three firings.
  function neverAnsweredCase(): void {
    var client = uncertainStart()
    t.waitFor(function () {
      return client.autoChecksDone === 3 && !client.autoChecking
    }, 2000, 'bounded: the schedule ends without answers', function () {
      t.equal(callsOf(client, 'environmentActivation').length, 1, 'bounded: only one lookup was ever sent')
      neverLaunched(client, 'bounded')
      actions.submissionUncertain = false
      root.runCalls = []
      actions.pending = true
      actions.submissionUncertain = true
      t.waitFor(function () {
        return actions.autoChecksDone === 3 && !actions.autoChecking
      }, 2000, 'bounded: the run schedule ends while busy', function () {
        t.equal(root.runCalls.length, 0, 'bounded: a busy client sends no check')
        actions.pending = false
        actions.submissionUncertain = false
        surfaceCase('project')
      })
    })
  }
  // Two projects with two checkouts each, to switch between.
  function surfaceState(project: string, checkout: string): var {
    var checkouts = [
      {
        id: 'c-1',
        path: '/one',
        branch: 'main'
      },
      {
        id: 'c-2',
        path: '/two',
        branch: 'fix'
      }
    ]
    return {
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-a',
          name: 'A',
          tools: {},
          workspaceMode: 'dedicated',
          lastCheckoutId: project === 'p-a' ? checkout : 'c-1',
          checkouts: checkouts
        },
        {
          id: 'p-b',
          name: 'B',
          tools: {},
          workspaceMode: 'dedicated',
          lastCheckoutId: 'c-1',
          checkouts: checkouts
        }
      ]
    }
  }
  // Switching project or checkout, or closing the window, stops both clients through the real surface.
  function surfaceCase(kind: string): void {
    var presentation = entry
    presentation.projectController.captureActive = true
    presentation.projectController.state = surfaceState('p-a', 'c-1')
    presentation.projectId = 'p-a'
    presentation.opened = true
    var client = presentation.projectClient, run = presentation.actionClient
    client.captureActive = false
    run.captureActive = false
    client.autoCheckDelays = [50, 100, 150]
    run.autoCheckDelays = [50, 100, 150]
    client.acceptanceUnknown = false
    run.submissionUncertain = false
    var held = []
    var reads = []
    client.runner = function (argv, done) {
      held.push({
        method: argv[2],
        done: done
      })
    }
    run.runner = function (argv, input, done) {
      reads.push(argv[1])
    }
    client.startEnvironment({
      projectId: 'p-a',
      checkoutId: 'c-1',
      profileId: 'f-one',
      profileRevision: 1,
      activationId: activation
    })
    held[0].done(1, '', 'acknowledgement lost')
    run.submissionTarget = {
      projectId: 'p-a',
      checkoutId: 'c-1',
      actionId: 'a-00000000-0000-4000-8000-000000000001'
    }
    run.requestId = 'req-00000000-0000-4000-8000-000000000001'
    run.submissionUncertain = true
    root.accepted = 0
    t.waitFor(function () {
      return held.length === 2 && reads.length >= 1
    }, 2000, kind + ': first checks arrive', function () {
      var lookups = held.length, snapshots = run.autoChecksDone
      if (kind === 'project')
        presentation.projectId = 'p-b'
      else if (kind === 'checkout')
        presentation.projectController.state = surfaceState('p-a', 'c-2')
      else
        presentation.opened = false
      t.check(!client.autoChecking, kind + ': surface stops the lookups')
      t.check(!run.autoChecking, kind + ': surface stops the run checks')
      held[1].done(0, found(), '')
      t.equal(root.accepted, 0, kind + ': a late answer acknowledges nothing')
      t.step(300, function () {
        t.equal(held.length, lookups, kind + ': no further lookups')
        t.equal(run.autoChecksDone, snapshots, kind + ': no further run checks')
        if (kind === 'project')
          surfaceCase('checkout')
        else if (kind === 'checkout')
          surfaceCase('close')
        else
          t.done()
      })
    })
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    visible: true
    implicitWidth: 1080
    implicitHeight: 720
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Component.onCompleted: {
    entry.gitClient.captureActive = true
    entry.activityClient.captureActive = true
    entry.projectController.captureActive = true
    startCase()
  }
}
