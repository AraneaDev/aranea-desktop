// Actual client logic with a held transport: detection cache and sequential saves.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Held backend calls: argv, parsed input and completion.
  property var calls: []
  QmlTest {
    id: t
  }
  Projects.ProjectActionsClient {
    id: client
    projectId: 'p-00000000-0000-4000-8000-000000000001'
    checkoutId: 'c-00000000-0000-4000-8000-000000000001'
  }
  // Finish one held call with a backend envelope.
  function reply(index, response) {
    calls[index].done(response.ok ? 0 : 1, JSON.stringify(response), '')
  }
  // Minimal configure-ready draft.
  function draft(name) {
    return {
      name: name,
      kind: 'command',
      argv: ['make', name],
      cwdRelative: '.',
      timeoutSeconds: 300,
      previewUrl: null
    }
  }
  // Store snapshot after a save.
  function stateAfter(count) {
    return {
      revision: count,
      definitions: [],
      runs: [],
      requests: []
    }
  }
  Component.onCompleted: t.step(50, function () {
    client.runner = function (argv, input, done) {
      root.calls.push({
        argv: argv,
        input: JSON.parse(input),
        done: done
      })
    }
    t.check(client.detect(false), 'detect submits')
    t.equal(calls[0].argv[1], 'detect', 'fixed backend method')
    t.equal(calls[0].input.checkoutId, 'c-00000000-0000-4000-8000-000000000001', 'exact checkout submitted')
    t.check(client.detecting, 'detecting while held')
    reply(0, {
      ok: true,
      state: null,
      error: null,
      projectId: client.projectId,
      checkoutId: client.checkoutId,
      suggestions: [
        {
          key: 'makefile:.:test',
          definition: draft('test')
        }
      ],
      sources: []
    })
    t.check(!client.detecting, 'detection finished')
    t.equal(client.detection.suggestions.length, 1, 'cached for the selection')
    t.check(!client.detect(false), 'cache hit does not resubmit')
    t.check(client.detect(true), 'force refreshes')
    reply(1, {
      ok: false,
      state: null,
      error: {
        code: 'DETECTION_FAILED',
        message: 'Commands could not be read from this checkout.'
      }
    })
    t.equal(client.detection.error.code, 'DETECTION_FAILED', 'failure cached with error')
    t.check(client.detect(false), 'an errored cache entry may retry')
    // A reply for a superseded checkout is not published.
    client.checkoutId = 'c-00000000-0000-4000-8000-000000000002'
    reply(2, {
      ok: true,
      state: null,
      error: null,
      projectId: client.projectId,
      checkoutId: 'c-00000000-0000-4000-8000-000000000001',
      suggestions: [],
      sources: []
    })
    t.equal(client.detection, null, 'other checkout has no cache yet')
    t.equal(client.detections['p-00000000-0000-4000-8000-000000000001|c-00000000-0000-4000-8000-000000000001'].error, null, 'late reply lands only under its own checkout key')
    t.equal(client.detections['p-00000000-0000-4000-8000-000000000001|c-00000000-0000-4000-8000-000000000002'], undefined, 'superseded reply is not published for either key')
    // Sequential Add all stops at the first refusal.
    calls = []
    t.check(client.addSuggestions([draft('a'), draft('b'), draft('c')]), 'queue accepted')
    t.check(!client.addSuggestions([draft('d')]), 'second queue refused while active')
    t.equal(calls.length, 1, 'one save at a time')
    t.equal(calls[0].argv[1], 'configure', 'saves through configure')
    t.equal(calls[0].input.definition.name, 'a', 'first draft')
    reply(0, {
      ok: true,
      state: stateAfter(1),
      error: null
    })
    t.equal(calls.length, 2, 'next save after acknowledgement')
    reply(1, {
      ok: false,
      state: stateAfter(1),
      error: {
        code: 'CAPACITY_EXCEEDED',
        message: 'Too many actions.'
      }
    })
    t.equal(calls.length, 2, 'refusal stops the queue')
    t.equal(client.addResult.added, 1, 'one added')
    t.equal(client.addResult.total, 3, 'of three')
    t.equal(client.addResult.error.code, 'CAPACITY_EXCEEDED', 'refusal retained')
    // Queue stops on selection change.
    calls = []
    t.check(client.addSuggestions([draft('x'), draft('y')]), 'second queue')
    client.projectId = 'p-00000000-0000-4000-8000-000000000002'
    reply(0, {
      ok: true,
      state: stateAfter(2),
      error: null
    })
    t.equal(calls.length, 1, 'queue stops on selection change')
    t.equal(client.addQueue.length, 0, 'queue cleared')
    // (a) Capture mid-Add-all clears the queue; a later unrelated save advances nothing.
    calls = []
    t.check(client.addSuggestions([draft('m'), draft('n')]), 'queue before capture')
    client.captureActive = true
    client.captureActive = false
    t.equal(client.addQueue.length, 0, 'capture clears queue')
    t.check(!client.addActive, 'capture ends Add all')
    t.check(client.configure(draft('own'), undefined), 'unrelated save accepted')
    reply(1, {
      ok: true,
      state: stateAfter(3),
      error: null
    })
    t.equal(calls.length, 2, 'unrelated ack saves nothing further')
    t.equal(client.addResult.added, 0, 'unrelated ack not counted')
    calls = []
    t.check(client.addSuggestions([draft('q')]), 'Add all accepted again')
    reply(0, {
      ok: true,
      state: stateAfter(4),
      error: null
    })
    t.equal(client.addResult.added, 1, 'fresh queue completes')
    // (b) Selection change while the last save is in flight.
    calls = []
    t.check(client.addSuggestions([draft('last')]), 'single-item queue')
    client.projectId = 'p-00000000-0000-4000-8000-000000000003'
    t.check(!client.addActive, 'selection change ends Add all with save in flight')
    t.check(client.addSuggestions([draft('new1'), draft('new2')]), 'new queue on new project')
    t.equal(calls.length, 2, 'new queue issued its first save')
    reply(0, {
      ok: true,
      state: stateAfter(5),
      error: null
    })
    t.equal(calls.length, 2, 'late ack neither advances nor counts')
    t.equal(client.addCount, 0, 'late ack not counted')
    t.check(client.pending, 'late ack does not release the new save')
    reply(1, {
      ok: true,
      state: stateAfter(6),
      error: null
    })
    t.equal(calls.length, 3, 'own ack advances')
    t.done()
  })
}
