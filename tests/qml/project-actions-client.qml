// Actual narrow client: capture refusal, stale reads and uncertain submission recovery.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Held process boundary calls drive actual client callbacks.
  property var calls: []
  // Stable retained receipt for exact-identity assertions.
  property string accepted: 'r-00000000-0000-4000-8000-000000000001'
  QmlTest {
    id: t
  }
  Projects.ProjectActionsClient {
    id: client
    projectId: 'p-00000000-0000-4000-8000-000000000001'
    checkoutId: 'c-00000000-0000-4000-8000-000000000001'
    observationActive: false
    runner: function (argv, input, done) {
      root.calls.push({
        argv: argv,
        input: input,
        done: done
      })
    }
  }
  // Separate real-client transport exercises authoritative restart refusal and receipt aliases.
  property var restartCalls: []
  // Original-run refusals never emit a new acceptance event.
  property int restartAcceptances: 0
  Projects.ProjectActionsClient {
    id: restartClient
    projectId: 'p-00000000-0000-4000-8000-000000000001'
    checkoutId: 'c-00000000-0000-4000-8000-000000000001'
    observationActive: false
    runner: function (argv, input, done) {
      root.restartCalls.push({
        argv: argv,
        input: input,
        done: done
      })
    }
    onRunAccepted: root.restartAcceptances++
  }
  // A separate damaged-envelope transport cannot hide a new request receipt.
  property var conflictingCalls: []
  Projects.ProjectActionsClient {
    id: conflictingClient
    projectId: 'p-00000000-0000-4000-8000-000000000001'
    checkoutId: 'c-00000000-0000-4000-8000-000000000001'
    runner: function (argv, input, done) {
      root.conflictingCalls.push(done)
    }
  }
  // Every probe uses a fresh actual client; only the held native transport is injected.
  property var probeCalls: []
  Component {
    id: probeFactory
    Projects.ProjectActionsClient {
      property int acceptanceCount: 0
      projectId: 'p-00000000-0000-4000-8000-000000000001'
      checkoutId: 'c-00000000-0000-4000-8000-000000000001'
      onRunAccepted: acceptanceCount++
      runner: function (argv, input, done) {
        root.probeCalls.push(done)
      }
    }
  }
  // Missing or malformed immutable evidence must never authorize another submission.
  function rejectEnvelope(label, fields, retainedFields, receiptFields, refusal, recover) {
    var subject = probeFactory.createObject(root)
    var original = root.run()
    if (refusal)
      subject.currentRun = original
    probeCalls = []
    if (refusal)
      subject.restart(original.id)
    else
      subject.start(original.actionId, 3)
    probeCalls[0](0, '00000000-0000-4000-8000-000000000011', '')
    var damaged = Object.assign({}, original, fields)
    var response = root.envelope(damaged, 1)
    response.state.runs = [Object.assign({}, damaged, retainedFields)]
    response.state.requests = [Object.assign({
        requestId: 'req-00000000-0000-4000-8000-000000000011',
        runId: damaged.id
      }, receiptFields)]
    if (refusal) {
      response.ok = false
      response.error = {
        code: 'STOP_UNCONFIRMED',
        message: 'Protected original',
        recovery: 'Refresh or Stop'
      }
      response.state.requests = []
    }
    var callbackError = ''
    try {
      probeCalls[1](response.ok ? 0 : 1, JSON.stringify(response), '')
    } catch (e) {
      callbackError = String(e)
    }
    t.equal(callbackError, '', label + ' callback safely rejects malformed evidence')
    t.check(subject.submissionUncertain && subject.acceptanceCount === 0, label + ' remains uncertain without fresh acceptance')
    t.equal(subject.runId, '', label + ' never publishes an unusable or wrong run')
    if (recover) {
      subject.refresh()
      try {
        probeCalls[2](0, JSON.stringify(response), '')
      } catch (e) {
        t.check(false, 'malformed snapshot callback throws: ' + e)
      }
      t.check(subject.submissionUncertain && subject.acceptanceCount === 0 && !subject.runId, 'malformed snapshot cannot bypass exact receipt recovery')
    }
    t.check(!subject.start(original.actionId, 3), label + ' blocks duplicate submission')
    subject.destroy()
  }
  Projects.ProjectActionsClient {
    id: nativeClient
    projectId: 'p-native'
    checkoutId: 'c-native'
    backendPath: '/usr/bin/false'
    observationActive: false
  }
  // A queued process starts after capture toggles, exercising actual stdin I/O.
  property var captureStdinResult: null
  Projects.ProjectActionsClient {
    id: captureRace
    projectId: 'p-00000000-0000-4000-8000-000000000001'
    checkoutId: 'c-00000000-0000-4000-8000-000000000001'
    backendPath: '/usr/bin/tee'
    runner: function (argv, input, done) {
      var process = captureRace.processComponent.createObject(captureRace, {
        command: argv,
        input: input,
        completion: function (code, text, diagnostics) {
          root.captureStdinResult = text
          done(code, text, diagnostics)
        }
      })
      process.startRequested = true
      process.running = true
      captureRace.captureActive = true
    }
  }
  // Native polling counts actual client requests through the isolated transport.
  property int pollReads: 0
  FloatingWindow {
    visible: true
    implicitWidth: 100
    implicitHeight: 100
    Projects.ProjectActionsClient {
      id: pollClient
      projectId: 'p-00000000-0000-4000-8000-000000000001'
      checkoutId: 'c-00000000-0000-4000-8000-000000000001'
      observationActive: true
      visible: false
      pollInterval: 30
      runner: function (argv, input, done) {
        root.pollReads++
        var result = root.run()
        if (root.pollReads > 1) {
          result.processState = 'succeeded'
          result.submissionUnconfirmed = root.pollReads === 2
          result.exitCode = 0
          result.outcome = result.submissionUnconfirmed ? 'partial' : 'observed'
        }
        done(0, JSON.stringify(root.envelope(result, root.pollReads)), '')
      }
    }
  }
  Timer {
    id: finishPolling
    interval: 100
    onTriggered: {
      t.equal(root.pollReads, 3, 'confirmed terminal cleanup stops polling')
      pollClient.captureActive = true
      pollClient.readRun()
      t.equal(root.pollReads, 3, 'capture stops native polling before process creation')
      pollClient.currentRun = root.run()
      pollClient.captureActive = false
      t.waitFor(function () {
        return root.pollReads === 4
      }, 2000, 'restored visible protected run resumes observation', function () {
        pollClient.captureActive = true
        captureRace.configure({
          name: 'Must remain inert'
        }, 0)
        t.waitFor(function () {
          return root.captureStdinResult !== null
        }, 2000, 'queued native transport closes capture stdin', function () {
          t.equal(root.captureStdinResult, '', 'capture blocks stdin after queued process creation')
          t.done()
        })
      })
    }
  }
  // Deliver a real backend envelope through the injected process boundary.
  function reply(index, data) {
    calls[index].done(data.ok ? 0 : 1, JSON.stringify(data), '')
  }
  // Complete state shape consumed by actual client projections.
  function envelope(run, revision) {
    return {
      ok: true,
      error: null,
      state: {
        revision: revision,
        definitions: [],
        runs: run ? [run] : [],
        requests: run ? [
          {
            requestId: run.requestId,
            runId: run.id
          }
        ] : []
      },
      run: run
    }
  }
  // Immutable semantic tuple for the selected exact checkout.
  function run() {
    return {
      id: accepted,
      requestId: 'req-00000000-0000-4000-8000-000000000001',
      projectId: 'p-00000000-0000-4000-8000-000000000001',
      checkoutId: 'c-00000000-0000-4000-8000-000000000001',
      actionId: 'a-00000000-0000-4000-8000-000000000001',
      definitionRevision: 3,
      definitionHash: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      processState: 'running',
      submissionUnconfirmed: false,
      readiness: 'unknown'
    }
  }
  Component.onCompleted: t.step(0, function () {
    root.rejectEnvelope('absent run identity', {
      id: undefined,
      definitionRevision: undefined,
      definitionHash: undefined
    }, {}, {
      runId: undefined
    }, false, true)
    root.rejectEnvelope('empty run ID', {
      id: ''
    }, {}, {}, false, false)
    root.rejectEnvelope('wrongly typed run ID', {
      id: 17
    }, {}, {}, false, false)
    root.rejectEnvelope('malformed run ID', {
      id: 'r-invalid'
    }, {}, {}, false, false)
    root.rejectEnvelope('run ID with trailing newline', {
      id: accepted + '\n'
    }, {}, {}, false, false)
    root.rejectEnvelope('hash with trailing newline', {
      definitionHash: root.run().definitionHash + '\n'
    }, {}, {}, false, false)
    root.rejectEnvelope('absent primary request ID', {
      requestId: undefined
    }, {}, {}, false, false)
    root.rejectEnvelope('malformed primary request ID', {
      requestId: 'req-invalid'
    }, {}, {}, false, false)
    root.rejectEnvelope('absent definition revision', {
      definitionRevision: undefined
    }, {}, {}, false, false)
    root.rejectEnvelope('string definition revision', {
      definitionRevision: '3'
    }, {}, {}, false, false)
    root.rejectEnvelope('fractional definition revision', {
      definitionRevision: 1.5
    }, {}, {}, false, false)
    root.rejectEnvelope('zero definition revision', {
      definitionRevision: 0
    }, {}, {}, false, false)
    root.rejectEnvelope('absent definition hash', {
      definitionHash: undefined
    }, {}, {}, false, false)
    root.rejectEnvelope('malformed definition hash', {
      definitionHash: 'short'
    }, {}, {}, false, false)
    root.rejectEnvelope('missing retained hash', {}, {
      definitionHash: undefined
    }, {}, false, false)
    root.rejectEnvelope('missing receipt run ID', {}, {}, {
      runId: undefined
    }, false, false)
    root.rejectEnvelope('wrong project', {
      projectId: 'p-00000000-0000-4000-8000-000000000002'
    }, {}, {}, false, false)
    root.rejectEnvelope('wrong checkout', {
      checkoutId: 'c-00000000-0000-4000-8000-000000000002'
    }, {}, {}, false, false)
    root.rejectEnvelope('wrong action', {
      actionId: 'a-00000000-0000-4000-8000-000000000002'
    }, {}, {}, false, false)
    root.rejectEnvelope('original refusal missing hash', {
      definitionHash: undefined
    }, {}, {}, true, false)
    root.rejectEnvelope('original refusal missing revision', {
      definitionRevision: undefined
    }, {}, {}, true, false)
    var original = root.run()
    restartClient.currentRun = original
    restartClient.snapshot = envelope(original, 1).state
    restartClient.restart(original.id)
    restartCalls[0].done(0, '00000000-0000-4000-8000-000000000007', '')
    var refused = envelope(original, 2)
    refused.ok = false
    refused.error = {
      code: 'STOP_UNCONFIRMED',
      message: 'Original run remains protected',
      recovery: 'Refresh or Stop original run'
    }
    restartCalls[1].done(1, JSON.stringify(refused), '')
    t.check(!restartClient.submissionUncertain && restartClient.currentRun.id === original.id, 'authoritative failed restart retains original without wedged new receipt')
    t.equal(restartClient.error.code, 'STOP_UNCONFIRMED', 'failed restart retains backend recovery error')
    t.equal(restartAcceptances, 0, 'original refusal never emits fresh acceptance')
    if (restartClient.submissionUncertain) {
      t.done()
      return
    }
    t.check(restartClient.refreshRun(original.id), 'failed restart permits exact original Refresh')
    restartCalls[2].done(0, JSON.stringify(envelope(original, 3)), '')
    t.check(restartClient.stop(original.id), 'failed restart permits exact original Stop')
    restartCalls[3].done(1, JSON.stringify(refused), '')
    restartClient.restart(original.id)
    restartCalls[4].done(0, '00000000-0000-4000-8000-000000000008', '')
    var coalesced = envelope(original, 4)
    coalesced.state.requests = [
      {
        requestId: 'req-00000000-0000-4000-8000-000000000008',
        runId: original.id
      }
    ]
    restartCalls[5].done(0, JSON.stringify(coalesced), '')
    t.check(!restartClient.submissionUncertain && restartClient.runId === original.id, 'exact aliased request receipt accepts coalesced original run')
    t.equal(restartAcceptances, 1, 'coalesced acceptance emits one accepted identity')
    restartClient.restart(original.id)
    restartCalls[6].done(0, '00000000-0000-4000-8000-000000000009', '')
    var orphan = Object.assign({}, original, {
      requestId: 'req-00000000-0000-4000-8000-000000000009'
    })
    var orphanResponse = envelope(orphan, 5)
    orphanResponse.state.requests = []
    restartCalls[7].done(0, JSON.stringify(orphanResponse), '')
    t.check(restartClient.submissionUncertain, 'success orphan without exact durable receipt remains uncertain')
    conflictingClient.currentRun = original
    conflictingClient.snapshot = envelope(original, 1).state
    conflictingClient.restart(original.id)
    conflictingCalls[0](0, '00000000-0000-4000-8000-000000000010', '')
    var inconsistent = envelope(original, 6)
    inconsistent.ok = false
    inconsistent.error = refused.error
    var other = Object.assign({}, original, {
      id: 'r-00000000-0000-4000-8000-000000000002'
    })
    inconsistent.state.runs.push(other)
    inconsistent.state.requests = [
      {
        requestId: 'req-00000000-0000-4000-8000-000000000010',
        runId: other.id
      }
    ]
    conflictingCalls[1](1, JSON.stringify(inconsistent), '')
    t.check(conflictingClient.submissionUncertain, 'original-run refusal cannot hide a mismatched new request receipt')

    client.captureActive = true
    client.refresh()
    client.start('a-00000000-0000-4000-8000-000000000001', 3)
    client.configure({}, 0)
    client.remove('a-00000000-0000-4000-8000-000000000001', 0)
    client.observeRun(accepted)
    client.refreshRun(accepted)
    client.stop(accepted)
    client.restart(accepted)
    client.logs(accepted)
    client.openPreview(accepted)
    client.checkAvailability()
    t.equal(calls.length, 0, 'capture blocks every native read, UUID and mutation before process')
    client.captureActive = false
    client.refresh()
    client.refresh()
    reply(1, envelope(null, 2))
    reply(0, envelope(null, 1))
    t.equal(client.snapshot.revision, 2, 'stale snapshot cannot roll state back')
    t.check(client.start('a-00000000-0000-4000-8000-000000000001', 3), 'explicit start allowed')
    t.check(!client.start('a-00000000-0000-4000-8000-000000000001', 3), 'pending UUID prevents double submission')
    t.equal(calls[2].argv, ['/usr/bin/cat', '/proc/sys/kernel/random/uuid'], 'request ID comes from native UUID helper')
    calls[2].done(0, '00000000-0000-4000-8000-000000000001\n', '')
    t.equal(calls[3].argv.slice(-1), ['start'], 'fixed command map invokes backend')
    var payload = JSON.parse(calls[3].input)
    t.equal(payload.expectedDefinitionRevision, 3, 'displayed revision is submitted on stdin')
    t.equal(payload.checkoutId, 'c-00000000-0000-4000-8000-000000000001', 'exact selected checkout retained')
    client.refresh()
    client.refresh()
    reply(5, envelope(null, 5))
    calls[4].done(1, '', 'old error')
    reply(3, envelope(run(), 6))
    t.equal(client.runId, accepted, 'snapshot generation cannot erase late acceptance')
    t.equal(client.currentRun.id, accepted, 'accepted run is exposed')
    client.logs(accepted)
    reply(6, Object.assign(envelope(run(), 7), {
      output: '<b>literal</b>',
      truncated: true
    }))
    t.equal(client.output, '<b>literal</b>', 'log bytes stay plaintext data')
    t.check(client.truncated, 'truncation retained')
    var wrongRun = Object.assign({}, run(), {
      id: 'r-00000000-0000-4000-8000-000000000002'
    })
    var wrongRead = calls.length
    client.logs(accepted)
    reply(wrongRead, Object.assign(envelope(wrongRun, 8), {
      output: 'wrong run output',
      truncated: false
    }))
    t.check(client.currentRun.id === accepted && client.runId === accepted, 'wrong exact-run-ID callback cannot replace retained run')
    t.check(client.output === '<b>literal</b>' && client.truncated && client.snapshot.revision === 7, 'wrong exact-run-ID callback cannot replace logs or snapshot')
    t.equal(client.error.code, 'SUBMISSION_UNCONFIRMED', 'wrong exact-run-ID callback reports recovery error')
    calls.splice(wrongRead, 1)
    client.projectId = 'p-00000000-0000-4000-8000-000000000002'
    t.check(!client.currentRun, 'selection change never attaches old receipt to new project')
    t.equal(client.runId, accepted, 'accepted receipt retained for recovery')
    client.projectId = 'p-00000000-0000-4000-8000-000000000001'
    client.checkoutId = 'c-00000000-0000-4000-8000-000000000001'
    client.disconnect()
    client.start('a-00000000-0000-4000-8000-000000000002', 1)
    calls[7].done(0, '00000000-0000-4000-8000-000000000002', '')
    calls[8].done(1, '', 'transport lost')
    t.check(client.submissionUncertain, 'lost response stays uncertain')
    t.check(!client.start('a-00000000-0000-4000-8000-000000000002', 1), 'uncertain submission cannot automatically or explicitly duplicate')
    client.refresh()
    var late = run()
    late.requestId = 'req-00000000-0000-4000-8000-000000000002'
    late.actionId = 'a-00000000-0000-4000-8000-000000000002'
    var recovered = envelope(late, 9)
    recovered.state.requests = [
      {
        requestId: late.requestId,
        runId: late.id
      }
    ]
    reply(9, recovered)
    t.equal(client.runId, accepted, 'snapshot recovers exact request receipt without start retry')
    t.check(!client.submissionUncertain, 'receipt resolves local uncertainty')
    t.equal(calls.filter(function (c) {
      return c.argv[c.argv.length - 1] === 'start'
    }).length, 2, 'refresh never resubmits')
    client.captureActive = true
    var count = calls.length
    client.readRun()
    t.equal(calls.length, count, 'poll capture guard is before I/O')
    client.captureActive = false
    client.disconnect()
    client.start('a-00000000-0000-4000-8000-000000000003', 1)
    calls[10].done(0, '00000000-0000-4000-8000-000000000003', '')
    reply(11, {
      ok: true,
      error: null,
      state: null
    })
    t.check(client.submissionUncertain, 'success-shaped response without run never permits duplicate start')
    nativeClient.captureActive = true
    t.check(!nativeClient.start('a-native', 1), 'native production runner remains inert in capture')
    nativeClient.captureActive = false
    t.check(nativeClient.start('a-native', 1), 'native production transport reads UUID and writes backend stdin')
    t.waitFor(function () {
      return !nativeClient.pending
    }, 2000, 'native helper and failed backend complete', function () {
      t.check(/^req-[0-9a-f-]{36}$/.test(nativeClient.requestId), 'real kernel UUID identity is retained')
      t.check(nativeClient.submissionUncertain, 'actual process failure retains uncertainty')
      var readIndex = root.calls.length
      client.logs(root.accepted)
      root.reply(readIndex, Object.assign(root.envelope(root.run(), 10), {
        output: 'old exact-run logs',
        truncated: false
      }))
      var next = root.run()
      next.id = 'r-00000000-0000-4000-8000-000000000099'
      readIndex = root.calls.length
      client.observeRun(next.id)
      root.reply(readIndex, root.envelope(next, 11))
      t.equal(client.output, '', 'switching exact run clears previous run logs')
      var cleanup = root.run()
      cleanup.id = next.id
      cleanup.processState = 'succeeded'
      cleanup.submissionUnconfirmed = true
      cleanup.exitCode = 0
      cleanup.outcome = 'partial'
      readIndex = root.calls.length
      client.refreshRun(next.id)
      root.reply(readIndex, {
        ok: false,
        state: root.envelope(cleanup, 12).state,
        run: cleanup,
        error: {
          code: 'STOP_UNCONFIRMED',
          message: 'Cleanup remains protected.',
          recovery: 'Refresh or Stop.'
        }
      })
      t.check(client.available && client.currentRun.submissionUnconfirmed && client.currentRun.exitCode === 0, 'nonzero backend response retains successful main result and protected cleanup')
      t.equal(client.error.code, 'STOP_UNCONFIRMED', 'backend cleanup refusal remains structured')
      pollClient.observeRun(root.accepted)
      pollClient.readRun()
      t.equal(root.pollReads, 1, 'hidden retained run cannot poll')
      pollClient.visible = true
      t.check(pollClient.visible, 'poll fixture visible gate enabled')
      t.check(!!pollClient.currentRun && !pollClient.pending, 'poll fixture has selected retained evidence')
      t.waitFor(function () {
        return root.pollReads >= 3
      }, 2000, 'terminal cleanup uncertainty stays protected for another poll', function () {
        finishPolling.start()
      })
    })
  })
}
