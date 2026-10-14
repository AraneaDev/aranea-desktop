// Held native reads verify bounded summaries preserve receipt and output identity.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // External native refresh completions remain under fixture control.
  property var calls: []
  QmlTest {
    id: t
  }
  Projects.ProjectActionsClient {
    id: client
    captureActive: true
  }
  // Valid retained identifiers exercise production identity checks.
  function id(prefix, n) {
    return prefix + '-00000000-0000-4000-8000-00000000000' + n
  }
  // One authoritative immutable receipt with mutable process observations.
  function run(n, checkout) {
    return {
      id: id('r', n),
      requestId: id('req', n),
      projectId: id('p', 1),
      checkoutId: checkout || id('c', 1),
      actionId: id('a', n),
      definitionRevision: 1,
      definitionHash: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      processState: 'running',
      createdAt: n,
      updatedAt: n
    }
  }
  // Actual backend response, including its authoritative retained state.
  function reply(index, row, revision) {
    calls[index].done(0, JSON.stringify({
      ok: true,
      error: null,
      run: row,
      state: {
        revision: revision,
        definitions: [],
        runs: [row],
        requests: []
      }
    }), '')
  }
  Component.onCompleted: t.step(50, function () {
    client.projectId = id('p', 1)
    client.checkoutId = id('c', 1)
    client.runner = function (argv, input, done) {
      host.calls.push({
        method: argv[argv.length - 1],
        payload: JSON.parse(input || '{}'),
        done: done
      })
    }
    var first = run(1), second = run(2), other = run(3, id('c', 2))
    client.snapshot = {
      revision: 1,
      definitions: [],
      runs: [first, second, other],
      requests: []
    }
    client.runId = first.id
    client.requestId = first.requestId
    client.currentRun = first
    client.output = 'retained output'
    client.observeSummary()
    t.equal(calls.length, 0, 'capture refuses native summary reads')
    client.captureActive = false
    // This property is set dynamically only once production introduces the contract.
    if (client.summaryObservationActive !== undefined)
      client.summaryObservationActive = true
    client.observeSummary()
    t.equal(calls.length, 1, 'visible overview reads one protected exact-checkout run')
    if (!calls.length) {
      t.done()
      return
    }
    t.equal(calls[0].method, 'refresh', 'summary reads native observation without starting')
    t.equal(calls[0].payload.runId, second.id, 'newest exact-checkout protected run selected')
    client.observeSummary()
    t.equal(calls.length, 1, 'held callback bounds native summary work to one slot')
    reply(0, Object.assign({}, second, {
      processState: 'succeeded',
      updatedAt: 9
    }), 2)
    t.equal(client.snapshot.runs[0].processState, 'succeeded', 'authoritative native outcome updates summary snapshot')
    t.equal(client.runId, first.id, 'background read preserves selected accepted run')
    t.equal(client.requestId, first.requestId, 'background read preserves accepted request')
    t.equal(client.currentRun.id, first.id, 'background read preserves log selection')
    t.equal(client.output, 'retained output', 'background read preserves current output')
    client.snapshot = {
      revision: 3,
      definitions: [],
      runs: [first, second, other],
      requests: []
    }
    client.observeSummary()
    t.equal(calls[1].payload.runId, first.id, 'bounded passes rotate across protected runs')
    client.checkoutId = id('c', 2)
    client.observeSummary()
    t.equal(calls.length, 2, 'selection keeps prior physical read bounded')
    reply(1, Object.assign({}, first, {
      processState: 'failed'
    }), 4)
    t.equal(client.snapshot.revision, 3, 'late old-checkout summary cannot publish')
    client.observeSummary()
    t.equal(calls[2].payload.runId, other.id, 'next read uses newly selected exact checkout')
    client.captureActive = true
    reply(2, Object.assign({}, other, {
      processState: 'failed'
    }), 5)
    client.captureActive = false
    client.observeSummary()
    t.equal(calls.length, 4, 'capture completion releases its bounded physical slot')
    client.summaryObservationActive = false
    reply(3, Object.assign({}, other, {
      processState: 'failed'
    }), 6)
    t.equal(client.snapshot.revision, 3, 'hidden summary callback cannot publish')
    client.observeSummary()
    t.equal(calls.length, 4, 'hidden overview does not observe native state')
    client.summaryObservationActive = true
    client.observeSummary()
    reply(4, Object.assign({}, other, {
      definitionHash: 'bad',
      processState: 'failed'
    }), 7)
    t.equal(client.snapshot.revision, 3, 'mismatched immutable run identity cannot publish')
    t.check(!!client.summaryError, 'failed observation remains visible independently of receipt')
    t.equal(client.runId, first.id, 'failed observation never replaces accepted receipt')
    client.observeSummary()
    client.snapshot = {
      revision: 9,
      definitions: [],
      runs: [other],
      requests: []
    }
    reply(5, Object.assign({}, other, {
      processState: 'failed'
    }), 8)
    t.equal(client.snapshot.revision, 9, 'older backend revision cannot overwrite newer evidence')
    client.observeSummary()
    client.stop(other.id)
    calls[7].done(0, JSON.stringify({
      ok: true,
      error: null,
      run: Object.assign({}, other, {
        processState: 'stopped'
      })
    }), '')
    reply(6, other, 12)
    t.equal(client.snapshot.revision, 9, 'old summary cannot overwrite newer Stop observation without a snapshot envelope')
    t.equal(client.currentRun.processState, 'stopped', 'explicit Stop selection remains authoritative')
    client.observeSummary()
    client.restart(other.id)
    reply(8, other, 13)
    t.equal(client.snapshot.revision, 9, 'explicit Restart invalidates held summary publication')
    client.captureActive = true
    client.captureActive = false
    client.currentRun = other
    client.observationActive = true
    var beforePoll = calls.length
    client.observeSummary()
    t.equal(calls.length, beforePoll, 'selected protected run already has a native poll and is not duplicated')
    client.captureActive = true
    t.done()
  })
}
