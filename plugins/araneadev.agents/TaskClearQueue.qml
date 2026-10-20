// Serialize exact inactive-task dismissals through the existing activity owner.
// The frozen IDs go in sets, each removed in one store write; a long list is
// split so one set fits one IPC argument. Injected clients use the same narrow
// observation interface.
// qmllint disable missing-property
import QtQuick
import "../araneadev.activity/ActivityLogic.js" as ActivityLogic

Item {
  id: queue
  // The host supplies its persistent activity observer.
  property var client: null
  // Capture and showcase modes never submit task mutations.
  property bool captureActive: false
  // Remains true between individual accepted set dismissals.
  property bool pending: false
  // A failed or uncertain batch retains its explanation.
  property var error: null
  // Exact IDs frozen at the deliberate clear action, not yet submitted.
  property var remaining: []
  // Marks the submitted set; only its observed completion can advance the queue.
  property string currentId: ''
  // Tasks the store kept because they were still running.
  property int refused: 0
  // Largest serialized set, well under the IPC argument and reply limits.
  property int setBytes: 16000
  // Deferred continuations cannot cross cancellation or client changes.
  property int generation: 0
  onClientChanged: cancel()
  onCaptureActiveChanged: {
    if (captureActive)
      cancel()
  }
  // Cancel unsubmitted work; an accepted owner operation remains owned there.
  function cancel(): void {
    generation++
    remaining = []
    currentId = ''
    pending = false
  }
  // Clearing uses only distinct bounded task identities, never provider text.
  function start(ids: var): bool {
    if (captureActive || pending || !client || client.captureActive || client.pending || !Array.isArray(ids) || !ids.length || ids.length > 700 || ids.some(function (id, index) {
      return !ActivityLogic.validId(id) || ids.indexOf(id) !== index
    }))
      return false
    generation++
    error = null
    refused = 0
    remaining = ids.slice()
    pending = true
    next()
    return true
  }
  // The next IDs whose JSON array fits setBytes; at least one.
  function takeSet(): var {
    var set = [], used = 2
    while (remaining.length) {
      let size = ActivityLogic.utf8Length(JSON.stringify(remaining[0])) + 1
      if (set.length && used + size > setBytes)
        break
      set.push(remaining[0])
      remaining = remaining.slice(1)
      used += size
    }
    return set
  }
  // The store rechecks liveness for every task immediately before removal.
  function next(): void {
    if (!pending || captureActive || !client)
      return
    if (!remaining.length) {
      pending = false
      client.refresh()
      if (refused > 0)
        error = {
          code: 'TASK_LIVE',
          message: refused === 1 ? '1 task was still running and was kept.' : refused + ' tasks were still running and were kept.'
        }
      return
    }
    currentId = 'set-' + generation + '-' + remaining.length
    if (!client.dismissMany(takeSet()))
      fail(client.error || {
        code: 'CLEAR_REFUSED',
        message: 'Task clearing could not start. Refresh activity and try again.'
      })
  }
  // The current set is done; move on to the next one.
  function advance(): void {
    currentId = ''
    var token = generation
    Qt.callLater(function () {
      if (queue.pending && token === queue.generation)
        queue.next()
    })
  }
  // Partial progress is retained; uncertain work is never automatically repeated.
  function fail(reason: var): void {
    cancel()
    error = reason
    if (!captureActive && client && client.available !== false)
      client.refresh()
  }
  Connections {
    target: queue.client
    ignoreUnknownSignals: true
    // A failed list read leaves the batch running (details reads never set error).
    function onErrorChanged() {
      var error = queue.client.error
      if (!queue.pending || !error || ['snapshot', 'snapshotPage'].indexOf(queue.client.errorMethod) >= 0)
        return
      queue.fail(error)
    }
    function onPendingChanged() {
      if (!queue.pending || queue.client.pending)
        return
      var token = queue.generation, setId = queue.currentId
      Qt.callLater(function () {
        if (queue.pending && token === queue.generation && setId === queue.currentId && !queue.client.pending)
          queue.fail(queue.client.error || {
            code: 'CLEAR_UNCONFIRMED',
            message: 'Task clearing was not confirmed. Refresh activity before trying again.'
          })
      })
    }
    function onOperationChanged(op) {
      if (!queue.pending || !queue.currentId || op.action !== 'dismiss-many' || op.id !== queue.client.operationId || op.ownerId !== queue.client.ownerId || op.state !== 'completed')
        return
      if (op.outcome !== 'observed') {
        queue.fail(op.error || {
          code: 'CLEAR_UNCONFIRMED',
          message: 'Task clearing was not confirmed. Refresh activity before trying again.'
        })
        return
      }
      queue.refused += op.result && op.result.refused > 0 ? op.result.refused : 0
      queue.advance()
    }
  }
}
